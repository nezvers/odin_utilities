// A Link is one UDP socket that finds its public address with STUN, punches through NATs towards the peers whose codes it was
// given, and then carries messages: unreliable (fire and forget) or reliable (ordered, resent until acknowledged).
//
//   host:  LinkInit, LinkGatherBegin, (LinkUpdate until LinkGathered), LinkHost, LinkMakeInvite -> show the code,
//          LinkAcceptReply(pasted reply code) per guest
//   guest: LinkInit, LinkGatherBegin, (LinkUpdate until LinkGathered), LinkJoin(pasted invite), LinkMakeInvite -> show the reply
//   both:  every frame LinkUpdate, then LinkPollEvent / LinkReceive, LinkSend
//
// Memory: a Link is plain data with fixed capacities (peers, window, inbox, events). The caller places it (a global, a field,
// the heap once). Nothing is allocated per frame; failures are reported (send returns false when the window is full) instead of
// growing. Time is passed in (`now_ms`, see LinkNow) so tests can run a fake clock.
//
// Every packet after the header is sealed (XSalsa20-Poly1305, see nacl.odin) with a key made from the secret that only the invite
// carries, so the route (a free relay, a TURN server, the open internet) sees sizes and timing but nothing else, cannot forge a
// packet and cannot replay one. The key is per pair of ids and the packet counter in the nonce is checked against a window.
//
// Not covered, on purpose and stated in the README: the invite itself must reach the other person privately (a code in a public
// place gives the channel away), IPv4 only, and two peers behind symmetric NATs (or CGNAT on both sides) need a relay: DERP or TURN.
// The Link tells (`link.nat`) so the program can say why a connection failed.
package p2p

import "core:crypto"
import "core:crypto/sha2"
import "core:net"
import "core:testing"
import "core:time"

MAX_PEERS :: 8
MAX_PAYLOAD :: 1000                 // bytes of one message, keeps a datagram under the usual 1200 byte safe size
WINDOW :: 16                        // reliable messages in flight per peer, a power of two (sequence numbers wrap on it)
INBOX :: 64                         // received messages waiting for LinkReceive
EVENTS :: 32
PACKET_MAGIC :: u8(0xD7)            // STUN messages start with 0x00..0x3F, so the two never get mixed up
PACKET_HEADER :: 10                 // magic, kind, session tag (u32), id of the sender (u32)
PACKET_CRYPTO :: 8 + 1 + BOX_AUTH_SIZE     // counter (u64), kind inside the seal, authenticator: what sealing adds after the header
PUNCH_INTERVAL_MS :: 200
PUNCH_TIMEOUT_MS :: 20000
RESEND_FIRST_MS :: 250              // resend timeout until a round trip was measured
RESEND_MIN_MS :: 40
RESEND_MAX_MS :: 1000
STALL_MS :: 6000                    // reliable messages waiting this long without any acknowledgement: the peer is lost
KEEPALIVE_MS :: 1000                // also keeps the NAT mapping open
SILENCE_MS :: 8000
GATHER_RETRY_MS :: 500
GATHER_TIMEOUT_MS :: 2500
DATAGRAMS_PER_UPDATE :: 256
STUN_MAX_SERVERS :: len(STUN_SERVERS)
FILTER_STEP_MS :: 250
FILTER_PHASE_MS :: 1000
SPRAY_PORTS :: 32                   // ports guessed per punch round towards a peer behind a symmetric NAT

PacketKind :: enum u8 {
    PUNCH = 1,                      // "I am here"
    PUNCH_ACK,                      // answer to a PUNCH
    DATA,                           // unreliable message
    DATA_RELIABLE,                  // seq u16, ack u16, message
    ACK,                            // ack u16 (also the keepalive)
    CLOSE,
    SIGNAL,                         // an invite sent through the DERP relay (see derp_link.odin)
    WHO,                            // "is there a host of this channel?" to the channel key at the relay (no session yet, no tag)
    HERE,                           // the host's answer: its short invite
}

// How the NAT chooses the public port of a socket (RFC 4787 mapping behavior), measured by asking several STUN servers.
NatMapping :: enum u8 {
    UNKNOWN,                        // fewer than two servers answered
    INDEPENDENT,                    // same public port towards every server: the address in the code is what the peer hits
    DEPENDENT,                      // a new public port per destination (symmetric NAT): the peer has to guess it
}

// Who may send to the public port (filtering behavior), measured with a STUN server that can answer from another address.
NatFiltering :: enum u8 {
    UNKNOWN,
    OPEN,                           // anybody (full cone)
    ADDRESS,                        // only addresses we sent to
    PORT,                           // only the exact address and port we sent to
}

FilterState :: enum {
    IDLE,
    BOTH,                           // asking for an answer from another address and port
    PORT_ONLY,                      // asking for an answer from another port
    DONE,
}

GatherState :: enum {
    IDLE,
    RUNNING,
    DONE,
}

PeerState :: enum {
    EMPTY,
    PUNCHING,
    CONNECTED,
    FAILED,                         // never answered (see link.nat for the likely reason)
    LOST,                           // was connected, went silent or closed
}

LinkRole :: enum {
    NONE,
    HOST,
    GUEST,
}

LinkEventKind :: enum {
    GATHERED,
    PEER_CONNECTED,
    PEER_FAILED,
    PEER_LOST,
    NAT_MEASURED,                   // the filtering test finished (it runs after GATHERED)
    RELAY_READY,                    // the TURN server gave a relayed address (now a candidate)
    RELAY_FAILED,                   // wrong credentials, no answer, quota: link.turn.failure says why
    DERP_READY,                     // the DERP relay connection is up (codes made from now on carry it)
    DERP_FAILED,                    // link.derp.failure says why (and link.derp.failure_kind, DerpAdvice(kind) what to do)
    DERP_SWITCHED,                  // the relay stayed down and the link moved to another one (link.derp.server): codes made before name the old one
    DERP_LOST,                      // a working relay connection ended: it is reconnected by itself (DERP_READY comes again)
    DERP_HOST_FOUND,                // LinkDerpFind got an answer: link.derp.found is the host's invite, LinkJoin it
}

LinkEvent :: struct {
    kind: LinkEventKind,
    peer: int,
}

LinkConfig :: struct {
    port: u16,                      // local UDP port, 0 = any
    include_loopback: bool,         // also offer 127.0.0.1 (two programs on one computer, tests)
    // Offer exactly these local addresses instead of the ones found on the network cards (a program that knows better, a
    // simulated network). Zero count = look at the network cards.
    local_addresses: [MAX_CANDIDATES]net.IP4_Address,
    local_address_count: int,
    // Put only the TURN relayed address in the code (once the relay is ready): the peer never learns this computer's own
    // addresses, and the whole conversation goes through the relay. For privacy, and for testing a relay end to end.
    relay_only: bool,
    no_ipv6: bool,                  // do not open the IPv6 socket
    // An IPv6 address to offer instead of the one found on the network cards (simulated network, tests).
    local_v6: net.IP6_Address,
    local_v6_set: bool,
    // DERP relay identity: random unless set (a fixed key makes a fixed address there, which is what a rendezvous by name needs).
    derp_private: BoxKey,
    derp_private_set: bool,
    // Offer only the DERP relay (no addresses): everything goes through it. For privacy and for testing the relay end to end.
    derp_only: bool,
    derp_no_failover: bool,         // stay on the relay that was chosen however long it is down (a relay in the list is otherwise replaced after DERP_FAILOVER_MS)
}

// Where datagrams go in and out. The default is the UDP socket; a program (or a test with a simulated network) can put its own
// underneath: `send` fires and forgets, `receive` returns false when nothing is waiting.
Transport :: struct {
    user: rawptr,
    send: proc(user: rawptr, to: net.Endpoint, data: []byte),
    receive: proc(user: rawptr, buffer: []byte) -> (length: int, from: net.Endpoint, ok: bool),
}

Message :: struct {
    peer: u8,
    length: u16,
    data: [MAX_PAYLOAD]byte,
}

