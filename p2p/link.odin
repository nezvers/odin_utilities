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
// Not covered, on purpose and stated in the README: no encryption (the session id is a shared secret, not a key), IPv4 only,
// and no relay: two peers behind symmetric NATs (or CGNAT on both sides) cannot reach each other without a TURN server, which
// has no free public offer. The Link tells (`link.nat`) so the program can say why a connection failed.
package p2p

import "core:crypto"
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

PacketKind :: enum u8 {
    PUNCH = 1,                      // "I am here"
    PUNCH_ACK,                      // answer to a PUNCH
    DATA,                           // unreliable message
    DATA_RELIABLE,                  // seq u16, ack u16, message
    ACK,                            // ack u16 (also the keepalive)
    CLOSE,
}

NatKind :: enum {
    UNKNOWN,                        // fewer than two STUN answers, cannot tell
    CONE,                           // same public port towards every server: hole punching works
    SYMMETRIC,                      // a different port per destination: punching usually fails
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
}

LinkEvent :: struct {
    kind: LinkEventKind,
    peer: int,
}

LinkConfig :: struct {
    port: u16,                      // local UDP port, 0 = any
    include_loopback: bool,         // also offer 127.0.0.1 (two programs on one computer, tests)
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
}

Link :: struct {
    socket: net.UDP_Socket,
    open: bool,
    config: LinkConfig,
    role: LinkRole,
    id: u32,                        // identifies this link in punch packets
    session: u64,
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
    stun_port: [STUN_MAX_SERVERS]int,    // public port each server saw, 0 = no answer yet
    stun_count: int,
    nat: NatKind,

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
    datagram: [PACKET_HEADER + 4 + MAX_PAYLOAD + 16]byte,
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
    for link.id == 0 {
        crypto.rand_bytes((cast([^]byte)&link.id)[:size_of(link.id)])
    }
    return true
}

LinkClose :: proc(link: ^Link) {
    if !link.open {
        return
    }
    for peer in link.peers {
        if peer.state == .CONNECTED {
            LinkSendPacket(link, peer.endpoint, .CLOSE, nil)
        }
    }
    net.close(link.socket)
    link.open = false
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
    if _, is_ip4 := endpoint.address.(net.IP4_Address); !is_ip4 {
        return false
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
        link.stun_port[i] = 0
        crypto.rand_bytes(link.stun_txid[i][:])
    }
    link.gather = .RUNNING
    link.gather_start_ms = now_ms
    link.gather_sent_ms = now_ms - GATHER_RETRY_MS
    LinkGatherLocal(link)
    LinkGatherSend(link, now_ms)
    if link.stun_count == 0 {
        LinkGatherFinish(link)
    }
}

LinkGathered :: proc(link: ^Link) -> bool {
    return link.gather == .DONE
}

