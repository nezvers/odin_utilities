// A TURN client (RFC 5766 / 8656, UDP): the last resort when two NATs cannot be punched through.
//
// A TURN server gives a client a public "relayed address". Whatever is sent to that address is forwarded to the client, and the
// client can send through the server to anybody. Only ONE of the two peers needs it: the other just sends to the relayed address
// like to any public address. The relay carries every byte, so it is only used when it answers before a direct path does and
// the Link switches to a direct path as soon as one packet arrives that way.
//
// Free TURN does not exist anonymously (tool/probe finds many servers alive that all want a login): the user (or the game's
// developer) signs up at a provider with a free tier (Cloudflare, Metered, ExpressTURN, Xirsys, ...) and gives the server
// address, username and password to LinkTurnBegin. Long term credentials only (user + password in the clear, the usual static
// ones); short lived REST credentials work the same, they are just a username and a password too.
//
// Everything runs from LinkUpdate (non blocking): allocation, refresh before the lease ends, permissions for the peers'
// addresses. Memory: fixed, inside the Link.
package p2p

import "core:crypto"
import "core:crypto/hash"
import "core:crypto/hmac"
import "core:net"
import "core:testing"

TURN_ALLOCATE :: u16(0x0003)
TURN_REFRESH :: u16(0x0004)
TURN_SEND_INDICATION :: u16(0x0016)
TURN_DATA_INDICATION :: u16(0x0017)
TURN_CREATE_PERMISSION :: u16(0x0008)
TURN_ATTR_USERNAME :: u16(0x0006)
TURN_ATTR_INTEGRITY :: u16(0x0008)
TURN_ATTR_ERROR :: u16(0x0009)
TURN_ATTR_LIFETIME :: u16(0x000D)
TURN_ATTR_PEER :: u16(0x0012)
TURN_ATTR_DATA :: u16(0x0013)
TURN_ATTR_REALM :: u16(0x0014)
TURN_ATTR_NONCE :: u16(0x0015)
TURN_ATTR_RELAYED :: u16(0x0016)
TURN_ATTR_TRANSPORT :: u16(0x0019)

TURN_CREDENTIAL_MAX :: 128
TURN_RETRY_MS :: 500
TURN_TIMEOUT_MS :: 5000             // an allocation that did not finish by then failed
TURN_PERMISSION_MS :: 240000        // a permission lives 5 minutes, renewed after 4
TURN_PERMISSIONS :: 16
TURN_BATCH :: 4                     // addresses in one CreatePermission
TURN_OVERHEAD :: 48                 // the most a Send indication adds to a datagram

TurnPhase :: enum {
    OFF,
    ALLOCATING,
    READY,
    FAILED,
}

TurnRequest :: enum {
    NONE,
    ALLOCATE,
    REFRESH,
    PERMISSION,
}

TurnPermission :: struct {
    address: net.IP4_Address,
    expires_ms: i64,
    used: bool,
}

TurnClient :: struct {
    phase: TurnPhase,
    server: net.Endpoint,
    username: [TURN_CREDENTIAL_MAX]byte,
    username_len: int,
    password: [TURN_CREDENTIAL_MAX]byte,
    password_len: int,
    realm: [TURN_CREDENTIAL_MAX]byte,
    realm_len: int,
    nonce: [TURN_CREDENTIAL_MAX]byte,
    nonce_len: int,
    key: [16]byte,                  // MD5(username:realm:password)
    authenticated: bool,            // key is valid: realm and nonce were learned from the server

    relayed: net.Endpoint,          // where the peers send to reach us
    mapped: net.Endpoint,           // what the server saw (one more server reflexive address)
    lifetime_s: u32,
    failure: int,                   // the error code that ended the allocation, 0 = none / timeout

    request: TurnRequest,
    txid: StunTxId,
    sent_ms: i64,
    started_ms: i64,
    tries: int,
    refresh_ms: i64,
    batch: [TURN_BATCH]net.IP4_Address,
    batch_count: int,
    permissions: [TURN_PERMISSIONS]TurnPermission,
}

// ============================================================ message building (STUN with attributes)

// Starts a message of type `kind`. The length field always tells what has been appended so far.
@(private)
StunBegin :: proc(buffer: []byte, kind: u16, txid: StunTxId) -> int {
    id: StunTxId = txid
    PutU16BE(buffer[0:], kind)
    PutU16BE(buffer[2:], 0)
    PutU32BE(buffer[4:], STUN_MAGIC)
    copy(buffer[8:20], id[:])
    return STUN_HEADER_SIZE
}

