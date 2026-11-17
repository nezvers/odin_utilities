package p2p

// A simulated internet for the tests: no sockets, no real time. Links talk through `Transport` procs into this file, which
// holds NAT boxes with the behaviors real routers have (RFC 4787 vocabulary), a LAN behind each NAT, and STUN servers that
// honor CHANGE-REQUEST. Every datagram is delivered at once, so a test is deterministic and takes milliseconds.
//
//   mapping    how the public port is chosen: one per inside socket (cone), or a new one per destination (symmetric),
//              counting up (many home routers) or random (many carrier and company NATs)
//   filtering  who may send to a public port: anybody (full cone), addresses we sent to, exact address and port we sent to
//   hairpin    whether a host behind the NAT can reach another host of the same NAT through the NAT's public address

import "core:mem"
import "core:net"
import "core:testing"
import "core:time"

SIM_HOSTS :: 8
SIM_NATS :: 4
SIM_MAPPINGS :: 256
SIM_QUEUE :: 128
SIM_PERMITTED :: 32

SimMapping :: enum {
    INDEPENDENT,
    DEPENDENT_SEQUENTIAL,
    DEPENDENT_RANDOM,
}

SimFilter :: enum {
    FULL_CONE,
    ADDRESS_RESTRICTED,
    PORT_RESTRICTED,
}

SimNatConfig :: struct {
    mapping: SimMapping,
    filter: SimFilter,
    hairpin: bool,
}

// The kinds a host can sit behind, for the test matrix.
SimKind :: enum {
    PUBLIC,                         // no NAT
    FULL_CONE,
    ADDRESS_RESTRICTED,
    PORT_RESTRICTED,
    SYMMETRIC_SEQUENTIAL,
    SYMMETRIC_RANDOM,
}

SimConfigOf :: proc(kind: SimKind) -> SimNatConfig {
    switch kind {
    case .PUBLIC, .FULL_CONE:
        return {.INDEPENDENT, .FULL_CONE, false}
    case .ADDRESS_RESTRICTED:
        return {.INDEPENDENT, .ADDRESS_RESTRICTED, false}
    case .PORT_RESTRICTED:
        return {.INDEPENDENT, .PORT_RESTRICTED, false}
    case .SYMMETRIC_SEQUENTIAL:
        return {.DEPENDENT_SEQUENTIAL, .PORT_RESTRICTED, false}
    case .SYMMETRIC_RANDOM:
        return {.DEPENDENT_RANDOM, .PORT_RESTRICTED, false}
    }
    return {}
}

SimDatagram :: struct {
    from: net.Endpoint,
    length: int,
    data: [1300]byte,
}

SimHost :: struct {
    sim: ^Sim,
    v6: net.Endpoint,               // a global IPv6 address (no NAT), when has_v6
    has_v6: bool,
    firewall: bool,                 // IPv6 stateful firewall: only what it sent to may answer
    sent_to: [32]net.Endpoint,
    sent_count: int,
    private: net.Endpoint,          // the address the host knows itself by (its public one when there is no NAT)
    nat: int,                       // -1 = directly on the internet
    queue: [SIM_QUEUE]SimDatagram,
    head: int,
    count: int,
    derp: SimDerpHost,              // its connection to the fake DERP relay (sim_derp_test.odin)
}

SimEntry :: struct {
    used: bool,
    inside: net.Endpoint,
    external: int,
    dest: net.Endpoint,             // only meaningful for dependent mappings
    permitted: [SIM_PERMITTED]net.Endpoint,
    permitted_count: int,
    permitted_next: int,
}

SimNat :: struct {
    address: net.IP4_Address,       // its public address
    config: SimNatConfig,
    entries: [SIM_MAPPINGS]SimEntry,
    next_port: int,
    random: u32,
    host_count: int,
}

SIM_ALLOCATIONS :: 8
SIM_TURN_USER :: "player"
SIM_TURN_PASSWORD :: "secret"
SIM_TURN_REALM :: "sim.example"
SIM_TURN_NONCE :: "nonce123"

SimAllocation :: struct {
    used: bool,
    client: net.Endpoint,           // the public address the client talks from
    relayed: net.Endpoint,
    expires_ms: i64,
    permissions: [16]net.IP4_Address,
    permission_expires_ms: [16]i64,
    permission_count: int,
}

SimStun :: struct {
    endpoint: net.Endpoint,
    other: net.Endpoint,            // the second address that answers CHANGE-REQUEST
}

Sim :: struct {
    hosts: [SIM_HOSTS]SimHost,
    host_count: int,
    nats: [SIM_NATS]SimNat,
    nat_count: int,
    stuns: [2]SimStun,
    served: int,                    // STUN requests answered
    turn: net.Endpoint,             // the TURN server
    turn_down: bool,                // it exists but never answers
    allocations: [SIM_ALLOCATIONS]SimAllocation,
    now_ms: i64,                    // set by SimPump, for the lifetimes of the relay
    relayed_bytes: int,             // payload that went through the relay (either way)
    derp_down: bool,                // the DERP relay does not answer (connections to it fail)
    derp_relayed: int,              // packets that went through the DERP relay
}