Peer :: struct {
    state: PeerState,
    id: u32,                        // from its invite
    name: [NAME_MAX]byte,
    name_len: int,
    candidates: [MAX_CANDIDATES]net.Endpoint,
    candidate_count: int,
    endpoint: net.Endpoint,         // where it really answered from, set when connected
    via_relay: bool,                // the packets from it arrive through a relay (our TURN allocation or DERP), so they are answered through it
    has_derp: bool,                 // it told us its key at the DERP relay we are connected to
    derp_key: BoxKey,
    signal_ms: i64,                 // last time a guest sent its reply through the relay
    upgrade_ms: i64,                // last time a connection through a relay tried the direct path
    nat_mapping: NatMapping,        // from its code: how to reach it
    nat_filtering: NatFiltering,
    port_delta: int,                // public port step of its NAT between destinations (0 = unknown)
    last_port: int,                 // the last public port its NAT handed out while it gathered
    punch_start_ms: i64,
    punch_last_ms: i64,
    rx_ms: i64,
    tx_ms: i64,

    // reliable channel (selective repeat): both windows are indexed by sequence % WINDOW
    send_next: u16,                 // sequence of the next new message
    send_base: u16,                 // oldest message not yet acknowledged
    send_count: int,                // messages in flight (base .. base + count)
    send_progress_ms: i64,          // last time an acknowledgement told something new
    send_length: [WINDOW]u16,
    send_data: [WINDOW][MAX_PAYLOAD]byte,
    send_acked: [WINDOW]bool,       // the peer has this one already but an older one is still missing
    send_last_ms: [WINDOW]i64,      // last (re)send
    send_attempts: [WINDOW]u8,      // resends so far; 0 means the round trip of its acknowledgement is a clean sample
    rtt_ms: f32,                    // smoothed round trip, 0 = not measured
    recv_next: u16,                 // sequence expected from the peer: everything before it was delivered
    recv_have: [WINDOW]bool,        // arrived ahead of recv_next, waiting for the missing ones before it
    recv_length: [WINDOW]u16,
    recv_data: [WINDOW][MAX_PAYLOAD]byte,
    ack_due: bool,

    rx_packets: u64,
    tx_packets: u64,
    resent: u64,

    key: BoxKey,                    // seals the packets with this peer, see PeerKeyMake
    send_counter: u64,              // next nonce counter, starts at a random value so a restarted peer never repeats a nonce
    recv_top: u64,                  // the highest counter that opened; recv_seen bit k = counter recv_top - k opened (replay window)
    recv_seen: u64,
    recv_any: bool,
    rejected: u64,                  // packets that did not open: forged, damaged or sealed for another session
}

Link :: struct {
    socket: net.UDP_Socket,
    socket6: net.UDP_Socket,        // IPv6, when the computer has it: with a global address on both sides there is no NAT at all
    has_v6: bool,
    local_port6: int,
    transport: Transport,           // nil procs: the socket is used
    open: bool,
    config: LinkConfig,
    role: LinkRole,
    id: u32,                        // identifies this link in punch packets
    session: u64,
    secret: [SECRET_SIZE]byte,      // the host makes it, the invite hands it on
    tag: u32,                       // session as sent in every packet
    name: [NAME_MAX]byte,
    name_len: int,
    local_port: int,

    // candidates this link can be reached at, what goes into its code
    candidates: [MAX_CANDIDATES]net.Endpoint,
    candidate_count: int,

    gather: GatherState,
    gather_start_ms: i64,
    gather_sent_ms: i64,
    stun_servers: [STUN_MAX_SERVERS]net.Endpoint,
    stun_txid: [STUN_MAX_SERVERS]StunTxId,
    stun_mapped: [STUN_MAX_SERVERS]net.Endpoint,    // what each server saw
    stun_answered: [STUN_MAX_SERVERS]bool,
    stun_other: [STUN_MAX_SERVERS]net.Endpoint,     // its second address, when it has one
    stun_has_other: [STUN_MAX_SERVERS]bool,
    stun_count: int,
    nat_mapping: NatMapping,
    nat_filtering: NatFiltering,
    nat_port_delta: int,            // how much the public port grows per new destination, 0 = no pattern seen
    nat_last_port: int,             // the last port allocated while gathering, the next one is probably last + delta
    portmap: ^PortMapState,         // set by LinkPortMap, given back by LinkClose
    turn: TurnClient,               // see LinkTurnBegin
    derp: DerpPath,                 // see LinkDerpBegin
    filter_state: FilterState,
    filter_server: int,
    filter_txid: StunTxId,
    filter_sent_ms: i64,
    filter_phase_ms: i64,

    peers: [MAX_PEERS]Peer,
    inbox: [INBOX]Message,
    inbox_head: int,
    inbox_count: int,
    events: [EVENTS]LinkEvent,
    event_head: int,
    event_count: int,

    // test hook: drop this percent of the received datagrams (pseudo random, so a pattern cannot line up with the resends)
    drop_percent: int,
    drop_state: u32,
    datagram: [PACKET_HEADER + PACKET_CRYPTO + 8 + MAX_PAYLOAD + TURN_OVERHEAD + 16]byte,
}

// Milliseconds on a monotonic clock, what LinkUpdate wants.
LinkNow :: proc() -> i64 {
    return i64(time.duration_milliseconds(time.tick_since(LINK_EPOCH)))
}

@(private)
LINK_EPOCH: time.Tick = time.tick_now()

// ============================================================ setup

// Opens the socket (non blocking). Returns false when the port cannot be bound.
LinkInit :: proc(link: ^Link, config: LinkConfig = {}) -> bool {
    link^ = {config = config}
    socket, make_error := net.make_unbound_udp_socket(.IP4)
    if make_error != nil {
        return false
    }
    if net.bind(socket, {address = net.IP4_Any, port = int(config.port)}) != nil {
        net.close(socket)
        return false
    }
    if net.set_blocking(socket, false) != nil {
        net.close(socket)
        return false
    }
    bound, bound_error := net.bound_endpoint(socket)
    if bound_error != nil {
        net.close(socket)
        return false
    }
    link.socket = socket
    link.open = true
    link.local_port = bound.port
    LinkOpenV6(link)
    for link.id == 0 {
        crypto.rand_bytes((cast([^]byte)&link.id)[:size_of(link.id)])
    }
    return true
}

// A link over your own transport instead of a socket. `local_port` is the port the transport delivers for.
LinkInitTransport :: proc(link: ^Link, transport: Transport, local_port: int, config: LinkConfig = {}) -> bool {
    assert(transport.send != nil && transport.receive != nil)
    link^ = {config = config, transport = transport, open = true, local_port = local_port, local_port6 = local_port, has_v6 = config.local_v6_set}
    for link.id == 0 {
        crypto.rand_bytes((cast([^]byte)&link.id)[:size_of(link.id)])
    }
    return true
}

// The IPv6 socket is optional: on the same port as the IPv4 one when it can (one port to forward, one number in the logs),
// else on a port of its own (a dual stack system lets the IPv6 socket take the IPv4 port too).
@(private)
LinkOpenV6 :: proc(link: ^Link) {
    if link.config.no_ipv6 {
        return
    }
    socket, make_error := net.make_unbound_udp_socket(.IP6)
    if make_error != nil {
        return
    }
    if net.bind(socket, {address = net.IP6_Any, port = link.local_port}) != nil && net.bind(socket, {address = net.IP6_Any, port = 0}) != nil {
        net.close(socket)
        return
    }
    bound, bound_error := net.bound_endpoint(socket)
    if bound_error != nil || net.set_blocking(socket, false) != nil {
        net.close(socket)
        return
    }
    link.socket6 = socket
    link.has_v6 = true
    link.local_port6 = bound.port
}

LinkClose :: proc(link: ^Link) {
    LinkDerpClose(link)
    if !link.open {
        return
    }
    for &peer in link.peers {
        if peer.state == .CONNECTED {
            LinkSendPacket(link, &peer, peer.endpoint, .CLOSE, nil, nil, peer.via_relay)
        }
    }
    if link.transport.send == nil {
        net.close(link.socket)
        if link.has_v6 {
            net.close(link.socket6)
        }
    }
    if link.portmap != nil && link.portmap.protocol != .NONE {
        PortMapClose(link.portmap)
    }
    link.open = false
}

@(private)
LinkSendRaw :: proc(link: ^Link, to: net.Endpoint, data: []byte) {
    if slot, is_derp := DerpEndpointSlot(to); is_derp {
        LinkDerpSend(link, slot, data)
        return
    }
    if link.transport.send != nil {
        link.transport.send(link.transport.user, to, data)
        return
    }
    if _, is_v6 := to.address.(net.IP6_Address); is_v6 {
        if link.has_v6 {
            net.send_udp(link.socket6, data, to)
        }
        return
    }
    net.send_udp(link.socket, data, to)
}

// 0 = nothing waiting, otherwise the length; a receive error that is not "would block" reads as an empty datagram of length -1
// so the caller keeps reading (Windows reports an ICMP port unreachable from an earlier send as a receive error).
@(private)
LinkReadRaw :: proc(link: ^Link) -> (length: int, from: net.Endpoint) {
    if link.transport.receive != nil {
        ok: bool
        length, from, ok = link.transport.receive(link.transport.user, link.datagram[:])
        return length if ok else 0, from
    }
    error: net.UDP_Recv_Error
    length, from, error = net.recv_udp(link.socket, link.datagram[:])
    if error == .Would_Block {
        if !link.has_v6 {
            return 0, from
        }
        length, from, error = net.recv_udp(link.socket6, link.datagram[:])
        if error == .Would_Block {
            return 0, from
        }
    }
    if error != nil {
        return -1, from
    }
    return length, from
}

// Resolves the STUN host names (a blocking DNS lookup, so do it at start, not per frame). Returns how many resolved.
LinkResolveStun :: proc(servers: []net.Endpoint) -> int {
    count: int
    for host in STUN_SERVERS {
        if count >= len(servers) {
            break
        }
        endpoint, error := net.resolve_ip4(host)
        if error == nil {
            servers[count] = endpoint
            count += 1
        }
    }
    return count
}

