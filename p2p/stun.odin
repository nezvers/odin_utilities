// STUN binding (RFC 5389): ask a free public server "what address and port do you see me at?".
//
// This is the only "server" the library needs, and it is not ours: it only answers one small UDP packet and keeps nothing.
// The request has to leave from the SAME socket the game uses, so the NAT mapping that STUN reveals is the one the peer is
// going to hit. Pure functions over caller buffers, no sockets here (the Link does the sending).
package p2p

import "core:net"
import "core:testing"

STUN_HEADER_SIZE :: 20
STUN_MAGIC :: u32(0x2112A442)
STUN_BINDING_REQUEST :: u16(0x0001)
STUN_BINDING_SUCCESS :: u16(0x0101)
STUN_ATTR_MAPPED :: u16(0x0001)
STUN_ATTR_XOR_MAPPED :: u16(0x0020)
STUN_ATTR_SOURCE_ADDRESS :: u16(0x0004)        // RFC 3489 servers
STUN_ATTR_CHANGED_ADDRESS :: u16(0x0005)
STUN_ATTR_CHANGE_REQUEST :: u16(0x0003)
STUN_ATTR_RESPONSE_ORIGIN :: u16(0x802B)       // RFC 5780 servers
STUN_ATTR_OTHER_ADDRESS :: u16(0x802C)
STUN_CHANGE_PORT :: u32(2)
STUN_CHANGE_IP :: u32(4)

// Free servers that answer binding requests. Several, because one of them can be down or blocked on a network, and different
// ones are needed to tell a symmetric NAT. The third also has a second address and honors CHANGE-REQUEST (RFC 5780), which
// is what the NAT filtering test needs (found with tool/probe: most free servers ignore it or announce a private address).
STUN_SERVERS := [?]string{
    "stun.l.google.com:19302",
    "stun.cloudflare.com:3478",
    "stun.nextcloud.com:3478",
}

StunTxId :: [12]byte

// Fill `buffer` (at least STUN_HEADER_SIZE + 8) with a binding request, returns the length to send. `change` asks the server to
// answer from another address (STUN_CHANGE_IP / STUN_CHANGE_PORT, RFC 5780): if that answer still reaches us the NAT lets
// strangers in, which is how the filtering behavior is measured. Only servers that support it answer.
StunBuildRequest :: proc(buffer: []byte, txid: StunTxId, change: u32 = 0) -> int {
    assert(len(buffer) >= STUN_HEADER_SIZE + 8)
    PutU16BE(buffer[0:], STUN_BINDING_REQUEST)
    PutU32BE(buffer[4:], STUN_MAGIC)
    for i in 0 ..< len(txid) {
        buffer[8 + i] = txid[i]
    }
    if change == 0 {
        PutU16BE(buffer[2:], 0)
        return STUN_HEADER_SIZE
    }
    PutU16BE(buffer[2:], 8)
    PutU16BE(buffer[20:], STUN_ATTR_CHANGE_REQUEST)
    PutU16BE(buffer[22:], 4)
    PutU32BE(buffer[24:], change)
    return STUN_HEADER_SIZE + 8
}

// Is this datagram shaped like STUN? Our own packets start with PACKET_MAGIC, so the two never mix on one socket.
StunLooksLikeStun :: proc(data: []byte) -> bool {
    return len(data) >= STUN_HEADER_SIZE && data[0] < 0x40 && GetU32BE(data[4:]) == STUN_MAGIC
}

// Is this a message of the transaction `txid`? Returns the end of its attributes (a view limit into data).
@(private)
StunCheck :: proc(data: []byte, txid: StunTxId) -> (end: int, ok: bool) {
    if !StunLooksLikeStun(data) {
        return
    }
    for i in 0 ..< len(txid) {
        if data[8 + i] != txid[i] {
            return
        }
    }
    end = STUN_HEADER_SIZE + int(GetU16BE(data[2:]))
    return end, end <= len(data)
}

// The value of the first attribute of `kind`, a view into data.
StunFindAttribute :: proc(data: []byte, kind: u16) -> (value: []byte, ok: bool) {
    if len(data) < STUN_HEADER_SIZE {
        return
    }
    end: int = min(STUN_HEADER_SIZE + int(GetU16BE(data[2:])), len(data))
    offset: int = STUN_HEADER_SIZE
    for offset + 4 <= end {
        found: u16 = GetU16BE(data[offset:])
        size: int = int(GetU16BE(data[offset + 2:]))
        start: int = offset + 4
        if start + size > end {
            return
        }
        if found == kind {
            return data[start:start + size], true
        }
        // attributes are padded to 4 bytes
        offset = start + (size + 3) & ~int(3)
    }
    return
}

// [0] reserved, [1] family (1 = IPv4), [2:4] port, [4:8] address; the XOR form hides them with the magic cookie
// (middle boxes that rewrite IP addresses in payloads would otherwise damage them). IPv4 only.
StunReadAddress :: proc(value: []byte, xor: bool) -> (endpoint: net.Endpoint, ok: bool) {
    if len(value) < 8 || value[1] != 1 {
        return
    }
    port: u16 = GetU16BE(value[2:])
    address: [4]byte = {value[4], value[5], value[6], value[7]}
    if xor {
        port ~= u16(STUN_MAGIC >> 16)
        for i in 0 ..< 4 {
            address[i] ~= byte(STUN_MAGIC >> u32(24 - 8 * i))
        }
    }
    return net.Endpoint{address = net.IP4_Address(address), port = int(port)}, true
}