SimInit :: proc(sim: ^Sim) {
    mem.zero_item(sim)
    sim.stuns[0] = {{net.IP4_Address{192, 0, 2, 1}, 3478}, {net.IP4_Address{192, 0, 2, 2}, 3479}}
    sim.stuns[1] = {{net.IP4_Address{192, 0, 2, 3}, 3478}, {net.IP4_Address{192, 0, 2, 4}, 3479}}
    sim.turn = {net.IP4_Address{192, 0, 2, 50}, 3478}
}

SimAddNat :: proc(sim: ^Sim, config: SimNatConfig) -> int {
    index: int = sim.nat_count
    sim.nat_count += 1
    nat: ^SimNat = &sim.nats[index]
    nat.address = net.IP4_Address{198, 51, 100, byte(10 + index)}
    nat.config = config
    nat.next_port = 30000 + 1000 * index
    nat.random = u32(12345 + index * 7919)
    return index
}

// A host behind NAT `nat` (-1: on the internet). Hosts of one NAT share its LAN 192.168.<nat + 1>.0.
SimAddHost :: proc(sim: ^Sim, nat: int) -> ^SimHost {
    host: ^SimHost = &sim.hosts[sim.host_count]
    host.sim = sim
    host.nat = nat
    if nat < 0 {
        host.private = {net.IP4_Address{203, 0, 113, byte(sim.host_count + 1)}, 4000 + sim.host_count}
    } else {
        sim.nats[nat].host_count += 1
        host.private = {net.IP4_Address{192, 168, byte(nat + 1), byte(9 + sim.nats[nat].host_count)}, 4000 + sim.host_count}
    }
    sim.host_count += 1
    return host
}

// Gives the host a global IPv6 address, behind a stateful firewall (what home routers do) or open.
SimGiveV6 :: proc(host: ^SimHost, firewall: bool) {
    host.has_v6 = true
    host.firewall = firewall
    host.v6 = {net.IP6_Address{0x2001, 0x0db8, 0, 0, 0, 0, 0, u16be(host.private.port)}, host.private.port}
}

SimTransport :: proc(host: ^SimHost) -> Transport {
    return {user = host, send = SimTransportSend, receive = SimTransportReceive}
}

SimTransportSend :: proc(user: rawptr, to: net.Endpoint, data: []byte) {
    SimSend((^SimHost)(user), to, data)
}

SimTransportReceive :: proc(user: rawptr, buffer: []byte) -> (length: int, from: net.Endpoint, ok: bool) {
    host: ^SimHost = (^SimHost)(user)
    if host.count == 0 {
        return
    }
    datagram: ^SimDatagram = &host.queue[host.head]
    host.head = (host.head + 1) % SIM_QUEUE
    host.count -= 1
    copy(buffer, datagram.data[:datagram.length])
    return datagram.length, datagram.from, true
}

SimQueue :: proc(host: ^SimHost, from: net.Endpoint, data: []byte) {
    if host.count >= SIM_QUEUE || len(data) > len(host.queue[0].data) {
        return
    }
    datagram: ^SimDatagram = &host.queue[(host.head + host.count) % SIM_QUEUE]
    datagram.from = from
    datagram.length = len(data)
    copy(datagram.data[:], data)
    host.count += 1
}

// What a host sends: through its NAT (creating the mapping and the permission), or straight onto the internet.
SimSend :: proc(host: ^SimHost, to: net.Endpoint, data: []byte) {
    sim: ^Sim = host.sim
    if _, to_v6 := to.address.(net.IP6_Address); to_v6 {
        if !host.has_v6 {
            return
        }
        known: bool
        for i in 0 ..< min(host.sent_count, len(host.sent_to)) {
            known ||= host.sent_to[i] == to
        }
        if !known {
            host.sent_to[host.sent_count % len(host.sent_to)] = to
            host.sent_count += 1
        }
        SimRoute(sim, host.v6, to, data)
        return
    }
    if host.nat < 0 {
        SimRoute(sim, host.private, to, data)
        return
    }
    nat: ^SimNat = &sim.nats[host.nat]
    // a neighbour on the same LAN is reached directly, no NAT in between
    to_address, to_is_ip4 := to.address.(net.IP4_Address)
    if to_is_ip4 && to_address[0] == 192 && to_address[1] == 168 {
        for i in 0 ..< sim.host_count {
            neighbour: ^SimHost = &sim.hosts[i]
            if neighbour.nat == host.nat && neighbour.private == to {
                SimQueue(neighbour, host.private, data)
            }
        }
        return
    }
    entry: ^SimEntry = SimNatOutbound(nat, host.private, to)
    source: net.Endpoint = {nat.address, entry.external}
    if to_address == nat.address {
        if nat.config.hairpin {
            SimNatInbound(sim, nat, source, to.port, data)
        }
        return
    }
    SimRoute(sim, source, to, data)
}