// Adds an address this link can be reached at. Gathering calls it for what it finds; call it yourself to add one by hand
// (a forwarded port, a test). Duplicates are ignored.
LinkAddCandidate :: proc(link: ^Link, endpoint: net.Endpoint) -> bool {
    if _, is_v6 := endpoint.address.(net.IP6_Address); is_v6 {
        // codes stay short: one IPv6 address is enough, it is global (no NAT) so any one reaches
        for i in 0 ..< link.candidate_count {
            if _, other_v6 := link.candidates[i].address.(net.IP6_Address); other_v6 {
                return false
            }
        }
    }
    for i in 0 ..< link.candidate_count {
        if link.candidates[i] == endpoint {
            return false
        }
    }
    if link.candidate_count >= MAX_CANDIDATES {
        return false
    }
    link.candidates[link.candidate_count] = endpoint
    link.candidate_count += 1
    return true
}

// Starts finding the addresses: the public one from every STUN server (all asked from the game socket) and the local network
// ones. With no servers only the local ones are found, which is enough on one LAN. LinkUpdate finishes it (GATHERED event).
// The interface list is read through the temp allocator once, here.
LinkGatherBegin :: proc(link: ^Link, servers: []net.Endpoint, now_ms: i64) {
    assert(link.open)
    link.candidate_count = 0
    link.stun_count = min(len(servers), STUN_MAX_SERVERS)
    for i in 0 ..< link.stun_count {
        link.stun_servers[i] = servers[i]
        link.stun_answered[i] = false
        link.stun_has_other[i] = false
        crypto.rand_bytes(link.stun_txid[i][:])
    }
    link.nat_mapping = .UNKNOWN
    link.nat_filtering = .UNKNOWN
    link.filter_state = .IDLE
    link.gather = .RUNNING
    link.gather_start_ms = now_ms
    link.gather_sent_ms = now_ms - GATHER_RETRY_MS
    LinkGatherLocal(link)
    LinkGatherSend(link, now_ms)
    if link.stun_count == 0 {
        LinkGatherFinish(link, now_ms)
    }
}

LinkGathered :: proc(link: ^Link) -> bool {
    return link.gather == .DONE && link.turn.phase != .ALLOCATING && !(link.derp.state == .CONNECTING && !link.derp.reconnecting)
}

// Asks the router to forward this link's UDP port (PCP, NAT-PMP or UPnP, see portmap.odin). Call it after the gathering and
// BEFORE the code is made. It BLOCKS for up to a few seconds. On success the public address of the mapping is the first
// candidate and the code says the NAT is open, so the peer does not have to punch (nor guess ports); the filtering test runs
// again, from a STUN server that answers from another address: if that answer arrives, strangers really can reach the
// mapping (`nat_filtering == .OPEN` after NAT_MEASURED), which is the proof from the outside. `state` is yours (about 16 KB)
// and must stay alive until LinkClose, which removes the mapping.
LinkPortMap :: proc(link: ^Link, state: ^PortMapState, now_ms: i64, timeout_ms: i64 = 1500) -> bool {
    assert(link.open && link.gather == .DONE && link.transport.send == nil)
    if !PortMapOpen(state, link.local_port, timeout_ms) {
        return false
    }
    link.portmap = state
    LinkAddCandidateFirst(link, state.external)
    link.nat_mapping = .INDEPENDENT
    link.nat_filtering = .OPEN
    link.nat_port_delta = 0
    link.nat_last_port = 0
    LinkFilterBegin(link, now_ms)
    return true
}

@(private)
LinkGatherLocal :: proc(link: ^Link) {
    if link.config.local_address_count > 0 {
        for i in 0 ..< link.config.local_address_count {
            LinkAddCandidate(link, {address = link.config.local_addresses[i], port = link.local_port})
        }
        if link.config.local_v6_set {
            LinkAddCandidate(link, {address = link.config.local_v6, port = link.local_port6})
        }
        return
    }
    defer free_all(context.temp_allocator)
    interfaces, error := net.enumerate_interfaces(context.temp_allocator)
    if error == nil {
        for interface in interfaces {
            if .Up not_in interface.link.state {
                continue
            }
            for lease in interface.unicast {
                if address6, is_v6 := lease.address.(net.IP6_Address); is_v6 {
                    if link.has_v6 && IsPublicAddress(address6) {
                        LinkAddCandidate(link, {address = address6, port = link.local_port6})
                    }
                    continue
                }
                address, is_ip4 := lease.address.(net.IP4_Address)
                // 169.254 is the "no network configured" address, nobody can reach it
                if !is_ip4 || address[0] == 127 || address[0] == 169 && address[1] == 254 {
                    continue
                }
                LinkAddCandidate(link, {address = address, port = link.local_port})
            }
        }
    }
    if link.config.include_loopback {
        LinkAddCandidate(link, {address = net.IP4_Loopback, port = link.local_port})
        if link.has_v6 {
            LinkAddCandidate(link, {address = net.IP6_Loopback, port = link.local_port6})
        }
    }
}

@(private)
LinkGatherSend :: proc(link: ^Link, now_ms: i64) {
    request: [STUN_HEADER_SIZE + 8]byte
    for i in 0 ..< link.stun_count {
        if !link.stun_answered[i] {
            length: int = StunBuildRequest(request[:], link.stun_txid[i])
            LinkSendRaw(link, link.stun_servers[i], request[:length])
        }
    }
    link.gather_sent_ms = now_ms
}

// An answer from a STUN server: to the gathering, or to the filtering test.
@(private)
LinkStunAnswer :: proc(link: ^Link, from: net.Endpoint, data: []byte, now_ms: i64) {
    if link.filter_state == .BOTH || link.filter_state == .PORT_ONLY {
        if _, ok := StunParseResult(data, link.filter_txid); ok {
            // an answer that came from another address than the one we asked got through the NAT: it let a stranger in
            if from != link.stun_servers[link.filter_server] {
                link.nat_filtering = .OPEN if link.filter_state == .BOTH else .ADDRESS
                LinkFilterFinish(link)
            }
            return
        }
    }
    for i in 0 ..< link.stun_count {
        if from != link.stun_servers[i] || link.stun_answered[i] {
            continue
        }
        result, ok := StunParseResult(data, link.stun_txid[i])
        if !ok {
            return
        }
        link.stun_answered[i] = true
        link.stun_mapped[i] = result.mapped
        link.stun_has_other[i] = result.has_other
        link.stun_other[i] = result.other
        LinkAddCandidateFirst(link, result.mapped)
        answered: int
        for k in 0 ..< link.stun_count {
            answered += int(link.stun_answered[k])
        }
        if answered == link.stun_count {
            LinkGatherFinish(link, now_ms)
        }
        return
    }
}

// The public address goes first: it is the one that works from another network. A full list drops its last entry.
@(private)
LinkAddCandidateFirst :: proc(link: ^Link, endpoint: net.Endpoint) {
    end: int = link.candidate_count
    for i in 0 ..< link.candidate_count {
        if link.candidates[i] == endpoint {
            end = i
            break
        }
    }
    if end == link.candidate_count {
        if link.candidate_count < MAX_CANDIDATES {
            link.candidate_count += 1
        } else {
            end = MAX_CANDIDATES - 1
        }
    }
    for j := end; j > 0; j -= 1 {
        link.candidates[j] = link.candidates[j - 1]
    }
    link.candidates[0] = endpoint
}

// A routable address: not private, not loopback, not link local, not 0.0.0.0. A STUN server that announces anything else as
// its second address is misconfigured and its CHANGE-REQUEST answers can never arrive.
IsPublicAddress :: proc(address: net.Address) -> bool {
    if address6, is_v6 := address.(net.IP6_Address); is_v6 {
        // global unicast, 2000::/3
        return u16(address6[0]) & 0xE000 == 0x2000
    }
    ip, is_ip4 := address.(net.IP4_Address)
    if !is_ip4 {
        return false
    }
    switch {
    case ip[0] == 0, ip[0] == 10, ip[0] == 127, ip[0] >= 224:
        return false
    case ip[0] == 172 && ip[1] >= 16 && ip[1] <= 31, ip[0] == 192 && ip[1] == 168, ip[0] == 169 && ip[1] == 254:
        return false
    case ip[0] == 100 && ip[1] >= 64 && ip[1] <= 127:     // carrier grade NAT range
        return false
    }
    return true
}

@(private)
LinkGatherFinish :: proc(link: ^Link, now_ms: i64) {
    if link.gather == .DONE {
        return
    }
    link.gather = .DONE
    LinkMeasureMapping(link)
    LinkPushEvent(link, {kind = .GATHERED})
    LinkFilterBegin(link, now_ms)
}