@(private)
LinkGatherLocal :: proc(link: ^Link) {
    defer free_all(context.temp_allocator)
    interfaces, error := net.enumerate_interfaces(context.temp_allocator)
    if error == nil {
        for interface in interfaces {
            if .Up not_in interface.link.state {
                continue
            }
            for lease in interface.unicast {
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
    }
}

@(private)
LinkGatherSend :: proc(link: ^Link, now_ms: i64) {
    request: [STUN_HEADER_SIZE]byte
    for i in 0 ..< link.stun_count {
        if link.stun_port[i] == 0 {
            StunBuildRequest(request[:], link.stun_txid[i])
            net.send_udp(link.socket, request[:], link.stun_servers[i])
        }
    }
    link.gather_sent_ms = now_ms
}

@(private)
LinkGatherAnswer :: proc(link: ^Link, from: net.Endpoint, data: []byte) {
    for i in 0 ..< link.stun_count {
        if from != link.stun_servers[i] || link.stun_port[i] != 0 {
            continue
        }
        mapped, ok := StunParseResponse(data, link.stun_txid[i])
        if !ok {
            return
        }
        link.stun_port[i] = mapped.port
        LinkAddCandidateFirst(link, mapped)
        answered: int
        for k in 0 ..< link.stun_count {
            if link.stun_port[k] != 0 {
                answered += 1
            }
        }
        if answered == link.stun_count {
            LinkGatherFinish(link)
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

@(private)
LinkGatherFinish :: proc(link: ^Link) {
    if link.gather == .DONE {
        return
    }
    link.gather = .DONE
    first: int
    differs: bool
    answered: int
    for i in 0 ..< link.stun_count {
        if link.stun_port[i] == 0 {
            continue
        }
        answered += 1
        if first == 0 {
            first = link.stun_port[i]
        } else if first != link.stun_port[i] {
            differs = true
        }
    }
    link.nat = .UNKNOWN
    if answered >= 2 {
        link.nat = .SYMMETRIC if differs else .CONE
    }
    LinkPushEvent(link, {kind = .GATHERED})
}

// ============================================================ session

// This link makes the session: a random id that every packet carries, and the invites it hands out.
LinkHost :: proc(link: ^Link, name: string) {
    assert(link.open && link.role == .NONE)
    link.role = .HOST
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
    link.session = invite.session
    link.tag = SessionTag(link.session)
    link.name_len = min(len(name), NAME_MAX)
    copy(link.name[:link.name_len], name)
    PeerStart(&link.peers[0], invite, now_ms)
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
    PeerStart(&link.peers[free_slot], reply, now_ms)
    return free_slot, true
}

// The code of this link: an INVITE for the host, a REPLY for a guest. Call it after the gathering is done.
LinkMakeInvite :: proc(link: ^Link) -> (invite: Invite) {
    assert(link.role != .NONE)
    invite.kind = .INVITE if link.role == .HOST else .REPLY
    invite.session = link.session
    invite.id = link.id
    invite.name = link.name
    invite.name_len = link.name_len
    for i in 0 ..< link.candidate_count {
        InviteAddCandidate(&invite, link.candidates[i])
    }
    return
}

@(private)
SessionTag :: proc(session: u64) -> u32 {
    return u32(session) ~ u32(session >> 32)
}

@(private)
PeerStart :: proc(peer: ^Peer, invite: Invite, now_ms: i64) {
    peer^ = {state = .PUNCHING, id = invite.id, name = invite.name, name_len = invite.name_len}
    peer.candidates = invite.candidates
    peer.candidate_count = invite.candidate_count
    peer.punch_start_ms = now_ms
    peer.punch_last_ms = now_ms - PUNCH_INTERVAL_MS
}

LinkPeerName :: proc(link: ^Link, peer: int) -> string {
    return string(link.peers[peer].name[:link.peers[peer].name_len])
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
        LinkSendPacket(link, peer.endpoint, .DATA, data)
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
        LinkSendPacket(link, peer.endpoint, .CLOSE, nil)
    }
    peer.state = .EMPTY
}

// ============================================================ packets

@(private)
LinkSendPacket :: proc(link: ^Link, to: net.Endpoint, kind: PacketKind, payload: []byte, extra: []byte = nil) {
    buffer: [PACKET_HEADER + 8 + MAX_PAYLOAD]byte
    buffer[0] = PACKET_MAGIC
    buffer[1] = u8(kind)
    PutU32BE(buffer[2:], link.tag)
    PutU32BE(buffer[6:], link.id)
    length: int = PACKET_HEADER
    copy(buffer[length:], extra)
    length += len(extra)
    copy(buffer[length:], payload)
    length += len(payload)
    net.send_udp(link.socket, buffer[:length], to)
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
    LinkSendPacket(link, peer.endpoint, .DATA_RELIABLE, peer.send_data[slot][:peer.send_length[slot]], extra[:])
    peer.tx_packets += 1
    peer.ack_due = false
}

@(private)
LinkSendAck :: proc(link: ^Link, peer: ^Peer, now_ms: i64) {
    extra: [4]byte
    PutU16BE(extra[0:], peer.recv_next)
    PutU16BE(extra[2:], PeerAckMask(peer))
    LinkSendPacket(link, peer.endpoint, .ACK, nil, extra[:])
    peer.ack_due = false
    peer.tx_ms = now_ms
}

@(private)
LinkHandleDatagram :: proc(link: ^Link, from: net.Endpoint, data: []byte, now_ms: i64) {
    if len(data) < PACKET_HEADER || data[0] != PACKET_MAGIC || GetU32BE(data[2:]) != link.tag || link.role == .NONE {
        return
    }
    kind: PacketKind = PacketKind(data[1])
    sender: u32 = GetU32BE(data[6:])
    body: []byte = data[PACKET_HEADER:]

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

    if kind == .PUNCH || kind == .PUNCH_ACK {
        if peer.state == .PUNCHING {
            // from now on the peer is whatever address this packet came from: that is the hole the NAT opened
            peer.state = .CONNECTED
            peer.endpoint = from
            peer.rx_ms = now_ms
            peer.tx_ms = now_ms
            LinkPushEvent(link, {kind = .PEER_CONNECTED, peer = peer_index})
        }
        if kind == .PUNCH {
            // always answer, the peer may still be punching because our earlier answer was lost
            LinkSendPacket(link, from, .PUNCH_ACK, nil)
        }
        if peer.state == .CONNECTED {
            peer.rx_ms = now_ms
        }
        return
    }

    if peer.state != .CONNECTED {
        return
    }
    peer.endpoint = from
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

// Call every frame (or at least every 50 ms): reads the socket, finishes the gathering, punches, resends, keeps alive.
LinkUpdate :: proc(link: ^Link, now_ms: i64) {
    assert(link.open)
    for _ in 0 ..< DATAGRAMS_PER_UPDATE {
        length, from, error := net.recv_udp(link.socket, link.datagram[:])
        if error != nil {
            // Windows reports an ICMP "port unreachable" from an earlier send as a receive error: skip it and read on
            if error == .Would_Block {
                break
            }
            continue
        }
        if length == 0 {
            break
        }
        data: []byte = link.datagram[:length]
        if StunLooksLikeStun(data) {
            LinkGatherAnswer(link, from, data)
            continue
        }
        if link.drop_percent > 0 {
            link.drop_state = link.drop_state * 1664525 + 1013904223
            if int(link.drop_state >> 16) % 100 < link.drop_percent {
                continue
            }
        }
        LinkHandleDatagram(link, from, data, now_ms)
    }

    if link.gather == .RUNNING {
        if now_ms - link.gather_start_ms >= GATHER_TIMEOUT_MS {
            LinkGatherFinish(link)
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
                for c in 0 ..< peer.candidate_count {
                    LinkSendPacket(link, peer.candidates[c], .PUNCH, nil)
                }
            }
        case .CONNECTED:
            LinkUpdatePeer(link, i, peer, now_ms)
        }
    }
}

@(private)
LinkUpdatePeer :: proc(link: ^Link, index: int, peer: ^Peer, now_ms: i64) {
    if now_ms - peer.rx_ms >= SILENCE_MS || peer.send_count > 0 && now_ms - peer.send_progress_ms >= STALL_MS {
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
    testing.expect_value(t, link.nat, NatKind.UNKNOWN)
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