@(private)
StunAppend :: proc(buffer: []byte, offset: int, kind: u16, value: []byte) -> int {
    PutU16BE(buffer[offset:], kind)
    PutU16BE(buffer[offset + 2:], u16(len(value)))
    copy(buffer[offset + 4:], value)
    padded: int = (len(value) + 3) & ~int(3)
    for i in len(value) ..< padded {
        buffer[offset + 4 + i] = 0
    }
    end: int = offset + 4 + padded
    PutU16BE(buffer[2:], u16(end - STUN_HEADER_SIZE))
    return end
}

// An IPv4 address attribute in the XOR form (peer and relayed addresses).
@(private)
StunAppendAddress :: proc(buffer: []byte, offset: int, kind: u16, endpoint: net.Endpoint) -> int {
    address: net.IP4_Address = endpoint.address.(net.IP4_Address)
    value: [8]byte
    value[1] = 1
    PutU16BE(value[2:], u16(endpoint.port) ~ u16(STUN_MAGIC >> 16))
    for i in 0 ..< 4 {
        value[4 + i] = address[i] ~ byte(STUN_MAGIC >> u32(24 - 8 * i))
    }
    return StunAppend(buffer, offset, kind, value[:])
}

// Adds MESSAGE-INTEGRITY: HMAC-SHA1 over the message so far, with the length field already counting the attribute itself.
@(private)
StunSign :: proc(buffer: []byte, offset: int, key: []byte) -> int {
    PutU16BE(buffer[2:], u16(offset - STUN_HEADER_SIZE + 24))
    mac: [20]byte
    hmac.sum(.Insecure_SHA1, mac[:], buffer[:offset], key)
    return StunAppend(buffer, offset, TURN_ATTR_INTEGRITY, mac[:])
}

// Does the MESSAGE-INTEGRITY of this message match `key`? (a server checks requests with it; the tests do)
StunVerify :: proc(data: []byte, key: []byte) -> bool {
    offset: int = STUN_HEADER_SIZE
    end: int = min(STUN_HEADER_SIZE + int(GetU16BE(data[2:])), len(data))
    for offset + 4 <= end {
        kind: u16 = GetU16BE(data[offset:])
        size: int = int(GetU16BE(data[offset + 2:]))
        if kind == TURN_ATTR_INTEGRITY && size == 20 && offset + 24 <= len(data) {
            copy_buffer: [1500]byte
            if offset > len(copy_buffer) {
                return false
            }
            copy(copy_buffer[:], data[:offset])
            PutU16BE(copy_buffer[2:], u16(offset - STUN_HEADER_SIZE + 24))
            mac: [20]byte
            hmac.sum(.Insecure_SHA1, mac[:], copy_buffer[:offset], key)
            return string(mac[:]) == string(data[offset + 4:offset + 24])
        }
        offset += 4 + (size + 3) & ~int(3)
    }
    return false
}

// The long term key of RFC 5389: MD5 of "username:realm:password".
TurnKey :: proc(username: string, realm: string, password: string) -> (key: [16]byte) {
    ctx: hash.Context
    hash.init(&ctx, .Insecure_MD5)
    hash.update(&ctx, transmute([]byte)username)
    hash.update(&ctx, []byte{':'})
    hash.update(&ctx, transmute([]byte)realm)
    hash.update(&ctx, []byte{':'})
    hash.update(&ctx, transmute([]byte)password)
    hash.final(&ctx, key[:])
    return
}

// ============================================================ the client

// Starts allocating a relayed address on `server` (resolve its name first, LinkResolve). Non blocking: LinkUpdate does the
// rest. When it is READY the relayed address is one more candidate of the link (RELAY_READY event); call it BEFORE the gathering
// is done and LinkGathered waits for it, so the first code already holds the relay.
LinkTurnBegin :: proc(link: ^Link, server: net.Endpoint, username: string, password: string, now_ms: i64) -> bool {
    assert(link.open)
    if len(username) > TURN_CREDENTIAL_MAX || len(password) > TURN_CREDENTIAL_MAX {
        return false
    }
    turn: ^TurnClient = &link.turn
    turn^ = {phase = .ALLOCATING, server = server, started_ms = now_ms}
    copy(turn.username[:], username)
    turn.username_len = len(username)
    copy(turn.password[:], password)
    turn.password_len = len(password)
    TurnStartRequest(link, .ALLOCATE, now_ms)
    return true
}