// Mapping behavior from the servers that agree on our public address (one that saw another address, a misconfigured server
// behind a NAT of its own, tells nothing about ours). Same port everywhere = independent. Different ports = dependent, and if
// the step between them is constant the next port can be predicted, which is what the peer uses to guess it.
@(private)
LinkMeasureMapping :: proc(link: ^Link) {
    link.nat_mapping = .UNKNOWN
    link.nat_port_delta = 0
    link.nat_last_port = 0
    // the address most servers saw
    majority: net.Address
    best: int
    for i in 0 ..< link.stun_count {
        count: int
        for j in 0 ..< link.stun_count {
            count += int(link.stun_answered[i] && link.stun_answered[j] && link.stun_mapped[i].address == link.stun_mapped[j].address)
        }
        if count > best {
            best = count
            majority = link.stun_mapped[i].address
        }
    }
    ports: [STUN_MAX_SERVERS]int
    count: int
    for i in 0 ..< link.stun_count {
        if link.stun_answered[i] && link.stun_mapped[i].address == majority {
            ports[count] = link.stun_mapped[i].port
            count += 1
        }
    }
    if count < 2 {
        return
    }
    link.nat_last_port = ports[count - 1]
    link.nat_mapping = .INDEPENDENT
    delta: int = ports[1] - ports[0]
    constant: bool = true
    for i in 1 ..< count {
        if ports[i] != ports[0] {
            link.nat_mapping = .DEPENDENT
        }
        constant &&= ports[i] - ports[i - 1] == delta
    }
    if link.nat_mapping == .DEPENDENT {
        // the requests left in server order, so the ports are in allocation order
        link.nat_port_delta = delta if constant && delta != 0 && abs(delta) <= SPRAY_PORTS else 0
        LinkKeepOnePublicCandidate(link, majority)
    }
}

// With a symmetric NAT every server saw another port: only the last one is next to the port the peer will get, the others
// would just waste candidate slots and punch packets.
@(private)
LinkKeepOnePublicCandidate :: proc(link: ^Link, address: net.Address) {
    kept: int
    for i in 0 ..< link.candidate_count {
        endpoint: net.Endpoint = link.candidates[i]
        is_stun_port: bool
        for k in 0 ..< link.stun_count {
            is_stun_port ||= link.stun_answered[k] && link.stun_mapped[k] == endpoint
        }
        if is_stun_port && endpoint != (net.Endpoint{address = address, port = link.nat_last_port}) {
            continue
        }
        link.candidates[kept] = endpoint
        kept += 1
    }
    link.candidate_count = kept
}

// The filtering test needs a server with a second public address (RFC 5780). It asks for an answer from another IP and port,
// then from another port: what gets through says how open the NAT is.
@(private)
LinkFilterBegin :: proc(link: ^Link, now_ms: i64) {
    link.filter_state = .DONE
    for i in 0 ..< link.stun_count {
        if link.stun_answered[i] && link.stun_has_other[i] && IsPublicAddress(link.stun_other[i].address) {
            link.filter_server = i
            link.filter_state = .BOTH
            link.filter_phase_ms = now_ms
            link.filter_sent_ms = now_ms - FILTER_STEP_MS
            crypto.rand_bytes(link.filter_txid[:])
            return
        }
    }
}

@(private)
LinkFilterFinish :: proc(link: ^Link) {
    link.filter_state = .DONE
    LinkPushEvent(link, {kind = .NAT_MEASURED})
}

@(private)
LinkFilterUpdate :: proc(link: ^Link, now_ms: i64) {
    if link.filter_state != .BOTH && link.filter_state != .PORT_ONLY {
        return
    }
    if now_ms - link.filter_phase_ms >= FILTER_PHASE_MS {
        if link.filter_state == .BOTH {
            link.filter_state = .PORT_ONLY
            link.filter_phase_ms = now_ms
            link.filter_sent_ms = now_ms - FILTER_STEP_MS
            crypto.rand_bytes(link.filter_txid[:])
        } else {
            // nothing came from another address or port: only the exact address we sent to may answer
            link.nat_filtering = .PORT
            LinkFilterFinish(link)
        }
        return
    }
    if now_ms - link.filter_sent_ms >= FILTER_STEP_MS {
        link.filter_sent_ms = now_ms
        request: [STUN_HEADER_SIZE + 8]byte
        change: u32 = STUN_CHANGE_IP | STUN_CHANGE_PORT if link.filter_state == .BOTH else STUN_CHANGE_PORT
        length: int = StunBuildRequest(request[:], link.filter_txid, change)
        LinkSendRaw(link, link.stun_servers[link.filter_server], request[:length])
    }
}

// ============================================================ session

// This link makes the session: a random id that every packet carries, and the invites it hands out.
LinkHost :: proc(link: ^Link, name: string) {
    assert(link.open && link.role == .NONE)
    link.role = .HOST
    crypto.rand_bytes(link.secret[:])
    crypto.rand_bytes((cast([^]byte)&link.session)[:size_of(link.session)])
    link.tag = SessionTag(link.session)
    link.name_len = min(len(name), NAME_MAX)
    copy(link.name[:link.name_len], name)
}

// Joins the session of a pasted INVITE and starts punching towards the host (peer 0) at once: the host's NAT opens when the
// host answers to the reply, and both sides keep sending until one packet gets through.
LinkJoin :: proc(link: ^Link, invite: Invite, name: string, now_ms: i64) -> bool {
    assert(link.open && link.role == .NONE)
    if invite.kind != .INVITE {
        return false
    }
    link.role = .GUEST
    link.secret = invite.secret
    link.session = invite.session
    link.tag = SessionTag(link.session)
    link.name_len = min(len(name), NAME_MAX)
    copy(link.name[:link.name_len], name)
    PeerStart(link, 0, invite, now_ms)
    return true
}

// The host adds the guest of a pasted REPLY. Returns its peer index. The same reply pasted twice gives the same peer.
LinkAcceptReply :: proc(link: ^Link, reply: Invite, now_ms: i64) -> (peer: int, ok: bool) {
    if link.role != .HOST || reply.kind != .REPLY || reply.session != link.session {
        return
    }
    free_slot: int = -1
    for i in 0 ..< MAX_PEERS {
        if link.peers[i].state != .EMPTY && link.peers[i].id == reply.id {
            return i, true
        }
        if free_slot < 0 && (link.peers[i].state == .EMPTY || link.peers[i].state == .FAILED || link.peers[i].state == .LOST) {
            free_slot = i
        }
    }
    if free_slot < 0 {
        return
    }
    link.peers[free_slot] = {}
    PeerStart(link, free_slot, reply, now_ms)
    return free_slot, true
}

// The code of this link: an INVITE for the host, a REPLY for a guest. Call it after the gathering is done.
LinkMakeInvite :: proc(link: ^Link, short: bool = false) -> (invite: Invite) {
    assert(link.role != .NONE)
    assert(!short || link.derp.state == .READY)
    invite.kind = .INVITE if link.role == .HOST else .REPLY
    invite.session = link.session
    invite.id = link.id
    if link.role == .HOST {
        invite.secret = link.secret
    }
    invite.name = link.name
    invite.name_len = link.name_len
    invite.nat_mapping = link.nat_mapping
    invite.nat_filtering = link.nat_filtering
    invite.port_delta = link.nat_port_delta
    invite.last_port = link.nat_last_port
    if link.derp.state == .READY {
        invite.derp_server = u8(link.derp.server)
        invite.derp_key = link.derp.public
        if link.derp.server == DERP_CUSTOM {
            invite.derp_host_length = link.derp.host_length
            copy(invite.derp_host[:], link.derp.host[:link.derp.host_length])
        }
    }
    for i in 0 ..< link.candidate_count {
        if short || link.config.derp_only && link.derp.state == .READY {
            break
        }
        if link.config.relay_only && link.turn.phase == .READY && link.candidates[i] != link.turn.relayed {
            continue
        }
        InviteAddCandidate(&invite, link.candidates[i])
    }
    return
}

@(private)
SessionTag :: proc(session: u64) -> u32 {
    return u32(session) ~ u32(session >> 32)
}

@(private)
PeerStart :: proc(link: ^Link, slot: int, invite: Invite, now_ms: i64) {
    peer: ^Peer = &link.peers[slot]
    peer^ = {state = .PUNCHING, id = invite.id, name = invite.name, name_len = invite.name_len}
    peer.candidates = invite.candidates
    peer.candidate_count = invite.candidate_count
    peer.nat_mapping = invite.nat_mapping
    peer.nat_filtering = invite.nat_filtering
    peer.port_delta = invite.port_delta
    peer.last_port = invite.last_port
    peer.punch_start_ms = now_ms
    peer.punch_last_ms = now_ms - PUNCH_INTERVAL_MS
    PeerKeyMake(link, peer)
    // the same relay on both sides: its key is one more candidate, and the way to signal
    if link.derp.state == .READY && DerpSameRelay(&link.derp, invite) {
        peer.has_derp = true
        peer.derp_key = invite.derp_key
        PeerAddDerpCandidate(peer, slot)
    }
}

LinkPeerName :: proc(link: ^Link, peer: int) -> string {
    return string(link.peers[peer].name[:link.peers[peer].name_len])
}

// Messages sent to the peer and not yet acknowledged. Zero means everything arrived: safe moment to close the link.
LinkPending :: proc(link: ^Link, peer: int) -> int {
    assert(peer >= 0 && peer < MAX_PEERS)
    return link.peers[peer].send_count
}