// A datagram on the internet, from a public source address to a public destination.
SimRoute :: proc(sim: ^Sim, source: net.Endpoint, to: net.Endpoint, data: []byte) {
    if to == sim.turn {
        if !sim.turn_down {
            SimTurnServe(sim, source, data)
        }
        return
    }
    for &allocation in sim.allocations {
        if allocation.used && allocation.relayed == to {
            SimTurnInbound(sim, &allocation, source, data)
            return
        }
    }
    for i in 0 ..< len(sim.stuns) {
        if to == sim.stuns[i].endpoint || to == sim.stuns[i].other {
            SimStunServe(sim, &sim.stuns[i], to, source, data)
            return
        }
    }
    to_address, is_ip4 := to.address.(net.IP4_Address)
    if !is_ip4 {
        for i in 0 ..< sim.host_count {
            host: ^SimHost = &sim.hosts[i]
            if !host.has_v6 || host.v6 != to {
                continue
            }
            allowed: bool = !host.firewall
            for k in 0 ..< min(host.sent_count, len(host.sent_to)) {
                allowed ||= host.sent_to[k] == source
            }
            if allowed {
                SimQueue(host, source, data)
            }
        }
        return
    }
    for i in 0 ..< sim.nat_count {
        if sim.nats[i].address == to_address {
            SimNatInbound(sim, &sim.nats[i], source, to.port, data)
            return
        }
    }
    for i in 0 ..< sim.host_count {
        if sim.hosts[i].nat < 0 && sim.hosts[i].private == to {
            SimQueue(&sim.hosts[i], source, data)
            return
        }
    }
}

SimNatOutbound :: proc(nat: ^SimNat, inside: net.Endpoint, to: net.Endpoint) -> ^SimEntry {
    dependent: bool = nat.config.mapping != .INDEPENDENT
    free_entry: ^SimEntry
    for &entry in nat.entries {
        if !entry.used {
            if free_entry == nil {
                free_entry = &entry
            }
            continue
        }
        if entry.inside == inside && (!dependent || entry.dest == to) {
            SimPermit(&entry, to)
            return &entry
        }
    }
    assert(free_entry != nil, "the simulated NAT table is full")
    free_entry^ = {used = true, inside = inside, dest = to}
    if nat.config.mapping == .DEPENDENT_RANDOM {
        nat.random = nat.random * 1664525 + 1013904223
        free_entry.external = 20000 + int(nat.random >> 8) % 40000
    } else {
        nat.next_port += 1
        free_entry.external = nat.next_port
    }
    SimPermit(free_entry, to)
    return free_entry
}

SimPermit :: proc(entry: ^SimEntry, to: net.Endpoint) {
    for i in 0 ..< entry.permitted_count {
        if entry.permitted[i] == to {
            return
        }
    }
    if entry.permitted_count < SIM_PERMITTED {
        entry.permitted[entry.permitted_count] = to
        entry.permitted_count += 1
        return
    }
    entry.permitted[entry.permitted_next] = to
    entry.permitted_next = (entry.permitted_next + 1) % SIM_PERMITTED
}

// A datagram arriving at the public side of a NAT: delivered only when the filtering allows its source.
SimNatInbound :: proc(sim: ^Sim, nat: ^SimNat, source: net.Endpoint, external: int, data: []byte) {
    for &entry in nat.entries {
        if !entry.used || entry.external != external {
            continue
        }
        allowed: bool
        switch {
        case nat.config.mapping != .INDEPENDENT:
            allowed = source == entry.dest
        case nat.config.filter == .FULL_CONE:
            allowed = true
        case:
            for i in 0 ..< entry.permitted_count {
                same_address: bool = entry.permitted[i].address == source.address
                if same_address && (nat.config.filter == .ADDRESS_RESTRICTED || entry.permitted[i].port == source.port) {
                    allowed = true
                    break
                }
            }
        }
        if !allowed {
            return
        }
        for i in 0 ..< sim.host_count {
            if sim.hosts[i].nat >= 0 && &sim.nats[sim.hosts[i].nat] == nat && sim.hosts[i].private == entry.inside {
                SimQueue(&sim.hosts[i], source, data)
            }
        }
        return
    }
}

// A STUN server with two addresses. The answer comes from the address the request asked for (CHANGE-REQUEST), which is how a
// client tests whether its NAT lets strangers in.
SimStunServe :: proc(sim: ^Sim, server: ^SimStun, to: net.Endpoint, source: net.Endpoint, request: []byte) {
    // as strict as the real ones: the datagram is exactly the header plus the attributes it announces
    if len(request) < STUN_HEADER_SIZE || !StunLooksLikeStun(request) || GetU16BE(request[0:]) != STUN_BINDING_REQUEST {
        return
    }
    if len(request) != STUN_HEADER_SIZE + int(GetU16BE(request[2:])) {
        return
    }
    from: net.Endpoint = to
    if flags, found := StunFindAttribute(request, STUN_ATTR_CHANGE_REQUEST); found && len(flags) >= 4 {
        change: u32 = GetU32BE(flags)
        if change & STUN_CHANGE_IP != 0 {
            from.address = server.other.address if to == server.endpoint else server.endpoint.address
        }
        if change & STUN_CHANGE_PORT != 0 {
            from.port = server.other.port if to == server.endpoint else server.endpoint.port
        }
    }
    response: [64]byte
    PutU16BE(response[0:], STUN_BINDING_SUCCESS)
    PutU32BE(response[4:], STUN_MAGIC)
    copy(response[8:20], request[8:20])
    offset: int = STUN_HEADER_SIZE
    offset = SimPutAddress(response[:], offset, STUN_ATTR_XOR_MAPPED, source, true)
    offset = SimPutAddress(response[:], offset, STUN_ATTR_RESPONSE_ORIGIN, from, false)
    offset = SimPutAddress(response[:], offset, STUN_ATTR_OTHER_ADDRESS, server.other if to == server.endpoint else server.endpoint, false)
    PutU16BE(response[2:], u16(offset - STUN_HEADER_SIZE))
    sim.served += 1
    SimRoute(sim, from, source, response[:offset])
}