// What a binding answer tells: where the server saw us, where the answer came from and, for servers that have a second
// address (RFC 5780 OTHER-ADDRESS, RFC 3489 CHANGED-ADDRESS), that address.
StunResult :: struct {
    mapped: net.Endpoint,
    origin: net.Endpoint,
    other: net.Endpoint,
    has_origin: bool,
    has_other: bool,
}

// Answers for another transaction are rejected, so a late or forged reply cannot overwrite a good result.
StunParseResult :: proc(data: []byte, txid: StunTxId) -> (result: StunResult, ok: bool) {
    _ = StunCheck(data, txid) or_return
    if GetU16BE(data[0:]) != STUN_BINDING_SUCCESS {
        return
    }
    if value, found := StunFindAttribute(data, STUN_ATTR_XOR_MAPPED); found {
        result.mapped = StunReadAddress(value, true) or_return
    } else if value, found = StunFindAttribute(data, STUN_ATTR_MAPPED); found {
        // old servers answer with the plain address only
        result.mapped = StunReadAddress(value, false) or_return
    } else {
        return
    }
    if value, found := StunFindAttribute(data, STUN_ATTR_RESPONSE_ORIGIN); found {
        result.origin, result.has_origin = StunReadAddress(value, false)
    } else if value, found = StunFindAttribute(data, STUN_ATTR_SOURCE_ADDRESS); found {
        result.origin, result.has_origin = StunReadAddress(value, false)
    }
    if value, found := StunFindAttribute(data, STUN_ATTR_OTHER_ADDRESS); found {
        result.other, result.has_other = StunReadAddress(value, false)
    } else if value, found = StunFindAttribute(data, STUN_ATTR_CHANGED_ADDRESS); found {
        result.other, result.has_other = StunReadAddress(value, false)
    }
    return result, true
}

// The address the server saw us at.
StunParseResponse :: proc(data: []byte, txid: StunTxId) -> (endpoint: net.Endpoint, ok: bool) {
    result := StunParseResult(data, txid) or_return
    return result.mapped, true
}

// ============================================================ big endian helpers (the STUN wire format)

PutU16BE :: proc(buffer: []byte, value: u16) {
    buffer[0] = byte(value >> 8)
    buffer[1] = byte(value)
}

PutU32BE :: proc(buffer: []byte, value: u32) {
    buffer[0] = byte(value >> 24)
    buffer[1] = byte(value >> 16)
    buffer[2] = byte(value >> 8)
    buffer[3] = byte(value)
}

GetU16BE :: proc(buffer: []byte) -> u16 {
    return u16(buffer[0]) << 8 | u16(buffer[1])
}

GetU32BE :: proc(buffer: []byte) -> u32 {
    return u32(buffer[0]) << 24 | u32(buffer[1]) << 16 | u32(buffer[2]) << 8 | u32(buffer[3])
}

// ============================================================ tests

@(test)
StunRoundTripTest :: proc(t: ^testing.T) {
    txid: StunTxId = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
    request: [STUN_HEADER_SIZE + 8]byte
    testing.expect_value(t, StunBuildRequest(request[:], txid), STUN_HEADER_SIZE)
    testing.expect_value(t, StunBuildRequest(request[:], txid, STUN_CHANGE_IP | STUN_CHANGE_PORT), STUN_HEADER_SIZE + 8)
    change, change_found := StunFindAttribute(request[:STUN_HEADER_SIZE + 8], STUN_ATTR_CHANGE_REQUEST)
    testing.expect(t, change_found && GetU32BE(change) == 6)
    StunBuildRequest(request[:], txid)
    testing.expect(t, StunLooksLikeStun(request[:]))

    // a response as a server builds it: 203.0.113.9:54321, XOR-MAPPED-ADDRESS
    response: [32]byte
    PutU16BE(response[0:], STUN_BINDING_SUCCESS)
    PutU16BE(response[2:], 12)
    PutU32BE(response[4:], STUN_MAGIC)
    copy(response[8:20], txid[:])
    PutU16BE(response[20:], STUN_ATTR_XOR_MAPPED)
    PutU16BE(response[22:], 8)
    response[25] = 1
    PutU16BE(response[26:], u16(54321) ~ u16(STUN_MAGIC >> 16))
    ip: [4]byte = {203, 0, 113, 9}
    for i in 0 ..< 4 {
        response[28 + i] = ip[i] ~ byte(STUN_MAGIC >> u32(24 - 8 * i))
    }

    endpoint, ok := StunParseResponse(response[:], txid)
    testing.expect(t, ok)
    testing.expect_value(t, endpoint.port, 54321)
    testing.expect_value(t, endpoint.address, net.Address(net.IP4_Address{203, 0, 113, 9}))

    other: StunTxId = {9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9}
    _, wrong_ok := StunParseResponse(response[:], other)
    testing.expect(t, !wrong_ok)
    _, short_ok := StunParseResponse(response[:10], txid)
    testing.expect(t, !short_ok)
}