// Resolves "host:port" to an IPv4 endpoint (a blocking DNS lookup, so do it at start).
LinkResolve :: proc(host_and_port: string) -> (endpoint: net.Endpoint, ok: bool) {
    resolved, error := net.resolve_ip4(host_and_port)
    return resolved, error == nil
}

@(private)
TurnStartRequest :: proc(link: ^Link, request: TurnRequest, now_ms: i64) {
    turn: ^TurnClient = &link.turn
    turn.request = request
    turn.tries = 0
    crypto.rand_bytes(turn.txid[:])
    TurnSendRequest(link, now_ms)
}

// (Re)sends the request in progress, with the credentials once the server has told its realm and nonce.
@(private)
TurnSendRequest :: proc(link: ^Link, now_ms: i64) {
    turn: ^TurnClient = &link.turn
    buffer: [512]byte
    offset: int
    switch turn.request {
    case .NONE:
        return
    case .ALLOCATE:
        offset = StunBegin(buffer[:], TURN_ALLOCATE, turn.txid)
        offset = StunAppend(buffer[:], offset, TURN_ATTR_TRANSPORT, []byte{17, 0, 0, 0})
    case .REFRESH:
        offset = StunBegin(buffer[:], TURN_REFRESH, turn.txid)
    case .PERMISSION:
        offset = StunBegin(buffer[:], TURN_CREATE_PERMISSION, turn.txid)
        for i in 0 ..< turn.batch_count {
            offset = StunAppendAddress(buffer[:], offset, TURN_ATTR_PEER, {address = turn.batch[i], port = 0})
        }
    }
    if turn.authenticated {
        offset = StunAppend(buffer[:], offset, TURN_ATTR_USERNAME, turn.username[:turn.username_len])
        offset = StunAppend(buffer[:], offset, TURN_ATTR_REALM, turn.realm[:turn.realm_len])
        offset = StunAppend(buffer[:], offset, TURN_ATTR_NONCE, turn.nonce[:turn.nonce_len])
        offset = StunSign(buffer[:], offset, turn.key[:])
    }
    LinkSendRaw(link, turn.server, buffer[:offset])
    turn.sent_ms = now_ms
}

// Send indication: the server forwards `data` from our relayed address to `to`. No answer, no authentication.
@(private)
LinkSendRelayed :: proc(link: ^Link, to: net.Endpoint, data: []byte) {
    if slot, is_derp := DerpEndpointSlot(to); is_derp {
        LinkDerpSend(link, slot, data)                // a peer reached through the DERP relay is answered through it
        return
    }
    if link.turn.phase != .READY || len(data) > MAX_PAYLOAD + PACKET_HEADER + 8 {
        return
    }
    buffer: [PACKET_HEADER + 8 + MAX_PAYLOAD + TURN_OVERHEAD]byte
    txid: StunTxId
    crypto.rand_bytes(txid[:])
    offset: int = StunBegin(buffer[:], TURN_SEND_INDICATION, txid)
    offset = StunAppendAddress(buffer[:], offset, TURN_ATTR_PEER, to)
    offset = StunAppend(buffer[:], offset, TURN_ATTR_DATA, data)
    LinkSendRaw(link, link.turn.server, buffer[:offset])
}

// A datagram from the TURN server: a Data indication gives the peer's datagram (returned as `inner`, from `peer`), anything
// else is an answer to one of our requests.
@(private)
TurnReceive :: proc(link: ^Link, data: []byte, now_ms: i64) -> (inner: []byte, peer: net.Endpoint, is_data: bool) {
    if !StunLooksLikeStun(data) {
        return
    }
    kind: u16 = GetU16BE(data[0:])
    if kind == TURN_DATA_INDICATION {
        address, found := StunFindAttribute(data, TURN_ATTR_PEER)
        payload, has_payload := StunFindAttribute(data, TURN_ATTR_DATA)
        if !found || !has_payload {
            return
        }
        read, read_ok := StunReadAddress(address, true)
        return payload, read, read_ok
    }
    TurnAnswer(link, data, now_ms)
    return
}