SimPutAddress :: proc(buffer: []byte, offset: int, kind: u16, endpoint: net.Endpoint, xor: bool) -> int {
    address: net.IP4_Address = endpoint.address.(net.IP4_Address)
    PutU16BE(buffer[offset:], kind)
    PutU16BE(buffer[offset + 2:], 8)
    buffer[offset + 4] = 0
    buffer[offset + 5] = 1
    port: u16 = u16(endpoint.port)
    if xor {
        port ~= u16(STUN_MAGIC >> 16)
    }
    PutU16BE(buffer[offset + 6:], port)
    for i in 0 ..< 4 {
        buffer[offset + 8 + i] = address[i] ~ (byte(STUN_MAGIC >> u32(24 - 8 * i)) if xor else 0)
    }
    return offset + 12
}

// ============================================================ a TURN server

SimTurnFind :: proc(sim: ^Sim, client: net.Endpoint) -> ^SimAllocation {
    for &allocation in sim.allocations {
        if allocation.used && allocation.client == client && allocation.expires_ms > sim.now_ms {
            return &allocation
        }
    }
    return nil
}

SimTurnPermit :: proc(sim: ^Sim, allocation: ^SimAllocation, address: net.IP4_Address) {
    for i in 0 ..< allocation.permission_count {
        if allocation.permissions[i] == address {
            allocation.permission_expires_ms[i] = sim.now_ms + 300000
            return
        }
    }
    if allocation.permission_count < len(allocation.permissions) {
        allocation.permissions[allocation.permission_count] = address
        allocation.permission_expires_ms[allocation.permission_count] = sim.now_ms + 300000
        allocation.permission_count += 1
    }
}

SimTurnReply :: proc(sim: ^Sim, client: net.Endpoint, buffer: []byte, length: int) {
    SimRoute(sim, sim.turn, client, buffer[:length])
}

SimTurnError :: proc(sim: ^Sim, client: net.Endpoint, request: []byte, code: int) {
    txid: StunTxId
    copy(txid[:], request[8:20])
    buffer: [256]byte
    offset: int = StunBegin(buffer[:], GetU16BE(request[0:]) | 0x0110, txid)
    offset = StunAppend(buffer[:], offset, TURN_ATTR_ERROR, []byte{0, 0, byte(code / 100), byte(code % 100)})
    offset = StunAppend(buffer[:], offset, TURN_ATTR_REALM, transmute([]byte)string(SIM_TURN_REALM))
    offset = StunAppend(buffer[:], offset, TURN_ATTR_NONCE, transmute([]byte)string(SIM_TURN_NONCE))
    SimTurnReply(sim, client, buffer[:], offset)
}

