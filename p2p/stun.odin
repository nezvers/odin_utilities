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

// Free servers that answer binding requests. Several, because one of them can be down or blocked on a network.
STUN_SERVERS := [?]string{
    "stun.l.google.com:19302",
    "stun.cloudflare.com:3478",
    "stun1.l.google.com:19302",
}

StunTxId :: [12]byte

// Fill `buffer` (at least STUN_HEADER_SIZE) with a binding request, returns the length to send.
StunBuildRequest :: proc(buffer: []byte, txid: StunTxId) -> int {
    assert(len(buffer) >= STUN_HEADER_SIZE)
    PutU16BE(buffer[0:], STUN_BINDING_REQUEST)
    PutU16BE(buffer[2:], 0)
    PutU32BE(buffer[4:], STUN_MAGIC)
    for i in 0 ..< len(txid) {
        buffer[8 + i] = txid[i]
    }
    return STUN_HEADER_SIZE
}

// Is this datagram shaped like STUN? Our own packets start with PACKET_MAGIC, so the two never mix on one socket.
StunLooksLikeStun :: proc(data: []byte) -> bool {
    return len(data) >= STUN_HEADER_SIZE && data[0] < 0x40 && GetU32BE(data[4:]) == STUN_MAGIC
}

// The address the server saw us at. Only IPv4 (the socket is IPv4). Answers for another transaction are rejected,
// so a late or forged reply cannot overwrite a good result.
StunParseResponse :: proc(data: []byte, txid: StunTxId) -> (endpoint: net.Endpoint, ok: bool) {
    if !StunLooksLikeStun(data) || GetU16BE(data[0:]) != STUN_BINDING_SUCCESS {
        return
    }
    for i in 0 ..< len(txid) {
        if data[8 + i] != txid[i] {
            return
        }
    }
    end: int = STUN_HEADER_SIZE + int(GetU16BE(data[2:]))
    if end > len(data) {
        return
    }

    plain: net.Endpoint
    have_plain: bool
    offset: int = STUN_HEADER_SIZE
    for offset + 4 <= end {
        kind: u16 = GetU16BE(data[offset:])
        size: int = int(GetU16BE(data[offset + 2:]))
        value_start: int = offset + 4
        if value_start + size > end {
            return
        }
        value: []byte = data[value_start:value_start + size]
        // attributes are padded to 4 bytes
        offset = value_start + (size + 3) & ~int(3)

        // [0] reserved, [1] family (1 = IPv4), [2:4] port, [4:8] address
        if size < 8 || value[1] != 1 {
            continue
        }
        port: u16 = GetU16BE(value[2:])
        address: [4]byte = {value[4], value[5], value[6], value[7]}
        switch kind {
        case STUN_ATTR_XOR_MAPPED:
            port ~= u16(STUN_MAGIC >> 16)
            for i in 0 ..< 4 {
                address[i] ~= byte(STUN_MAGIC >> u32(24 - 8 * i))
            }
            return net.Endpoint{address = net.IP4_Address(address), port = int(port)}, true
        case STUN_ATTR_MAPPED:
            plain = {address = net.IP4_Address(address), port = int(port)}
            have_plain = true
        }
    }
    // old servers answer with the plain address only
    return plain, have_plain
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
    request: [STUN_HEADER_SIZE]byte
    testing.expect_value(t, StunBuildRequest(request[:], txid), STUN_HEADER_SIZE)
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