// Starts the 20 s countdown of peers that are still being reached over from `now_ms`. For when the invite was handled early but the
// path only opens later (a tunnel that needs the person to click "allow" first).
LinkRestartPunch :: proc(link: ^Link, now_ms: i64) {
    for &peer in link.peers {
        if peer.state == .PUNCHING {
            peer.punch_start_ms = now_ms
            peer.punch_last_ms = now_ms - PUNCH_INTERVAL_MS
        }
    }
}

LinkPeerCount :: proc(link: ^Link) -> (count: int) {
    for peer in link.peers {
        if peer.state == .CONNECTED {
            count += 1
        }
    }
    return
}

// ============================================================ events and messages

@(private)
LinkPushEvent :: proc(link: ^Link, event: LinkEvent) {
    if link.event_count >= EVENTS {
        return
    }
    link.events[(link.event_head + link.event_count) % EVENTS] = event
    link.event_count += 1
}

LinkPollEvent :: proc(link: ^Link) -> (event: LinkEvent, ok: bool) {
    if link.event_count == 0 {
        return
    }
    event = link.events[link.event_head]
    link.event_head = (link.event_head + 1) % EVENTS
    link.event_count -= 1
    return event, true
}

// Copies the oldest received message into `buffer` (MAX_PAYLOAD is always enough). `ok` is false when there is none.
LinkReceive :: proc(link: ^Link, buffer: []byte) -> (peer: int, length: int, ok: bool) {
    if link.inbox_count == 0 {
        return
    }
    message: ^Message = &link.inbox[link.inbox_head]
    length = int(message.length)
    assert(len(buffer) >= length)
    copy(buffer[:length], message.data[:length])
    peer = int(message.peer)
    link.inbox_head = (link.inbox_head + 1) % INBOX
    link.inbox_count -= 1
    return peer, length, true
}

// Queues a message for a connected peer. Reliable ones arrive once, in order, even over a lossy link; false means the
// window is full (the peer is too slow or gone), try again later. Unreliable ones are sent once and may never arrive.
LinkSend :: proc(link: ^Link, peer_index: int, data: []byte, reliable: bool, now_ms: i64) -> bool {
    if peer_index < 0 || peer_index >= MAX_PEERS || len(data) > MAX_PAYLOAD {
        return false
    }
    peer: ^Peer = &link.peers[peer_index]
    if peer.state != .CONNECTED {
        return false
    }
    peer.tx_ms = now_ms
    if !reliable {
        LinkSendPacket(link, peer, peer.endpoint, .DATA, data, nil, peer.via_relay)
        peer.tx_packets += 1
        return true
    }
    if peer.send_count >= WINDOW {
        return false
    }
    slot: int = int(peer.send_next) % WINDOW
    peer.send_length[slot] = u16(len(data))
    copy(peer.send_data[slot][:len(data)], data)
    peer.send_acked[slot] = false
    peer.send_last_ms[slot] = now_ms
    peer.send_attempts[slot] = 0
    if peer.send_count == 0 {
        peer.send_progress_ms = now_ms
    }
    LinkSendReliable(link, peer, peer.send_next, slot)
    peer.send_next += 1
    peer.send_count += 1
    return true
}

// Sends the message to every connected peer (a host relaying chat). Returns how many accepted it.
LinkBroadcast :: proc(link: ^Link, data: []byte, reliable: bool, now_ms: i64, except: int = -1) -> (count: int) {
    for i in 0 ..< MAX_PEERS {
        if i != except && LinkSend(link, i, data, reliable, now_ms) {
            count += 1
        }
    }
    return
}

LinkDisconnect :: proc(link: ^Link, peer_index: int) {
    peer: ^Peer = &link.peers[peer_index]
    if peer.state == .CONNECTED {
        LinkSendPacket(link, peer, peer.endpoint, .CLOSE, nil, nil, peer.via_relay)
    }
    peer.state = .EMPTY
}

// ============================================================ packets

// The key of one pair of peers: it depends on the session secret and on both ids, so every pair (and the reply code of a guest, which
// has no secret of its own) gets a different key and the nonce counters of two senders never meet.
@(private)
PeerKeyMake :: proc(link: ^Link, peer: ^Peer) {
    low: u32 = min(link.id, peer.id)
    high: u32 = max(link.id, peer.id)
    context_256: sha2.Context_256
    sha2.init_256(&context_256)
    sha2.update(&context_256, transmute([]byte)string("p2p-link-v1:"))
    sha2.update(&context_256, link.secret[:])
    ids: [8]byte
    PutU32BE(ids[0:], low)
    PutU32BE(ids[4:], high)
    sha2.update(&context_256, ids[:])
    sha2.final(&context_256, peer.key[:])
    crypto.rand_bytes((cast([^]byte)&peer.send_counter)[:size_of(peer.send_counter)])
    peer.send_counter &= 0x7FFF_FFFF_FFFF_FFFF
}

// counter (8 bytes) and direction: the two ends of a pair never use the same nonce
@(private)
PacketNonce :: proc(counter: u64, from_higher_id: bool) -> (nonce: [BOX_NONCE_SIZE]byte) {
    PutU32BE(nonce[0:], u32(counter >> 32))
    PutU32BE(nonce[4:], u32(counter))
    nonce[8] = 1 if from_higher_id else 0
    return
}

// Opens a received datagram: returns the length of [kind][body] written into `plain`, 0 when it is not from this peer's key, is
// damaged, or was seen before.
@(private)
PeerOpen :: proc(link: ^Link, peer: ^Peer, data: []byte, plain: []byte) -> int {
    if len(data) < PACKET_HEADER + PACKET_CRYPTO || len(data) - PACKET_HEADER - 8 - BOX_AUTH_SIZE > len(plain) {
        return 0
    }
    counter: u64 = u64(GetU32BE(data[PACKET_HEADER:])) << 32 | u64(GetU32BE(data[PACKET_HEADER + 4:]))
    if peer.recv_any && counter <= peer.recv_top && (peer.recv_top - counter >= 64 || peer.recv_seen >> (peer.recv_top - counter) & 1 != 0) {
        return 0                          // too old, or already seen
    }
    sealed: []byte = data[PACKET_HEADER + 8:]
    if !BoxOpen(plain, sealed, PacketNonce(counter, peer.id > link.id), peer.key) {
        return 0
    }
    if !peer.recv_any {
        peer.recv_any = true
        peer.recv_top = counter
        peer.recv_seen = 1
    } else if counter > peer.recv_top {
        shift: u64 = counter - peer.recv_top
        peer.recv_seen = 0 if shift >= 64 else peer.recv_seen << shift
        peer.recv_seen |= 1
        peer.recv_top = counter
    } else {
        peer.recv_seen |= 1 << (peer.recv_top - counter)
    }
    return len(sealed) - BOX_AUTH_SIZE
}

@(private)
LinkSendPacket :: proc(link: ^Link, peer: ^Peer, to: net.Endpoint, kind: PacketKind, payload: []byte, extra: []byte = nil, relay: bool = false) {
    buffer: [PACKET_HEADER + PACKET_CRYPTO + 8 + MAX_PAYLOAD]byte
    length: int = PeerSeal(link, peer, kind, payload, extra, buffer[:])
    if relay {
        LinkSendRelayed(link, to, buffer[:length])
        return
    }
    LinkSendRaw(link, to, buffer[:length])
}

// The datagram for `peer`: header, counter, [kind][extra][payload] sealed. Returns its length.
@(private)
PeerSeal :: proc(link: ^Link, peer: ^Peer, kind: PacketKind, payload: []byte, extra: []byte, buffer: []byte) -> int {
    buffer[0] = PACKET_MAGIC
    buffer[1] = u8(kind)
    PutU32BE(buffer[2:], link.tag)
    PutU32BE(buffer[6:], link.id)
    // the kind is inside the seal too: the header is not covered by the authenticator, so a changed header kind must not pass
    plain: [1 + 8 + MAX_PAYLOAD]byte
    plain[0] = u8(kind)
    plain_length: int = 1
    copy(plain[plain_length:], extra)
    plain_length += len(extra)
    copy(plain[plain_length:], payload)
    plain_length += len(payload)
    counter: u64 = peer.send_counter
    peer.send_counter += 1
    PutU32BE(buffer[PACKET_HEADER:], u32(counter >> 32))
    PutU32BE(buffer[PACKET_HEADER + 4:], u32(counter))
    BoxSeal(buffer[PACKET_HEADER + 8:], plain[:plain_length], PacketNonce(counter, link.id > peer.id), peer.key)
    return PACKET_HEADER + 8 + plain_length + BOX_AUTH_SIZE
}

// Every reliable message and every ACK carries the acknowledgement: the next sequence expected (everything before it arrived)
// and a bit mask of the ones that arrived ahead of it, so the sender resends only the holes.
@(private)
PeerAckMask :: proc(peer: ^Peer) -> (mask: u16) {
    for k in 1 ..< WINDOW {
        if peer.recv_have[int(peer.recv_next + u16(k)) % WINDOW] {
            mask |= 1 << u32(k - 1)
        }
    }
    return
}