// Authentication, allocations, refreshes, permissions and Send indications of one client.
SimTurnServe :: proc(sim: ^Sim, source: net.Endpoint, data: []byte) {
    if !StunLooksLikeStun(data) || len(data) != STUN_HEADER_SIZE + int(GetU16BE(data[2:])) {
        return
    }
    kind: u16 = GetU16BE(data[0:])
    allocation: ^SimAllocation = SimTurnFind(sim, source)
    if kind == TURN_SEND_INDICATION {
        peer_value, found := StunFindAttribute(data, TURN_ATTR_PEER)
        payload, has_payload := StunFindAttribute(data, TURN_ATTR_DATA)
        peer, peer_ok := StunReadAddress(peer_value, true)
        if allocation == nil || !found || !has_payload || !peer_ok {
            return
        }
        // sending to an address also opens the permission for what comes back from it
        SimTurnPermit(sim, allocation, peer.address.(net.IP4_Address))
        sim.relayed_bytes += len(payload)
        SimRoute(sim, allocation.relayed, peer, payload)
        return
    }

    key: [16]byte = TurnKey(SIM_TURN_USER, SIM_TURN_REALM, SIM_TURN_PASSWORD)
    if _, signed := StunFindAttribute(data, TURN_ATTR_INTEGRITY); !signed || !StunVerify(data, key[:]) {
        SimTurnError(sim, source, data, 401)
        return
    }
    nonce, _ := StunFindAttribute(data, TURN_ATTR_NONCE)
    if string(nonce) != SIM_TURN_NONCE {
        SimTurnError(sim, source, data, 438)
        return
    }
    txid: StunTxId
    copy(txid[:], data[8:20])
    buffer: [256]byte
    offset: int
    switch kind {
    case TURN_ALLOCATE:
        if allocation == nil {
            for &candidate, index in sim.allocations {
                if !candidate.used || candidate.expires_ms <= sim.now_ms {
                    candidate = {used = true, client = source, relayed = {net.IP4_Address{192, 0, 2, 51}, 49152 + index}}
                    allocation = &candidate
                    break
                }
            }
        }
        if allocation == nil {
            SimTurnError(sim, source, data, 486)
            return
        }
        allocation.expires_ms = sim.now_ms + 600000
        offset = StunBegin(buffer[:], TURN_ALLOCATE | 0x0100, txid)
        offset = StunAppendAddress(buffer[:], offset, TURN_ATTR_RELAYED, allocation.relayed)
        offset = StunAppendAddress(buffer[:], offset, STUN_ATTR_XOR_MAPPED, source)
        lifetime: [4]byte
        PutU32BE(lifetime[:], 600)
        offset = StunAppend(buffer[:], offset, TURN_ATTR_LIFETIME, lifetime[:])
    case TURN_REFRESH:
        if allocation == nil {
            SimTurnError(sim, source, data, 437)
            return
        }
        allocation.expires_ms = sim.now_ms + 600000
        offset = StunBegin(buffer[:], TURN_REFRESH | 0x0100, txid)
        lifetime: [4]byte
        PutU32BE(lifetime[:], 600)
        offset = StunAppend(buffer[:], offset, TURN_ATTR_LIFETIME, lifetime[:])
    case TURN_CREATE_PERMISSION:
        if allocation == nil {
            SimTurnError(sim, source, data, 437)
            return
        }
        position: int = STUN_HEADER_SIZE
        for position + 4 <= len(data) {
            attribute: u16 = GetU16BE(data[position:])
            size: int = int(GetU16BE(data[position + 2:]))
            if attribute == TURN_ATTR_PEER {
                peer, ok := StunReadAddress(data[position + 4:position + 4 + size], true)
                if ok {
                    SimTurnPermit(sim, allocation, peer.address.(net.IP4_Address))
                }
            }
            position += 4 + (size + 3) & ~int(3)
        }
        offset = StunBegin(buffer[:], TURN_CREATE_PERMISSION | 0x0100, txid)
    case:
        return
    }
    SimTurnReply(sim, source, buffer[:], offset)
}

// A datagram that reached a relayed address: forwarded to the client as a Data indication if its sender has a permission.
SimTurnInbound :: proc(sim: ^Sim, allocation: ^SimAllocation, source: net.Endpoint, data: []byte) {
    if allocation.expires_ms <= sim.now_ms {
        return
    }
    address, is_ip4 := source.address.(net.IP4_Address)
    if !is_ip4 {
        return
    }
    allowed: bool
    for i in 0 ..< allocation.permission_count {
        allowed ||= allocation.permissions[i] == address && allocation.permission_expires_ms[i] > sim.now_ms
    }
    if !allowed {
        return
    }
    buffer: [1400]byte
    txid: StunTxId = {9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9}
    offset: int = StunBegin(buffer[:], TURN_DATA_INDICATION, txid)
    offset = StunAppendAddress(buffer[:], offset, TURN_ATTR_PEER, source)
    offset = StunAppend(buffer[:], offset, TURN_ATTR_DATA, data)
    sim.relayed_bytes += len(data)
    SimRoute(sim, sim.turn, allocation.client, buffer[:offset])
}

// ============================================================ driving two links through the simulation

SimPump :: proc(a: ^Link, b: ^Link, now: ^i64, steps: int) {
    for _ in 0 ..< steps {
        now^ += 10
        if a.transport.user != nil {
            (^SimHost)(a.transport.user).sim.now_ms = now^
        }
        LinkUpdate(a, now^)
        LinkUpdate(b, now^)
    }
}

SimLink :: proc(host: ^SimHost) -> ^Link {
    link: ^Link = new(Link)
    config: LinkConfig
    config.local_addresses[0] = host.private.address.(net.IP4_Address)
    config.local_address_count = 1
    config.local_v6 = host.v6.address.(net.IP6_Address) if host.has_v6 else {}
    config.local_v6_set = host.has_v6
    LinkInitTransport(link, SimTransport(host), host.private.port, config)
    return link
}

// The whole flow of two people: gather, host code, guest pastes it, reply code, host pastes it, then punching.
// Returns the milliseconds (fake clock) until both sides were connected, or -1.
SimConnect :: proc(sim: ^Sim, a: ^Link, b: ^Link, now: ^i64, limit_ms: i64 = 30000, relay_a: bool = false, relay_b: bool = false, password: string = SIM_TURN_PASSWORD) -> i64 {
    servers: [2]net.Endpoint = {sim.stuns[0].endpoint, sim.stuns[1].endpoint}
    if relay_a {
        LinkTurnBegin(a, sim.turn, SIM_TURN_USER, password, now^)
    }
    if relay_b {
        LinkTurnBegin(b, sim.turn, SIM_TURN_USER, password, now^)
    }
    LinkGatherBegin(a, servers[:], now^)
    LinkGatherBegin(b, servers[:], now^)
    for !LinkGathered(a) || !LinkGathered(b) {
        SimPump(a, b, now, 1)
        if now^ > 20000 {
            return -1
        }
    }
    LinkHost(a, "A")
    text: [CODE_TEXT_MAX]byte
    invite_text, _ := InviteEncode(LinkMakeInvite(a), text[:])
    invite, invite_ok := InviteDecode(invite_text)
    if !invite_ok || !LinkJoin(b, invite, "B", now^) {
        return -1
    }
    reply_text: [CODE_TEXT_MAX]byte
    reply_code, _ := InviteEncode(LinkMakeInvite(b), reply_text[:])
    reply, reply_ok := InviteDecode(reply_code)
    if !reply_ok {
        return -1
    }
    started: i64 = now^
    if _, accepted := LinkAcceptReply(a, reply, now^); !accepted {
        return -1
    }
    for now^ - started < limit_ms {
        SimPump(a, b, now, 1)
        if LinkPeerCount(a) == 1 && LinkPeerCount(b) == 1 {
            return now^ - started
        }
    }
    return -1
}

