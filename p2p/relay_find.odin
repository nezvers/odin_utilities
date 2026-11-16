// Looking for a relay (TURN) server that works from this network, so a program can offer it as an option.
//
// There is no anonymous free TURN server: every public one wants a login (measured with tool/probe). What can be found without an
// account is which servers are ALIVE and reachable from here (they answer an Allocate request with "401 unauthorized" plus their
// realm), and, rarely, one that is simply open. The caller shows the alive ones with their provider's free sign-up and takes
// credentials from the person; an open one is used straight away.
//
// Blocking and time bounded (name lookup, then one wait for all answers): meant for the start of a program, like LinkResolveStun.
package p2p

import "core:crypto"
import "core:net"
import "core:testing"
import "core:time"

RelayCandidate :: struct {
    host: string,                   // host:port, UDP
    provider: string,
    signup: string,                 // where the free tier is made, "" when unknown
}

RELAY_CANDIDATES := [?]RelayCandidate{
    {"relay1.expressturn.com:3478", "ExpressTURN", "https://www.expressturn.com (free tier, 1 TB a month)"},
    {"standard.relay.metered.ca:80", "Metered", "https://www.metered.ca/tools/openrelay (free tier)"},
    {"openrelay.metered.ca:80", "Metered Open Relay", "https://www.metered.ca/tools/openrelay"},
    {"openrelay.metered.ca:443", "Metered Open Relay", "https://www.metered.ca/tools/openrelay"},
    {"turn.cloudflare.com:3478", "Cloudflare Calls TURN", "https://developers.cloudflare.com/calls/turn/ (free tier)"},
    {"turn.speed.cloudflare.com:50000", "Cloudflare", ""},
    {"eu-turn1.xirsys.com:80", "Xirsys", "https://xirsys.com (free tier)"},
    {"global.turn.twilio.com:3478", "Twilio", "https://www.twilio.com/stun-turn (needs an account, tokens expire)"},
    {"freestun.net:3478", "freestun.net", ""},
    {"freestun.net:5349", "freestun.net", ""},
    {"turn.anyfirewall.com:3478", "anyfirewall", ""},
    {"turn.anyfirewall.com:443", "anyfirewall", ""},
    {"numb.viagenie.ca:3478", "Viagenie numb", ""},
    {"turn.bistri.com:80", "Bistri", ""},
    {"turn.nextcloud.com:3478", "Nextcloud", ""},
    {"turn.stunprotocol.org:3478", "stunprotocol.org", ""},
}

RelayState :: enum {
    UNRESOLVED,                     // the name did not resolve
    NO_ANSWER,                      // resolved, but nothing came back (dead, or UDP to it is blocked here)
    WANTS_LOGIN,                    // alive, answered 401: needs credentials
    OPEN,                           // alive and allocated without credentials (anybody can use it)
    OTHER_ERROR,                    // alive but refused for another reason (see code)
}

RelayInfo :: struct {
    endpoint: net.Endpoint,
    state: RelayState,
    code: int,                      // the TURN error code when it answered with one
    rtt_ms: int,
    realm: [64]byte,
    realm_length: int,
}

// What does this datagram say about a relay: only Allocate answers of the transaction `txid` count.
RelayClassify :: proc(data: []byte, txid: StunTxId) -> (info: RelayInfo, ok: bool) {
    end: int
    end, ok = StunCheck(data, txid)
    if !ok {
        return
    }
    kind: u16 = GetU16BE(data[0:])
    switch kind {
    case 0x0103:                    // Allocate success
        info.state = .OPEN
    case 0x0113:                    // Allocate error
        value, has_code := StunFindAttribute(data[:end], TURN_ATTR_ERROR)
        if !has_code || len(value) < 4 {
            return {}, false
        }
        info.code = int(value[2]) * 100 + int(value[3])
        info.state = .WANTS_LOGIN if info.code == 401 else .OTHER_ERROR
    case:
        return {}, false
    }
    if realm, has_realm := StunFindAttribute(data[:end], TURN_ATTR_REALM); has_realm {
        info.realm_length = min(len(realm), len(info.realm))
        copy(info.realm[:info.realm_length], realm)
    }
    return info, true
}