@(private)
LinkSendReliable :: proc(link: ^Link, peer: ^Peer, sequence: u16, slot: int) {
    extra: [6]byte
    PutU16BE(extra[0:], sequence)
    PutU16BE(extra[2:], peer.recv_next)
    PutU16BE(extra[4:], PeerAckMask(peer))
    LinkSendPacket(link, peer, peer.endpoint, .DATA_RELIABLE, peer.send_data[slot][:peer.send_length[slot]], extra[:], peer.via_relay)
    peer.tx_packets += 1
    peer.ack_due = false
}

@(private)
LinkSendAck :: proc(link: ^Link, peer: ^Peer, now_ms: i64) {
    extra: [4]byte
    PutU16BE(extra[0:], peer.recv_next)
    PutU16BE(extra[2:], PeerAckMask(peer))
    LinkSendPacket(link, peer, peer.endpoint, .ACK, nil, extra[:], peer.via_relay)
    peer.ack_due = false
    peer.tx_ms = now_ms
}

@(private)
LinkHandleDatagram :: proc(link: ^Link, from: net.Endpoint, data: []byte, now_ms: i64, relay: bool = false) {
    if len(data) < PACKET_HEADER || data[0] != PACKET_MAGIC || GetU32BE(data[2:]) != link.tag || link.role == .NONE {
        return
    }
    kind: PacketKind = PacketKind(data[1])
    sender: u32 = GetU32BE(data[6:])

    // The peer is found by the id in the packet, not by the address it came from: a computer with several network cards
    // answers from whichever address its routing picks, and a NAT can change the public port in the middle of a session.
    peer_index: int = -1
    for i in 0 ..< MAX_PEERS {
        if link.peers[i].state != .EMPTY && link.peers[i].id == sender {
            peer_index = i
            break
        }
    }
    if peer_index < 0 {
        return
    }
    peer: ^Peer = &link.peers[peer_index]

    plain: [1 + 8 + MAX_PAYLOAD]byte
    plain_length: int = PeerOpen(link, peer, data, plain[:])
    if plain_length < 1 || plain[0] != u8(kind) {
        peer.rejected += 1
        return
    }
    body: []byte = plain[1:plain_length]

    if kind == .PUNCH || kind == .PUNCH_ACK {
        if peer.state == .PUNCHING {
            // from now on the peer is whatever address this packet came from: that is the hole the NAT opened
            peer.state = .CONNECTED
            peer.endpoint = from
            peer.via_relay = relay
            peer.rx_ms = now_ms
            peer.tx_ms = now_ms
            LinkPushEvent(link, {kind = .PEER_CONNECTED, peer = peer_index})
        }
        if kind == .PUNCH {
            // always answer, the peer may still be punching because our earlier answer was lost
            LinkSendPacket(link, peer, from, .PUNCH_ACK, nil, nil, relay)
        } else if peer.state == .CONNECTED && peer.via_relay && !relay {
            // our direct punch was answered: the direct path works both ways, leave the relay
            peer.endpoint = from
            peer.via_relay = false
        }
        if peer.state == .CONNECTED {
            peer.rx_ms = now_ms
        }
        return
    }

    if peer.state != .CONNECTED {
        return
    }
    // The relay is a way in, not a home: when a packet comes straight, the connection moves to the direct path. A packet
    // through the relay while a direct path is in use is still taken, but does not move anything back.
    if relay == peer.via_relay || !relay && peer.via_relay {
        peer.endpoint = from
        peer.via_relay = relay
    }
    peer.rx_ms = now_ms
    peer.rx_packets += 1

    #partial switch kind {
    case .DATA:
        LinkInboxPush(link, peer_index, body)
    case .DATA_RELIABLE:
        if len(body) < 6 {
            return
        }
        LinkHandleAck(peer, GetU16BE(body[2:]), GetU16BE(body[4:]), now_ms)
        LinkReceiveReliable(link, peer_index, peer, GetU16BE(body[0:]), body[6:])
    case .ACK:
        if len(body) >= 4 {
            LinkHandleAck(peer, GetU16BE(body[0:]), GetU16BE(body[2:]), now_ms)
        }
    case .CLOSE:
        peer.state = .LOST
        LinkPushEvent(link, {kind = .PEER_LOST, peer = peer_index})
    }
}

@(private)
LinkInboxPush :: proc(link: ^Link, peer_index: int, data: []byte) {
    if link.inbox_count >= INBOX || len(data) > MAX_PAYLOAD {
        return
    }
    message: ^Message = &link.inbox[(link.inbox_head + link.inbox_count) % INBOX]
    message.peer = u8(peer_index)
    message.length = u16(len(data))
    copy(message.data[:len(data)], data)
    link.inbox_count += 1
}

// A reliable message: kept until its turn, then delivered in order. Anything outside the window is a duplicate of something
// delivered long ago (or garbage) and only gets the acknowledgement again, which tells the sender where we are.
@(private)
LinkReceiveReliable :: proc(link: ^Link, peer_index: int, peer: ^Peer, sequence: u16, message: []byte) {
    peer.ack_due = true
    if int(sequence - peer.recv_next) >= WINDOW || len(message) > MAX_PAYLOAD {
        return
    }
    slot: int = int(sequence) % WINDOW
    if !peer.recv_have[slot] {
        peer.recv_have[slot] = true
        peer.recv_length[slot] = u16(len(message))
        copy(peer.recv_data[slot][:len(message)], message)
    }
    // a full inbox leaves the rest buffered (and acknowledged), it is delivered when the program reads
    for {
        next: int = int(peer.recv_next) % WINDOW
        if !peer.recv_have[next] || link.inbox_count >= INBOX {
            break
        }
        LinkInboxPush(link, peer_index, peer.recv_data[next][:peer.recv_length[next]])
        peer.recv_have[next] = false
        peer.recv_next += 1
    }
}

// `ack` is the next sequence the peer expects (everything before it arrived), bit k of `mask` says that sequence ack + 1 + k
// arrived too. Round trips are sampled only from messages that were never resent, otherwise it is unknown which copy answered.
@(private)
LinkHandleAck :: proc(peer: ^Peer, ack: u16, mask: u16, now_ms: i64) {
    advance: int = int(ack - peer.send_base)        // u16 wrap around
    if advance > peer.send_count {
        return
    }
    progress: bool
    sample :: proc(peer: ^Peer, slot: int, now_ms: i64) {
        if peer.send_attempts[slot] == 0 {
            round_trip: f32 = f32(now_ms - peer.send_last_ms[slot])
            peer.rtt_ms = round_trip if peer.rtt_ms == 0 else peer.rtt_ms * 0.875 + round_trip * 0.125
        }
    }
    if advance > 0 {
        last: int = int(ack - 1) % WINDOW
        if !peer.send_acked[last] {
            sample(peer, last, now_ms)
        }
        peer.send_base = ack
        peer.send_count -= advance
        progress = true
    }
    for k in 0 ..< WINDOW - 1 {
        if mask & (1 << u32(k)) == 0 {
            continue
        }
        offset: int = int(u16(ack + 1 + u16(k)) - peer.send_base)
        slot: int = int(peer.send_base + u16(offset)) % WINDOW
        if offset < peer.send_count && !peer.send_acked[slot] {
            sample(peer, slot, now_ms)
            peer.send_acked[slot] = true
            progress = true
        }
    }
    if progress {
        peer.send_progress_ms = now_ms
    }
}

// How long to wait for an acknowledgement of a message sent `attempts` times: twice the round trip, doubling per resend.
@(private)
PeerResendMs :: proc(peer: ^Peer, attempts: u8) -> i64 {
    base: i64 = RESEND_FIRST_MS
    if peer.rtt_ms > 0 {
        base = clamp(i64(peer.rtt_ms * 2) + 20, RESEND_MIN_MS, RESEND_MAX_MS)
    }
    return min(base << u32(min(attempts, 4)), RESEND_MAX_MS)
}

// ============================================================ update

// The test hook of drop_percent: true when this received datagram is to be thrown away.
@(private)
LinkDropped :: proc(link: ^Link) -> bool {
    if link.drop_percent <= 0 {
        return false
    }
    link.drop_state = link.drop_state * 1664525 + 1013904223
    return int(link.drop_state >> 16) % 100 < link.drop_percent
}