// Two hosts behind NATs of the given kinds (PUBLIC = no NAT), connected through the whole flow.
SimPair :: proc(kind_a: SimKind, kind_b: SimKind, relay_a: bool = false, relay_b: bool = false, v6_a: bool = false, v6_b: bool = false) -> (milliseconds: i64) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    nat_a: int = -1 if kind_a == .PUBLIC else SimAddNat(sim, SimConfigOf(kind_a))
    nat_b: int = -1 if kind_b == .PUBLIC else SimAddNat(sim, SimConfigOf(kind_b))
    host_a: ^SimHost = SimAddHost(sim, nat_a)
    host_b: ^SimHost = SimAddHost(sim, nat_b)
    if v6_a {
        SimGiveV6(host_a, true)
    }
    if v6_b {
        SimGiveV6(host_b, true)
    }
    a: ^Link = SimLink(host_a)
    b: ^Link = SimLink(host_b)
    defer free(a)
    defer free(b)
    now: i64
    return SimConnect(sim, a, b, &now, 30000, relay_a, relay_b)
}

// ============================================================ tests

// What the library is expected to manage for every pair of NAT kinds. A pair that is expected to fail is listed on purpose:
// the day an improvement makes it work, the test says so and the expectation moves to the other side.
SimExpected :: proc(a: SimKind, b: SimKind) -> bool {
    random :: proc(kind: SimKind) -> bool {
        return kind == .SYMMETRIC_RANDOM
    }
    symmetric :: proc(kind: SimKind) -> bool {
        return kind == .SYMMETRIC_SEQUENTIAL || kind == .SYMMETRIC_RANDOM
    }
    // a port that cannot be guessed needs the other side to accept anything, or an address on the open internet
    if random(a) && (b == .PORT_RESTRICTED || symmetric(b)) || random(b) && (a == .PORT_RESTRICTED || symmetric(a)) {
        return false
    }
    return true
}

@(test)
SimNatMatrixTest :: proc(t: ^testing.T) {
    for a in SimKind {
        for b in SimKind {
            took: i64 = SimPair(a, b)
            testing.expectf(t, (took >= 0) == SimExpected(a, b), "%v with %v: connected=%v (took %v ms), expected %v", a, b, took >= 0, took, SimExpected(a, b))
        }
    }
}

// Two computers on one home network behind a symmetric NAT: the local address is the way, the NAT is not involved at all.
@(test)
SimSameLanTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    nat: int = SimAddNat(sim, SimConfigOf(.SYMMETRIC_RANDOM))
    a: ^Link = SimLink(SimAddHost(sim, nat))
    b: ^Link = SimLink(SimAddHost(sim, nat))
    defer free(a)
    defer free(b)
    now: i64
    testing.expect(t, SimConnect(sim, a, b, &now) >= 0)
}

// Chat over a punched connection with loss, for a pair that needs the punching to have worked first.
@(test)
SimDataThroughNatTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    nat_a: int = SimAddNat(sim, SimConfigOf(.PORT_RESTRICTED))
    nat_b: int = SimAddNat(sim, SimConfigOf(.ADDRESS_RESTRICTED))
    a: ^Link = SimLink(SimAddHost(sim, nat_a))
    b: ^Link = SimLink(SimAddHost(sim, nat_b))
    defer free(a)
    defer free(b)
    now: i64
    testing.expect(t, SimConnect(sim, a, b, &now) >= 0)
    a.drop_percent = 30
    b.drop_percent = 30
    sent, received: int
    buffer: [MAX_PAYLOAD]byte
    for _ in 0 ..< 2000 {
        if sent < 60 {
            message: [1]byte = {byte(sent)}
            if LinkSend(a, 0, message[:], true, now) {
                sent += 1
            }
        }
        SimPump(a, b, &now, 1)
        for {
            _, length, ok := LinkReceive(b, buffer[:])
            if !ok {
                break
            }
            testing.expect_value(t, int(buffer[0]), received)
            received += 1
            _ = length
        }
        if received == 60 {
            break
        }
    }
    testing.expect_value(t, received, 60)
}