// Asks every host (one Allocate request without credentials, twice because UDP drops) and waits up to `timeout_ms` for the answers.
// `infos` is filled in the same order as `hosts` (at most len(infos) are tried). Returns how many are alive (any answer).
RelayFind :: proc(hosts: []string, infos: []RelayInfo, timeout_ms: i64) -> (alive: int) {
    count: int = min(len(hosts), len(infos))
    if count == 0 {
        return
    }
    socket, make_error := net.make_unbound_udp_socket(.IP4)
    if make_error != nil {
        return
    }
    defer net.close(socket)
    if net.bind(socket, {address = net.IP4_Any, port = 0}) != nil || net.set_blocking(socket, false) != nil {
        return
    }
    txids: [64]StunTxId
    sent_ms: [64]i64
    count = min(count, len(txids))
    for i in 0 ..< count {
        infos[i] = {}
        endpoint, resolved := LinkResolve(hosts[i])
        if !resolved {
            infos[i].state = .UNRESOLVED
            continue
        }
        infos[i].endpoint = endpoint
        infos[i].state = .NO_ANSWER
        crypto.rand_bytes(txids[i][:])
    }
    request: [32]byte
    send_round :: proc(socket: net.UDP_Socket, infos: []RelayInfo, txids: []StunTxId, sent_ms: []i64, count: int, request: []byte) {
        for i in 0 ..< count {
            if infos[i].state != .NO_ANSWER {
                continue
            }
            length: int = StunBegin(request, TURN_ALLOCATE, txids[i])
            length = StunAppend(request, length, TURN_ATTR_TRANSPORT, {17, 0, 0, 0})
            if sent_ms[i] == 0 {
                sent_ms[i] = LinkNow()
            }
            net.send_udp(socket, request[:length], infos[i].endpoint)
        }
    }
    send_round(socket, infos, txids[:], sent_ms[:], count, request[:])
    start: i64 = LinkNow()
    resent: bool
    buffer: [1500]byte
    for LinkNow() - start < timeout_ms {
        if !resent && LinkNow() - start >= timeout_ms / 3 {
            resent = true
            send_round(socket, infos, txids[:], sent_ms[:], count, request[:])
        }
        length, _, error := net.recv_udp(socket, buffer[:])
        if error != nil || length < STUN_HEADER_SIZE {
            time.sleep(2 * time.Millisecond)
            continue
        }
        for i in 0 ..< count {
            if infos[i].state != .NO_ANSWER {
                continue
            }
            info, ok := RelayClassify(buffer[:length], txids[i])
            if ok {
                info.endpoint = infos[i].endpoint
                info.rtt_ms = int(LinkNow() - sent_ms[i])
                infos[i] = info
                alive += 1
                break
            }
        }
    }
    return
}

@(test)
RelayClassifyTest :: proc(t: ^testing.T) {
    txid: StunTxId = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
    data: [128]byte
    // a real server answer: Allocate error 401 with the REALM attribute
    length: int = StunBegin(data[:], 0x0113, txid)
    length = StunAppend(data[:], length, TURN_ATTR_ERROR, {0, 0, 4, 1, 'U', 'n', 'a', 'u', 't', 'h'})
    length = StunAppend(data[:], length, TURN_ATTR_REALM, transmute([]byte)string("example.org"))
    info, ok := RelayClassify(data[:length], txid)
    testing.expect(t, ok)
    testing.expect_value(t, info.state, RelayState.WANTS_LOGIN)
    testing.expect_value(t, info.code, 401)
    testing.expect_value(t, string(info.realm[:info.realm_length]), "example.org")

    // another error code is alive but not usable
    length = StunBegin(data[:], 0x0113, txid)
    length = StunAppend(data[:], length, TURN_ATTR_ERROR, {0, 0, 4, 20})
    info, ok = RelayClassify(data[:length], txid)
    testing.expect(t, ok)
    testing.expect_value(t, info.state, RelayState.OTHER_ERROR)

    // success without credentials: an open relay
    length = StunBegin(data[:], 0x0103, txid)
    info, ok = RelayClassify(data[:length], txid)
    testing.expect(t, ok)
    testing.expect_value(t, info.state, RelayState.OPEN)

    // somebody else's transaction, or not an Allocate answer, is ignored
    other: StunTxId = {9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9}
    _, ok = RelayClassify(data[:length], other)
    testing.expect(t, !ok)
    length = StunBegin(data[:], STUN_BINDING_SUCCESS, txid)
    _, ok = RelayClassify(data[:length], txid)
    testing.expect(t, !ok)
}