@(private)
TurnAnswer :: proc(link: ^Link, data: []byte, now_ms: i64) {
    turn: ^TurnClient = &link.turn
    for i in 0 ..< len(turn.txid) {
        if data[8 + i] != turn.txid[i] {
            return
        }
    }
    if turn.request == .NONE {
        return
    }
    kind: u16 = GetU16BE(data[0:])
    if kind & 0x0110 == 0x0110 {
        code: int
        if value, found := StunFindAttribute(data, TURN_ATTR_ERROR); found && len(value) >= 4 {
            code = int(value[2]) * 100 + int(value[3])
        }
        // 401: the server wants credentials (and tells realm and nonce), 438: the nonce is stale, here is a new one
        if code == 401 || code == 438 {
            was_authenticated: bool = turn.authenticated
            realm, has_realm := StunFindAttribute(data, TURN_ATTR_REALM)
            nonce, has_nonce := StunFindAttribute(data, TURN_ATTR_NONCE)
            if !has_nonce || len(nonce) > TURN_CREDENTIAL_MAX || has_realm && len(realm) > TURN_CREDENTIAL_MAX {
                TurnFail(link, code)
                return
            }
            if has_realm {
                copy(turn.realm[:], realm)
                turn.realm_len = len(realm)
            }
            copy(turn.nonce[:], nonce)
            turn.nonce_len = len(nonce)
            // a 401 to a request that already carried the credentials: they are wrong
            if code == 401 && was_authenticated {
                TurnFail(link, code)
                return
            }
            turn.key = TurnKey(string(turn.username[:turn.username_len]), string(turn.realm[:turn.realm_len]), string(turn.password[:turn.password_len]))
            turn.authenticated = true
            crypto.rand_bytes(turn.txid[:])
            TurnSendRequest(link, now_ms)
            return
        }
        if turn.request == .ALLOCATE {
            TurnFail(link, code)
        } else {
            turn.request = .NONE
        }
        return
    }

    switch turn.request {
    case .NONE:
    case .ALLOCATE:
        relayed, relayed_found := StunFindAttribute(data, TURN_ATTR_RELAYED)
        if !relayed_found {
            TurnFail(link, 0)
            return
        }
        turn.relayed, _ = StunReadAddress(relayed, true)
        if mapped, found := StunFindAttribute(data, STUN_ATTR_XOR_MAPPED); found {
            turn.mapped, _ = StunReadAddress(mapped, true)
        }
        turn.lifetime_s = 600
        if lifetime, found := StunFindAttribute(data, TURN_ATTR_LIFETIME); found && len(lifetime) >= 4 {
            turn.lifetime_s = GetU32BE(lifetime)
        }
        turn.phase = .READY
        turn.request = .NONE
        turn.refresh_ms = now_ms + i64(turn.lifetime_s) * 500
        LinkAddRelayCandidate(link, turn.relayed)
        LinkPushEvent(link, {kind = .RELAY_READY})
    case .REFRESH:
        if lifetime, found := StunFindAttribute(data, TURN_ATTR_LIFETIME); found && len(lifetime) >= 4 {
            turn.lifetime_s = GetU32BE(lifetime)
        }
        turn.refresh_ms = now_ms + i64(turn.lifetime_s) * 500
        turn.request = .NONE
    case .PERMISSION:
        for i in 0 ..< turn.batch_count {
            TurnPermitted(turn, turn.batch[i], now_ms + TURN_PERMISSION_MS)
        }
        turn.request = .NONE
    }
}

@(private)
TurnFail :: proc(link: ^Link, code: int) {
    link.turn.phase = .FAILED
    link.turn.failure = code
    link.turn.request = .NONE
    LinkPushEvent(link, {kind = .RELAY_FAILED})
}

@(private)
TurnPermitted :: proc(turn: ^TurnClient, address: net.IP4_Address, expires_ms: i64) {
    oldest: int
    for i in 0 ..< TURN_PERMISSIONS {
        if turn.permissions[i].used && turn.permissions[i].address == address {
            turn.permissions[i].expires_ms = expires_ms
            return
        }
        if !turn.permissions[i].used {
            oldest = i
            break
        }
        if turn.permissions[i].expires_ms < turn.permissions[oldest].expires_ms {
            oldest = i
        }
    }
    turn.permissions[oldest] = {address = address, expires_ms = expires_ms, used = true}
}

@(private)
TurnHasPermission :: proc(turn: ^TurnClient, address: net.IP4_Address, now_ms: i64) -> bool {
    for permission in turn.permissions {
        // granted for 5 minutes, recorded as expiring after 4: asked again with a minute to spare
        if permission.used && permission.address == address && permission.expires_ms > now_ms {
            return true
        }
    }
    return false
}