// Call every frame (or at least every 50 ms): reads the socket, finishes the gathering, punches, resends, keeps alive.
LinkUpdate :: proc(link: ^Link, now_ms: i64) {
    assert(link.open)
    for _ in 0 ..< DATAGRAMS_PER_UPDATE {
        length, from := LinkReadRaw(link)
        if length < 0 {
            continue
        }
        if length == 0 {
            break
        }
        data: []byte = link.datagram[:length]
        if link.turn.phase != .OFF && from == link.turn.server {
            inner, peer_from, is_data := TurnReceive(link, data, now_ms)
            if is_data && !LinkDropped(link) {
                LinkHandleDatagram(link, peer_from, inner, now_ms, true)
            }
            continue
        }
        if StunLooksLikeStun(data) {
            LinkStunAnswer(link, from, data, now_ms)
            continue
        }
        if LinkDropped(link) {
            continue
        }
        LinkHandleDatagram(link, from, data, now_ms)
    }

    LinkFilterUpdate(link, now_ms)
    TurnUpdate(link, now_ms)
    LinkDerpUpdate(link, now_ms)
    if link.gather == .RUNNING {
        if now_ms - link.gather_start_ms >= GATHER_TIMEOUT_MS {
            LinkGatherFinish(link, now_ms)
        } else if now_ms - link.gather_sent_ms >= GATHER_RETRY_MS {
            LinkGatherSend(link, now_ms)
        }
    }

    for i in 0 ..< MAX_PEERS {
        peer: ^Peer = &link.peers[i]
        switch peer.state {
        case .EMPTY, .FAILED, .LOST:
        case .PUNCHING:
            if now_ms - peer.punch_start_ms >= PUNCH_TIMEOUT_MS {
                peer.state = .FAILED
                LinkPushEvent(link, {kind = .PEER_FAILED, peer = i})
            } else if now_ms - peer.punch_last_ms >= PUNCH_INTERVAL_MS {
                peer.punch_last_ms = now_ms
                // every candidate at once: whichever route the NATs allow is the one that answers
                // guesses first, and not the advertised port itself: every send to a new destination uses up one port of a
                // symmetric NAT, so what is sent first decides which port the peer has to guess. Starting the guesses at the
                // next port on both sides makes the two sequences pair up exactly.
                LinkDerpSignalGuest(link, peer, now_ms)
                spray_base: net.Endpoint = LinkSpray(link, peer)
                for c in 0 ..< peer.candidate_count {
                    if peer.candidates[c] != spray_base {
                        LinkSendPacket(link, peer, peer.candidates[c], .PUNCH, nil)
                    }
                }
            }
        case .CONNECTED:
            LinkUpdatePeer(link, i, peer, now_ms)
        }
    }
}

// A peer behind a symmetric NAT gets a new public port for us, which nobody knows. If its NAT counts up, the port is the next
// ones after the last it handed out: a window of guesses is sent at once, and the one that lands opens the way (the peer
// sprays at us the same way, which also opens our own filtering for its packets).
@(private)
LinkSpray :: proc(link: ^Link, peer: ^Peer) -> (base: net.Endpoint) {
    if peer.nat_mapping != .DEPENDENT || peer.port_delta == 0 || peer.last_port == 0 {
        return
    }
    address: net.Address
    for c in 0 ..< peer.candidate_count {
        if peer.candidates[c].port == peer.last_port && IsPublicAddress(peer.candidates[c].address) {
            address = peer.candidates[c].address
        }
    }
    if address == nil {
        return
    }
    base = {address = address, port = peer.last_port}
    for k in 1 ..= SPRAY_PORTS {
        port: int = peer.last_port + peer.port_delta * k
        if port > 0 && port < 65536 {
            LinkSendPacket(link, peer, {address = address, port = port}, .PUNCH, nil)
        }
    }
    return
}

@(private)
LinkUpdatePeer :: proc(link: ^Link, index: int, peer: ^Peer, now_ms: i64) {
    // a peer that can only be reached through the relay is not given up while the relay is being replaced: it comes back on the new one
    grace: bool = peer.via_relay && peer.has_derp && link.derp.state != .READY && link.derp.state != .OFF
    silence: i64 = DERP_OUTAGE_GRACE_MS if grace else SILENCE_MS
    stall: i64 = DERP_OUTAGE_GRACE_MS if grace else STALL_MS
    if now_ms - peer.rx_ms >= silence || peer.send_count > 0 && now_ms - peer.send_progress_ms >= stall {
        peer.state = .LOST
        LinkPushEvent(link, {kind = .PEER_LOST, peer = index})
        return
    }
    // only the messages that are still missing, each on its own timer: one loss does not cost the others a resend
    for k in 0 ..< peer.send_count {
        slot: int = int(peer.send_base + u16(k)) % WINDOW
        if peer.send_acked[slot] || now_ms - peer.send_last_ms[slot] < PeerResendMs(peer, peer.send_attempts[slot]) {
            continue
        }
        peer.send_attempts[slot] = min(peer.send_attempts[slot] + 1, 255)
        peer.send_last_ms[slot] = now_ms
        LinkSendReliable(link, peer, peer.send_base + u16(k), slot)
        peer.resent += 1
        peer.tx_ms = now_ms
    }
    if peer.ack_due || now_ms - peer.tx_ms >= KEEPALIVE_MS {
        LinkSendAck(link, peer, now_ms)
    }
    // through a relay: keep trying the direct path, the first punch that is answered moves the connection (LinkHandleDatagram)
    if peer.via_relay && now_ms - peer.upgrade_ms >= DERP_UPGRADE_MS {
        peer.upgrade_ms = now_ms
        for c in 0 ..< peer.candidate_count {
            if _, is_derp := DerpEndpointSlot(peer.candidates[c]); !is_derp {
                LinkSendPacket(link, peer, peer.candidates[c], .PUNCH, nil)
            }
        }
    }
}

// ============================================================ tests

@(private = "file")
TestPump :: proc(a: ^Link, b: ^Link, now: ^i64, steps: int, fake_stun: net.UDP_Socket = {}) {
    buffer: [64]byte
    for _ in 0 ..< steps {
        now^ += 10
        if fake_stun != {} {
            // a STUN server in a few lines: answer with the address the request came from
            for {
                length, from, error := net.recv_udp(fake_stun, buffer[:])
                if error != nil || length < STUN_HEADER_SIZE {
                    break
                }
                response: [32]byte
                PutU16BE(response[0:], STUN_BINDING_SUCCESS)
                PutU16BE(response[2:], 12)
                PutU32BE(response[4:], STUN_MAGIC)
                copy(response[8:20], buffer[8:20])
                PutU16BE(response[20:], STUN_ATTR_XOR_MAPPED)
                PutU16BE(response[22:], 8)
                response[25] = 1
                PutU16BE(response[26:], u16(from.port) ~ u16(STUN_MAGIC >> 16))
                ip: net.IP4_Address = from.address.(net.IP4_Address)
                for i in 0 ..< 4 {
                    response[28 + i] = ip[i] ~ byte(STUN_MAGIC >> u32(24 - 8 * i))
                }
                net.send_udp(fake_stun, response[:], from)
            }
        }
        LinkUpdate(a, now^)
        LinkUpdate(b, now^)
        // the fake clock is the protocol time, but loopback datagrams still need a moment of real time to arrive
        time.sleep(time.Millisecond)
    }
}

@(test)
LinkGatherStunTest :: proc(t: ^testing.T) {
    server, make_error := net.make_unbound_udp_socket(.IP4)
    testing.expect(t, make_error == nil)
    defer net.close(server)
    testing.expect(t, net.bind(server, {address = net.IP4_Loopback, port = 0}) == nil)
    testing.expect(t, net.set_blocking(server, false) == nil)
    server_endpoint, _ := net.bound_endpoint(server)

    link := new(Link)

    defer free(link)
    other := new(Link)
    defer free(other)
    testing.expect(t, LinkInit(link, {include_loopback = true}))
    testing.expect(t, LinkInit(other))
    defer LinkClose(link)
    defer LinkClose(other)

    now: i64
    LinkGatherBegin(link, {server_endpoint}, now)
    testing.expect(t, !LinkGathered(link))
    TestPump(link, other, &now, 20, server)
    testing.expect(t, LinkGathered(link))

    // the server saw the loopback address of this socket: it is the first candidate (the "public" one)
    testing.expect(t, link.candidate_count >= 1)
    testing.expect_value(t, link.candidates[0], net.Endpoint{address = net.IP4_Loopback, port = link.local_port})
    // one server answered: not enough to judge the NAT
    testing.expect_value(t, link.nat_mapping, NatMapping.UNKNOWN)
    event, has_event := LinkPollEvent(link)
    testing.expect(t, has_event && event.kind == .GATHERED)
}

// Two links, codes passed as text like two people would.
@(private = "file")
TestConnect :: proc(t: ^testing.T, host: ^Link, guest: ^Link, now: ^i64) -> bool {
    LinkGatherBegin(host, nil, now^)
    LinkGatherBegin(guest, nil, now^)
    TestPump(host, guest, now, 2)
    testing.expect(t, LinkGathered(host) && LinkGathered(guest))

    LinkHost(host, "Host")
    text: [CODE_TEXT_MAX]byte
    invite_text, ok := InviteEncode(LinkMakeInvite(host), text[:])
    testing.expect(t, ok)

    invite, invite_ok := InviteDecode(invite_text)
    testing.expect(t, invite_ok)
    testing.expect(t, LinkJoin(guest, invite, "Guest", now^))
    reply_text: [CODE_TEXT_MAX]byte
    reply_code, reply_ok := InviteEncode(LinkMakeInvite(guest), reply_text[:])
    testing.expect(t, reply_ok)

    reply, reply_decoded := InviteDecode(reply_code)
    testing.expect(t, reply_decoded)
    peer, accepted := LinkAcceptReply(host, reply, now^)
    testing.expect(t, accepted)
    again, again_ok := LinkAcceptReply(host, reply, now^)
    testing.expect(t, again_ok && again == peer)

    TestPump(host, guest, now, 50)
    testing.expect_value(t, LinkPeerCount(host), 1)
    testing.expect_value(t, LinkPeerCount(guest), 1)
    testing.expect_value(t, LinkPeerName(host, peer), "Guest")
    testing.expect_value(t, LinkPeerName(guest, 0), "Host")
    return LinkPeerCount(host) == 1 && LinkPeerCount(guest) == 1
}