// The measurement against each kind of NAT: mapping, filtering (needs the CHANGE-REQUEST answer to get through or be filtered)
// and the port step that makes a symmetric NAT guessable.
@(test)
SimNatDetectTest :: proc(t: ^testing.T) {
    Case :: struct {
        kind: SimKind,
        mapping: NatMapping,
        filtering: NatFiltering,
        delta: int,
    }
    cases := [?]Case{
        {.PUBLIC, .INDEPENDENT, .OPEN, 0},
        {.FULL_CONE, .INDEPENDENT, .OPEN, 0},
        {.ADDRESS_RESTRICTED, .INDEPENDENT, .ADDRESS, 0},
        {.PORT_RESTRICTED, .INDEPENDENT, .PORT, 0},
        {.SYMMETRIC_SEQUENTIAL, .DEPENDENT, .PORT, 1},
        {.SYMMETRIC_RANDOM, .DEPENDENT, .PORT, 0},
    }
    for c in cases {
        sim: ^Sim = new(Sim)
        defer free(sim)
        SimInit(sim)
        nat: int = -1 if c.kind == .PUBLIC else SimAddNat(sim, SimConfigOf(c.kind))
        link: ^Link = SimLink(SimAddHost(sim, nat))
        other: ^Link = SimLink(SimAddHost(sim, -1))
        defer free(link)
        defer free(other)
        servers: [2]net.Endpoint = {sim.stuns[0].endpoint, sim.stuns[1].endpoint}
        now: i64
        LinkGatherBegin(link, servers[:], now)
        SimPump(link, other, &now, 400)
        testing.expectf(t, LinkGathered(link), "%v: not gathered", c.kind)
        testing.expectf(t, link.nat_mapping == c.mapping, "%v: mapping %v, expected %v", c.kind, link.nat_mapping, c.mapping)
        testing.expectf(t, link.nat_filtering == c.filtering, "%v: filtering %v, expected %v", c.kind, link.nat_filtering, c.filtering)
        testing.expectf(t, link.nat_port_delta == c.delta, "%v: port step %v, expected %v", c.kind, link.nat_port_delta, c.delta)
        if c.mapping == .DEPENDENT {
            // one public candidate only, the last port: the one next to what the peer will get
            public: int
            for i in 0 ..< link.candidate_count {
                public += int(IsPublicAddress(link.candidates[i].address))
            }
            testing.expectf(t, public == 1, "%v: %v public candidates", c.kind, public)
        }
    }
}

@(test)
IsPublicAddressTest :: proc(t: ^testing.T) {
    testing.expect(t, IsPublicAddress(net.IP4_Address{8, 8, 8, 8}))
    testing.expect(t, IsPublicAddress(net.IP4_Address{192, 0, 2, 2}))
    testing.expect(t, !IsPublicAddress(net.IP4_Address{10, 48, 0, 11}))
    testing.expect(t, !IsPublicAddress(net.IP4_Address{172, 31, 9, 136}))
    testing.expect(t, IsPublicAddress(net.IP4_Address{172, 32, 0, 1}))
    testing.expect(t, !IsPublicAddress(net.IP4_Address{192, 168, 1, 1}))
    testing.expect(t, !IsPublicAddress(net.IP4_Address{100, 64, 0, 1}))
    testing.expect(t, !IsPublicAddress(net.IP4_Address{0, 0, 0, 0}))
    testing.expect(t, !IsPublicAddress(net.IP4_Address{127, 0, 0, 1}))
}

// With a TURN allocation on one side, every pair connects, even two symmetric NATs with unpredictable ports.
@(test)
SimRelayMatrixTest :: proc(t: ^testing.T) {
    for a in SimKind {
        for b in SimKind {
            testing.expectf(t, SimPair(a, b, true, false) >= 0, "%v (relay) with %v: not connected", a, b)
            testing.expectf(t, SimPair(a, b, false, true) >= 0, "%v with %v (relay): not connected", a, b)
        }
    }
}

// The relay is a way in, not a home: when a direct path works the connection ends up on it.
@(test)
SimRelayUpgradeTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    a: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.FULL_CONE))))
    b: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.FULL_CONE))))
    defer free(a)
    defer free(b)
    now: i64
    testing.expect(t, SimConnect(sim, a, b, &now, 30000, true, false) >= 0)
    SimPump(a, b, &now, 300)
    testing.expect(t, !a.peers[0].via_relay)
    testing.expect(t, !b.peers[0].via_relay)
}

// Two unpredictable symmetric NATs: only the relay carries the chat, over loss, and still works after the allocation and the
// permissions were renewed several times (the fake server expires them like the real one).
@(test)
SimRelayDataAndRenewalTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    a: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.SYMMETRIC_RANDOM))))
    b: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.SYMMETRIC_RANDOM))))
    defer free(a)
    defer free(b)
    now: i64
    testing.expect(t, SimConnect(sim, a, b, &now, 30000, true, false) >= 0)
    testing.expect(t, a.peers[0].via_relay)
    testing.expect(t, !b.peers[0].via_relay)

    a.drop_percent = 20
    b.drop_percent = 20
    buffer: [MAX_PAYLOAD]byte
    // 30 messages, then 25 simulated minutes of idle keepalives, then 30 more
    for round in 0 ..< 2 {
        sent, received: int
        for _ in 0 ..< 3000 {
            if sent < 30 {
                message: [2]byte = {byte(round), byte(sent)}
                if LinkSend(b, 0, message[:], true, now) {
                    sent += 1
                }
            }
            SimPump(a, b, &now, 1)
            for {
                _, length, ok := LinkReceive(a, buffer[:])
                if !ok {
                    break
                }
                testing.expect_value(t, int(buffer[1]), received)
                testing.expect_value(t, length, 2)
                received += 1
            }
            if received == 30 {
                break
            }
        }
        testing.expectf(t, received == 30, "round %v: %v of 30 messages", round, received)
        if round == 0 {
            SimPump(a, b, &now, 150000)
        }
    }
    testing.expect(t, sim.relayed_bytes > 0)
}