// The relay only forwards what comes from addresses it was told about: every public address of the peers is announced.
@(private)
TurnWantedAddresses :: proc(link: ^Link, now_ms: i64) {
    turn: ^TurnClient = &link.turn
    turn.batch_count = 0
    add :: proc(turn: ^TurnClient, address: net.Address, now_ms: i64) {
        ip, is_ip4 := address.(net.IP4_Address)
        if !is_ip4 || !IsPublicAddress(address) || turn.batch_count >= TURN_BATCH || TurnHasPermission(turn, ip, now_ms) {
            return
        }
        for i in 0 ..< turn.batch_count {
            if turn.batch[i] == ip {
                return
            }
        }
        turn.batch[turn.batch_count] = ip
        turn.batch_count += 1
    }
    for &peer in link.peers {
        if peer.state != .PUNCHING && peer.state != .CONNECTED {
            continue
        }
        for c in 0 ..< peer.candidate_count {
            add(turn, peer.candidates[c].address, now_ms)
        }
        if peer.state == .CONNECTED {
            add(turn, peer.endpoint.address, now_ms)
        }
    }
}

@(private)
TurnUpdate :: proc(link: ^Link, now_ms: i64) {
    turn: ^TurnClient = &link.turn
    switch turn.phase {
    case .OFF, .FAILED:
        return
    case .ALLOCATING:
        if now_ms - turn.started_ms >= TURN_TIMEOUT_MS {
            TurnFail(link, 0)
        } else if now_ms - turn.sent_ms >= TURN_RETRY_MS {
            TurnSendRequest(link, now_ms)
        }
    case .READY:
        if turn.request != .NONE {
            if now_ms - turn.sent_ms >= TURN_RETRY_MS {
                turn.tries += 1
                if turn.tries > 6 {
                    turn.request = .NONE
                } else {
                    TurnSendRequest(link, now_ms)
                }
            }
            return
        }
        if now_ms >= turn.refresh_ms {
            TurnStartRequest(link, .REFRESH, now_ms)
            return
        }
        TurnWantedAddresses(link, now_ms)
        if turn.batch_count > 0 {
            TurnStartRequest(link, .PERMISSION, now_ms)
        }
    }
}

// The relayed address goes last in the code: a direct address is always better, and a full list gives up a local one for it.
@(private)
LinkAddRelayCandidate :: proc(link: ^Link, endpoint: net.Endpoint) {
    for i in 0 ..< link.candidate_count {
        if link.candidates[i] == endpoint {
            return
        }
    }
    if link.candidate_count < MAX_CANDIDATES {
        link.candidates[link.candidate_count] = endpoint
        link.candidate_count += 1
    } else {
        link.candidates[MAX_CANDIDATES - 1] = endpoint
    }
}

// ============================================================ tests

@(test)
TurnIntegrityGoldenTest :: proc(t: ^testing.T) {
    // values computed with Python's hashlib and hmac, a different implementation than the one under test
    key: [16]byte = TurnKey("user", "example.org", "secret")
    expected_key: [16]byte = {0xa9, 0x83, 0x2f, 0xed, 0x4a, 0x75, 0x67, 0xb4, 0x0e, 0x43, 0x44, 0x3f, 0x9f, 0x30, 0xc2, 0x72}
    testing.expect_value(t, key, expected_key)

    txid: StunTxId = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
    buffer: [256]byte
    offset: int = StunBegin(buffer[:], TURN_ALLOCATE, txid)
    offset = StunAppend(buffer[:], offset, TURN_ATTR_TRANSPORT, []byte{17, 0, 0, 0})
    offset = StunAppend(buffer[:], offset, TURN_ATTR_USERNAME, transmute([]byte)string("user"))
    offset = StunAppend(buffer[:], offset, TURN_ATTR_REALM, transmute([]byte)string("example.org"))
    offset = StunAppend(buffer[:], offset, TURN_ATTR_NONCE, transmute([]byte)string("abcdef"))
    offset = StunSign(buffer[:], offset, key[:])
    testing.expect_value(t, offset, 88)
    testing.expect_value(t, GetU16BE(buffer[2:]), u16(68))
    expected_mac: [20]byte = {0x04, 0xce, 0x0b, 0x4a, 0xbd, 0xa9, 0x2f, 0x56, 0xda, 0x97, 0x97, 0xb1, 0x31, 0xc3, 0xd9, 0xb4, 0x8a, 0x01, 0xda, 0xba}
    mac, found := StunFindAttribute(buffer[:offset], TURN_ATTR_INTEGRITY)
    testing.expect(t, found)
    testing.expect_value(t, string(mac), string(expected_mac[:]))
    testing.expect(t, StunVerify(buffer[:offset], key[:]))
    wrong: [16]byte = TurnKey("user", "example.org", "other")
    testing.expect(t, !StunVerify(buffer[:offset], wrong[:]))
    buffer[30] ~= 1
    testing.expect(t, !StunVerify(buffer[:offset], key[:]))
}