// Sealing without any socket: two Links that only hold ids, a secret and one peer each.
@(test)
LinkSealTest :: proc(t: ^testing.T) {
    a := new(Link)
    b := new(Link)
    other := new(Link)
    defer free(a)
    defer free(b)
    defer free(other)
    a.id = 5
    b.id = 9
    other.id = 9
    for i in 0 ..< SECRET_SIZE {
        a.secret[i] = u8(i + 1)
        b.secret[i] = u8(i + 1)
        other.secret[i] = u8(i + 100)                                // a stranger that does not have the code
    }
    a.peers[0] = {state = .CONNECTED, id = b.id}
    b.peers[0] = {state = .CONNECTED, id = a.id}
    other.peers[0] = {state = .CONNECTED, id = a.id}
    PeerKeyMake(a, &a.peers[0])
    PeerKeyMake(b, &b.peers[0])
    PeerKeyMake(other, &other.peers[0])
    testing.expect(t, a.peers[0].key == b.peers[0].key)
    testing.expect(t, a.peers[0].key != other.peers[0].key)

    datagram: [PACKET_HEADER + PACKET_CRYPTO + 8 + MAX_PAYLOAD]byte
    plain: [1 + 8 + MAX_PAYLOAD]byte
    secret_text: string = "attack at dawn"
    length: int = PeerSeal(a, &a.peers[0], .DATA, transmute([]byte)secret_text, nil, datagram[:])
    testing.expect(t, !contains(datagram[:length], transmute([]byte)secret_text))      // not readable on the wire

    // the intended receiver opens it once, and only once (a replay is refused)
    opened: int = PeerOpen(b, &b.peers[0], datagram[:length], plain[:])
    testing.expect_value(t, opened, 1 + len(secret_text))
    testing.expect_value(t, string(plain[1:opened]), secret_text)
    testing.expect_value(t, PeerOpen(b, &b.peers[0], datagram[:length], plain[:]), 0)

    // a bit flipped anywhere after the header: refused. The kind in the header is not covered by the tag, but the kind inside is.
    for position in PACKET_HEADER ..< length {
        copy_of: [PACKET_HEADER + PACKET_CRYPTO + 8 + MAX_PAYLOAD]byte = datagram
        copy_of[position] ~= 1
        fresh := PeerOpen(b, &b.peers[0], copy_of[:length], plain[:])
        testing.expect_value(t, fresh, 0)
    }

    // the one that does not hold the code cannot make a packet that opens, and cannot open ours
    forged: int = PeerSeal(other, &other.peers[0], .DATA, transmute([]byte)secret_text, nil, datagram[:])
    testing.expect_value(t, PeerOpen(b, &b.peers[0], datagram[:forged], plain[:]), 0)
    mine: int = PeerSeal(a, &a.peers[0], .DATA, transmute([]byte)secret_text, nil, datagram[:])
    testing.expect_value(t, PeerOpen(other, &other.peers[0], datagram[:mine], plain[:]), 0)
    // our own packet sent back to us is not accepted either (the direction is part of the nonce)
    testing.expect_value(t, PeerOpen(a, &a.peers[0], datagram[:mine], plain[:]), 0)

    // the replay window: out of order inside 64 is fine, once each; far behind is refused
    a.peers[0].send_counter = 1000
    b.peers[0].recv_any = false
    packets: [70][PACKET_HEADER + PACKET_CRYPTO + 8 + MAX_PAYLOAD]byte
    lengths: [70]int
    for i in 0 ..< 70 {
        lengths[i] = PeerSeal(a, &a.peers[0], .DATA, nil, nil, packets[i][:])
    }
    testing.expect(t, PeerOpen(b, &b.peers[0], packets[69][:lengths[69]], plain[:]) > 0)
    testing.expect(t, PeerOpen(b, &b.peers[0], packets[40][:lengths[40]], plain[:]) > 0)
    testing.expect_value(t, PeerOpen(b, &b.peers[0], packets[40][:lengths[40]], plain[:]), 0)
    testing.expect_value(t, PeerOpen(b, &b.peers[0], packets[3][:lengths[3]], plain[:]), 0)          // 66 behind the newest
    testing.expect(t, PeerOpen(b, &b.peers[0], packets[6][:lengths[6]], plain[:]) > 0)               // 63 behind
}

contains :: proc(haystack: []byte, needle: []byte) -> bool {
    for i in 0 ..= len(haystack) - len(needle) {
        if string(haystack[i:i + len(needle)]) == string(needle) {
            return true
        }
    }
    return false
}

@(test)
LinkPunchAndChatTest :: proc(t: ^testing.T) {
    host := new(Link)
    defer free(host)
    guest := new(Link)
    defer free(guest)
    testing.expect(t, LinkInit(host, {include_loopback = true}))
    testing.expect(t, LinkInit(guest, {include_loopback = true}))
    defer LinkClose(host)
    defer LinkClose(guest)
    now: i64
    if !TestConnect(t, host, guest, &now) {
        return
    }

    testing.expect(t, LinkSend(host, 0, transmute([]byte)string("hello guest"), true, now))
    testing.expect(t, LinkSend(guest, 0, transmute([]byte)string("hello host"), true, now))
    TestPump(host, guest, &now, 10)
    buffer: [MAX_PAYLOAD]byte
    peer, length, ok := LinkReceive(guest, buffer[:])
    testing.expect(t, ok && peer == 0)
    testing.expect_value(t, string(buffer[:length]), "hello guest")
    _, length, ok = LinkReceive(host, buffer[:])
    testing.expect(t, ok)
    testing.expect_value(t, string(buffer[:length]), "hello host")
    _, _, ok = LinkReceive(host, buffer[:])
    testing.expect(t, !ok)

    connected: int
    for {
        event, has_event := LinkPollEvent(host)
        if !has_event {
            break
        }
        if event.kind == .PEER_CONNECTED {
            connected += 1
        }
    }
    testing.expect_value(t, connected, 1)

    // a graceful close is seen by the other side
    LinkDisconnect(guest, 0)
    TestPump(host, guest, &now, 5)
    testing.expect_value(t, LinkPeerCount(host), 0)
}

@(test)
LinkReliableOverLossTest :: proc(t: ^testing.T) {
    host := new(Link)
    defer free(host)
    guest := new(Link)
    defer free(guest)
    testing.expect(t, LinkInit(host, {include_loopback = true}))
    testing.expect(t, LinkInit(guest, {include_loopback = true}))
    defer LinkClose(host)
    defer LinkClose(guest)
    now: i64
    if !TestConnect(t, host, guest, &now) {
        return
    }

    // a third of the datagrams that arrive are thrown away, on both sides (messages and acknowledgements)
    host.drop_percent = 33
    guest.drop_percent = 33

    TOTAL :: 100
    sent: int
    received: int
    buffer: [MAX_PAYLOAD]byte
    for _ in 0 ..< 3000 {
        if sent < TOTAL {
            message: [2]byte = {byte(sent), byte(sent >> 8)}
            if LinkSend(host, 0, message[:], true, now) {
                sent += 1
            }
        }
        TestPump(host, guest, &now, 1)
        for {
            _, length, ok := LinkReceive(guest, buffer[:])
            if !ok {
                break
            }
            // in order, exactly once
            testing.expect_value(t, length, 2)
            testing.expect_value(t, int(buffer[0]) | int(buffer[1]) << 8, received)
            received += 1
        }
        if received == TOTAL {
            break
        }
    }
    testing.expect_value(t, received, TOTAL)
    testing.expect(t, host.peers[0].resent > 0)
    testing.expect_value(t, host.peers[0].state, PeerState.CONNECTED)
}

@(test)
LinkPunchFailsWithoutAnswerTest :: proc(t: ^testing.T) {
    host := new(Link)
    defer free(host)
    guest := new(Link)
    defer free(guest)
    testing.expect(t, LinkInit(host, {include_loopback = true}))
    testing.expect(t, LinkInit(guest, {include_loopback = true}))
    defer LinkClose(host)
    defer LinkClose(guest)
    now: i64
    LinkGatherBegin(host, nil, now)
    LinkGatherBegin(guest, nil, now)
    LinkHost(host, "Host")
    // the host never receives the reply, so nobody answers the punches of the guest
    LinkJoin(guest, LinkMakeInvite(host), "Guest", now)
    TestPump(host, guest, &now, PUNCH_TIMEOUT_MS / 10 + 5)
    testing.expect_value(t, guest.peers[0].state, PeerState.FAILED)
    found: bool
    for {
        event, has_event := LinkPollEvent(guest)
        if !has_event {
            break
        }
        found ||= event.kind == .PEER_FAILED
    }
    testing.expect(t, found)
}