@(test)
SimRelayWrongPasswordTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    a: ^Link = SimLink(SimAddHost(sim, -1))
    b: ^Link = SimLink(SimAddHost(sim, -1))
    defer free(a)
    defer free(b)
    now: i64
    // the gathering does not hang on a refused allocation: it ends, the link says why, and the connection is made without it
    testing.expect(t, SimConnect(sim, a, b, &now, 30000, true, false, "wrong") >= 0)
    testing.expect_value(t, a.turn.phase, TurnPhase.FAILED)
    testing.expect_value(t, a.turn.failure, 401)
    failed: bool
    for {
        event, ok := LinkPollEvent(a)
        if !ok {
            break
        }
        failed ||= event.kind == .RELAY_FAILED
    }
    testing.expect(t, failed)
}

@(test)
SimRelayUnreachableServerTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    sim.turn_down = true
    a: ^Link = SimLink(SimAddHost(sim, -1))
    b: ^Link = SimLink(SimAddHost(sim, -1))
    defer free(a)
    defer free(b)
    now: i64
    testing.expect(t, SimConnect(sim, a, b, &now, 30000, true, false) >= 0)
    testing.expect_value(t, a.turn.phase, TurnPhase.FAILED)
    testing.expect_value(t, a.turn.failure, 0)
}

// With IPv6 on both sides there is no NAT in the way: even two symmetric NATs with unpredictable ports connect, through the
// stateful firewalls, because both sides send first.
@(test)
SimIPv6Test :: proc(t: ^testing.T) {
    for a in SimKind {
        for b in SimKind {
            testing.expectf(t, SimPair(a, b, false, false, true, true) >= 0, "%v with %v, both IPv6: not connected", a, b)
        }
    }
    // only one side has it: the IPv4 path decides, as before
    testing.expect(t, SimPair(.SYMMETRIC_RANDOM, .SYMMETRIC_RANDOM, false, false, true, false) < 0)
    testing.expect(t, SimPair(.FULL_CONE, .PORT_RESTRICTED, false, false, true, false) >= 0)
}

@(test)
SimIPv6IsUsedTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    host_a: ^SimHost = SimAddHost(sim, SimAddNat(sim, SimConfigOf(.SYMMETRIC_RANDOM)))
    host_b: ^SimHost = SimAddHost(sim, SimAddNat(sim, SimConfigOf(.SYMMETRIC_RANDOM)))
    SimGiveV6(host_a, true)
    SimGiveV6(host_b, true)
    a: ^Link = SimLink(host_a)
    b: ^Link = SimLink(host_b)
    defer free(a)
    defer free(b)
    now: i64
    testing.expect(t, SimConnect(sim, a, b, &now) >= 0)
    _, a_is_v6 := a.peers[0].endpoint.address.(net.IP6_Address)
    _, b_is_v6 := b.peers[0].endpoint.address.(net.IP6_Address)
    testing.expect(t, a_is_v6 && b_is_v6)

    // chat over it
    testing.expect(t, LinkSend(a, 0, transmute([]byte)string("v6 hello"), true, now))
    SimPump(a, b, &now, 20)
    buffer: [MAX_PAYLOAD]byte
    _, length, ok := LinkReceive(b, buffer[:])
    testing.expect(t, ok)
    testing.expect_value(t, string(buffer[:length]), "v6 hello")
}

// The real IPv6 socket path: two links on this computer, a datagram over ::1 from one to the other. Skipped where the
// computer has no IPv6.
@(test)
LinkIPv6LoopbackTest :: proc(t: ^testing.T) {
    a: ^Link = new(Link)
    b: ^Link = new(Link)
    defer free(a)
    defer free(b)
    testing.expect(t, LinkInit(a))
    testing.expect(t, LinkInit(b))
    defer LinkClose(a)
    defer LinkClose(b)
    if !a.has_v6 || !b.has_v6 {
        return
    }
    message: []byte = {1, 2, 3}
    LinkSendRaw(a, {address = net.IP6_Loopback, port = b.local_port6}, message)
    arrived: bool
    for _ in 0 ..< 200 {
        length, from := LinkReadRaw(b)
        if length == 3 {
            testing.expect_value(t, b.datagram[1], u8(2))
            testing.expect_value(t, from.port, a.local_port6)
            arrived = true
            break
        }
        time.sleep(time.Millisecond)
    }
    testing.expect(t, arrived, "no datagram arrived over ::1")
}
