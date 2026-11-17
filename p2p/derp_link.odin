// DERP inside the Link: a relay path and a way to finish the connection without pasting a reply. See derp.odin for the relay itself.
//
// Two jobs, both with a relay that two peers share and that needs no account:
//
// 1. Relay of last resort. The peer's DERP key is a candidate like any address: a pseudo address (fd0d:...:slot) that LinkSendRaw
//    turns into "send this through the relay to that key". Punch packets go there too, the first one that arrives wins, the
//    connection runs through the relay and moves to a direct path as soon as a direct punch is answered (like with TURN).
//
// 2. Signalling. A code that names the relay and the sender's key there (no addresses needed, `LinkMakeInvite(link, short = true)`)
//    is enough to start: the guest sends its reply code as a SIGNAL packet through the relay, the host accepts it (the session id
//    in the packet is the proof, as with a pasted reply) and answers with its own full invite. So one code goes one way and nothing
//    comes back by hand.
//
// The relay is behind three procs (send, poll, status) like the sockets are behind Transport, so the simulation (sim_test.odin) runs
// the whole thing with a fake relay and the real one is the Derp client with its TLS connection.
package p2p

import "core:crypto/sha2"
import "core:net"
import "core:sync"

DERP_UPGRADE_MS :: 2500                  // a connection through a relay tries the direct path this often
DERP_CONNECT_GIVE_UP_MS :: 10000         // LinkGathered does not wait longer than this for the relay
DERP_SIGNAL_MS :: 1000
DERP_CUSTOM :: 255                       // invite.derp_server for a relay that is not in DERP_SERVERS (its name travels in the code)
DERP_HOST_MAX :: 48

// Time to wait before the next reconnect after a relay connection was lost or could not be made. Quick at first, because peers that talk
// through the relay give up after 6 to 8 seconds of silence, then slower and slower up to one try every 30 s (it never gives up).
DERP_RETRY_MS := [?]i64{500, 500, 500, 500, 500, 500, 1000, 1000, 2000, 4000, 8000, 15000, 30000}

DerpPathState :: enum {
    OFF,
    CONNECTING,
    RECONNECTING,                        // lost or failed after it worked once: waiting for the next attempt (never gives up)
    READY,
    FAILED,                              // never worked, see failure / failure_kind
}

// The relay as the Link sees it.
DerpPath :: struct {
    state: DerpPathState,
    server: int,                         // index in DERP_SERVERS plus one, or DERP_CUSTOM
    host: [DERP_HOST_MAX]byte,           // the relay's name (also for built in servers: reconnecting needs it)
    host_length: int,
    reconnecting: bool,                  // the current attempt is a reconnect, not the first connection
    attempt: int,
    next_ms: i64,
    lost_ms: i64,                        // when the connection was lost, for reports
    failure_kind: DerpFailure,
    private: BoxKey,
    public: BoxKey,                      // our identity there: it goes into the codes
    user: rawptr,
    send: proc(user: rawptr, peer: BoxKey, data: []byte) -> bool,
    poll: proc(user: rawptr, out: []byte) -> (from: BoxKey, length: int, ok: bool),
    status: proc(user: rawptr) -> DerpPathState,
    restart: proc(path: ^DerpPath),      // makes a new connection to the same relay with the same identity; nil: no reconnecting
    real: ^Derp,                         // set by LinkDerpBegin, freed by LinkClose
    begin_ms: i64,
    failure: string,
    // looking for the host of a channel (LinkDerpFind)
    find: bool,
    find_key: BoxKey,
    find_ms: i64,
    found: Invite,
}

@(private)
DerpScheduleRetry :: proc(derp: ^DerpPath, now_ms: i64) {
    derp.state = .RECONNECTING
    derp.next_ms = now_ms + DERP_RETRY_MS[min(derp.attempt, len(DERP_RETRY_MS) - 1)]
    derp.attempt += 1
}

// The pseudo address of a peer slot. Never leaves the program: LinkSendRaw sees it and uses the relay.
DerpEndpoint :: proc(slot: int) -> net.Endpoint {
    return {address = net.IP6_Address{0xfd0d, 0x0e29, 0, 0, 0, 0, 0, u16be(slot + 1)}, port = 1}
}

DerpEndpointSlot :: proc(endpoint: net.Endpoint) -> (slot: int, ok: bool) {
    address, is_v6 := endpoint.address.(net.IP6_Address)
    if !is_v6 || endpoint.port != 1 || address[0] != 0xfd0d || address[1] != 0x0e29 {
        return
    }
    for i in 2 ..< 7 {
        if address[i] != 0 {
            return
        }
    }
    slot = int(address[7]) - 1
    return slot, slot >= 0 && slot < MAX_PEERS
}

// ---------------------------------------------------------------------------------------------------------------- setup

// Uses a relay through any three procs (the simulation does). The state starts as CONNECTING until `status` says otherwise.
LinkDerpTransport :: proc(link: ^Link, server: int, private: BoxKey, user: rawptr, send: proc(user: rawptr, peer: BoxKey, data: []byte) -> bool, poll: proc(user: rawptr, out: []byte) -> (from: BoxKey, length: int, ok: bool), status: proc(user: rawptr) -> DerpPathState, now_ms: i64, restart: proc(path: ^DerpPath) = nil) {
    assert(link.open && server >= 1 && server <= len(DERP_SERVERS))
    link.derp = {state = .CONNECTING, server = server, private = private, public = BoxPublicKey(private), user = user, send = send, poll = poll, status = status, restart = restart, begin_ms = now_ms}
    link.derp.host_length = min(len(DERP_SERVERS[server - 1].host), DERP_HOST_MAX)
    copy(link.derp.host[:link.derp.host_length], DERP_SERVERS[server - 1].host)
}

// Is the relay of this invite the one we are connected to?
DerpSameRelay :: proc(path: ^DerpPath, invite: Invite) -> bool {
    invite: Invite = invite
    if invite.derp_server == 0 || int(invite.derp_server) != path.server {
        return false
    }
    if path.server == DERP_CUSTOM {
        return invite.derp_host_length == path.host_length && string(invite.derp_host[:invite.derp_host_length]) == string(path.host[:path.host_length])
    }
    return true
}

LinkDerpHost :: proc(link: ^Link) -> string {
    return string(link.derp.host[:link.derp.host_length])
}

@(private)
DerpPathSendReal :: proc(user: rawptr, peer: BoxKey, data: []byte) -> bool {
    return DerpSend(cast(^Derp)user, peer, data)
}

@(private)
DerpPathPollReal :: proc(user: rawptr, out: []byte) -> (from: BoxKey, length: int, ok: bool) {
    packet, got, _ := DerpPoll(cast(^Derp)user, out)
    return packet.from, packet.length, got
}

@(private)
DerpPathStatusReal :: proc(user: rawptr) -> DerpPathState {
    #partial switch DerpGetState(cast(^Derp)user) {
    case .READY:
        return .READY
    case .FAILED, .CLOSED:
        return .FAILED
    }
    return .CONNECTING
}

// The restart of the real client: a new connection to the same relay with the same identity. A connection attempt that is still stuck
// is abandoned (its thread closes it when it ends), not waited for: the frame loop never blocks here.
@(private)
DerpPathRestartReal :: proc(path: ^DerpPath) {
    old: ^Derp = path.real
    if DerpGetState(old) == .CONNECTING {
        sync.atomic_store(&old.abandoned, true)         // leaks its memory, only in the case of a relay that hangs
    } else {
        DerpClose(old)
        free(old)
    }
    fresh: ^Derp = new(Derp)
    DerpBegin(fresh, string(path.host[:path.host_length]), path.private)
    path.real = fresh
    path.user = fresh
}

// Starts connecting to the relay `server` (1 = the first of DERP_SERVERS, ...), on a thread: LinkUpdate notices when it is ready. Call it
// before the gathering is done so the codes can carry the relay (LinkGathered waits for it, up to 10 s). Both sides must use the same
// server number. The identity there is random unless config.derp_private_set. Allocates one Derp (about 110 KB), freed by LinkClose.
// A relay that was lost is reconnected by itself (DERP_LOST, then DERP_READY again).
LinkDerpBegin :: proc(link: ^Link, server: int, now_ms: i64) -> bool {
    if server < 1 || server > len(DERP_SERVERS) {
        return false
    }
    return LinkDerpBeginHost(link, DERP_SERVERS[server - 1].host, now_ms, server)
}

// Any DERP server by name ("derp.example.com" or "derp.example.com:8443"), for a relay of your own or one that is not in the list
// (the list changes, see `odin run p2p/tool/derp -- map`). The code carries the name, so the other side needs nothing but the code.
LinkDerpBeginHost :: proc(link: ^Link, host: string, now_ms: i64, server: int = DERP_CUSTOM) -> bool {
    if link.derp.state != .OFF || host == "" || len(host) > DERP_HOST_MAX {
        return false
    }
    private: BoxKey = link.config.derp_private
    if !link.config.derp_private_set {
        public: BoxKey
        if !BoxKeyGenerate(&private, &public) {
            return false
        }
    }
    derp: ^Derp = new(Derp)
    DerpBegin(derp, host, private)
    link.derp = {state = .CONNECTING, server = server, private = private, public = BoxPublicKey(private), user = derp, real = derp, begin_ms = now_ms}
    link.derp.host_length = len(host)
    copy(link.derp.host[:], host)
    link.derp.send = DerpPathSendReal
    link.derp.poll = DerpPathPollReal
    link.derp.status = DerpPathStatusReal
    link.derp.restart = DerpPathRestartReal
    return true
}

// Begins the relay an invite names (a guest does this with the code it was given). False: the invite names none.
LinkDerpBeginInvite :: proc(link: ^Link, invite: Invite, now_ms: i64) -> bool {
    invite_copy: Invite = invite
    host: string = InviteDerpHost(&invite_copy)
    if host == "" {
        return false
    }
    if invite.derp_server == DERP_CUSTOM {
        return LinkDerpBeginHost(link, host, now_ms)
    }
    return LinkDerpBegin(link, int(invite.derp_server), now_ms)
}

LinkDerpClose :: proc(link: ^Link) {
    if link.derp.real != nil {
        if DerpGetState(link.derp.real) == .CONNECTING {
            sync.atomic_store(&link.derp.real.abandoned, true)       // do not wait for a connect that hangs: it closes itself
        } else {
            DerpClose(link.derp.real)
            free(link.derp.real)
        }
    }
    link.derp = {}
}

// ---------------------------------------------------------------------------------------------------------------- channels

// The identity of the HOST of a named channel at the relay: derived from the name, so everybody who knows the name knows where to ask.
// The name is therefore the secret of the channel: whoever knows it can ask the host to let them in, and can pose as the host.
DerpChannelKey :: proc(channel: string) -> (private: BoxKey, public: BoxKey) {
    context_256: sha2.Context_256
    sha2.init_256(&context_256)
    sha2.update(&context_256, transmute([]byte)string("p2p-derp-channel-v1:"))
    sha2.update(&context_256, transmute([]byte)channel)
    sha2.final(&context_256, private[:])
    private[0] &= 248
    private[31] &= 127
    private[31] |= 64
    public = BoxPublicKey(private)
    return
}

// A guest (no role yet, relay ready) asks the channel's host key every second until an answer arrives: event DERP_HOST_FOUND, the
// host's short invite is in link.derp.found. The host is the member that connected to the relay with the channel's private key
// (config.derp_private = DerpChannelKey(name)) and called LinkHost.
LinkDerpFind :: proc(link: ^Link, host_key: BoxKey, now_ms: i64) {
    link.derp.find = true
    link.derp.find_key = host_key
    link.derp.find_ms = now_ms - DERP_SIGNAL_MS
}

@(private)
LinkSendRendezvous :: proc(link: ^Link, to: BoxKey, kind: PacketKind, invite: ^Invite) {
    packet: [PACKET_HEADER + CODE_BINARY_MAX]byte
    packet[0] = PACKET_MAGIC
    packet[1] = u8(kind)
    length: int = PACKET_HEADER
    if invite != nil {
        count: int = InviteToBinary(invite^, packet[PACKET_HEADER:])
        if count == 0 {
            return
        }
        length += count
    }
    link.derp.send(link.derp.user, to, packet[:length])
}

// ---------------------------------------------------------------------------------------------------------------- per frame

// State changes and incoming packets. Called from LinkUpdate.
@(private)
LinkDerpUpdate :: proc(link: ^Link, now_ms: i64) {
    derp: ^DerpPath = &link.derp
    if derp.state == .OFF {
        return
    }
    if derp.state == .CONNECTING {
        status: DerpPathState = derp.status(derp.user)
        if status == .CONNECTING && now_ms - derp.begin_ms >= DERP_CONNECT_GIVE_UP_MS {
            status = .FAILED
            derp.failure = "no answer from the relay in time"
            derp.failure_kind = .TIMEOUT
        }
        if status == .READY {
            derp.state = .READY
            derp.reconnecting = false
            derp.attempt = 0
            LinkPushEvent(link, {kind = .DERP_READY})
        } else if status == .FAILED {
            if derp.real != nil && derp.failure == "" {
                derp.failure = derp.real.failure
                derp.failure_kind = derp.real.failure_kind
            }
            if derp.reconnecting || derp.restart != nil && derp.attempt > 0 {
                DerpScheduleRetry(derp, now_ms)
            } else {
                derp.state = .FAILED
                LinkPushEvent(link, {kind = .DERP_FAILED})
                // a relay that never worked is retried too (the network may come back), without holding anything up
                if derp.restart != nil {
                    derp.reconnecting = true
                    DerpScheduleRetry(derp, now_ms)
                }
            }
        }
        return
    }
    if derp.state == .RECONNECTING || derp.state == .FAILED && derp.reconnecting {
        if now_ms >= derp.next_ms && derp.restart != nil {
            derp.failure = ""
            derp.restart(derp)
            derp.state = .CONNECTING
            derp.begin_ms = now_ms
        }
        return
    }
    if derp.state != .READY {
        return
    }
    if derp.status(derp.user) == .FAILED {
        derp.failure = derp.real.failure if derp.real != nil && derp.real.failure != "" else "the relay connection ended"
        derp.failure_kind = .CLOSED
        derp.lost_ms = now_ms
        LinkPushEvent(link, {kind = .DERP_LOST})
        if derp.restart != nil {
            derp.reconnecting = true
            derp.attempt = 0
            DerpScheduleRetry(derp, now_ms)
        } else {
            derp.state = .FAILED
            LinkPushEvent(link, {kind = .DERP_FAILED})
        }
        return
    }
    if derp.find && link.role == .NONE && now_ms - derp.find_ms >= DERP_SIGNAL_MS {
        derp.find_ms = now_ms
        LinkSendRendezvous(link, derp.find_key, .WHO, nil)
    }
    buffer: [PACKET_HEADER + 8 + MAX_PAYLOAD + 64]byte
    for _ in 0 ..< DATAGRAMS_PER_UPDATE {
        from, length, ok := derp.poll(derp.user, buffer[:])
        if !ok {
            break
        }
        if !LinkDropped(link) {
            LinkDerpDispatch(link, from, buffer[:length], now_ms)
        }
    }
}

@(private)
LinkDerpDispatch :: proc(link: ^Link, from: BoxKey, data: []byte, now_ms: i64) {
    if len(data) < PACKET_HEADER || data[0] != PACKET_MAGIC {
        return
    }
    // the rendezvous of a channel happens before there is a session, so these carry no tag
    #partial switch PacketKind(data[1]) {
    case .WHO:
        if link.role == .HOST && link.derp.state == .READY && LinkPeerCount(link) < MAX_PEERS {
            invite: Invite = LinkMakeInvite(link, true)
            LinkSendRendezvous(link, from, .HERE, &invite)
        }
        return
    case .HERE:
        if link.derp.find && link.role == .NONE && from == link.derp.find_key {
            invite, ok := InviteFromBinary(data[PACKET_HEADER:])
            if ok && invite.kind == .INVITE && DerpSameRelay(&link.derp, invite) && invite.derp_key == from {
                link.derp.found = invite
                link.derp.find = false
                LinkPushEvent(link, {kind = .DERP_HOST_FOUND})
            }
        }
        return
    }
    if link.role == .NONE {
        return
    }
    if PacketKind(data[1]) == .SIGNAL {
        LinkHandleSignal(link, from, data, now_ms)
        return
    }
    from_copy: BoxKey = from
    for i in 0 ..< MAX_PEERS {
        peer: ^Peer = &link.peers[i]
        if peer.state != .EMPTY && peer.has_derp && peer.derp_key == from_copy {
            LinkHandleDatagram(link, DerpEndpoint(i), data, now_ms, true)
            return
        }
    }
}

// Sends one datagram of the link to the peer in `slot` through the relay.
@(private)
LinkDerpSend :: proc(link: ^Link, slot: int, data: []byte) {
    peer: ^Peer = &link.peers[slot]
    if link.derp.state == .READY && peer.has_derp {
        link.derp.send(link.derp.user, peer.derp_key, data)
    }
}

// ---------------------------------------------------------------------------------------------------------------- signalling

// Our invite (or reply) as a SIGNAL packet through the relay to the key `to`.
@(private)
LinkSendSignal :: proc(link: ^Link, to: BoxKey, invite: Invite) {
    if link.derp.state != .READY {
        return
    }
    binary: [CODE_BINARY_MAX]byte
    length: int = InviteToBinary(invite, binary[:])
    if length == 0 {
        return
    }
    packet: [PACKET_HEADER + CODE_BINARY_MAX]byte
    packet[0] = PACKET_MAGIC
    packet[1] = u8(PacketKind.SIGNAL)
    PutU32BE(packet[2:], link.tag)
    PutU32BE(packet[6:], link.id)
    copy(packet[PACKET_HEADER:], binary[:length])
    link.derp.send(link.derp.user, to, packet[:PACKET_HEADER + length])
}

// A SIGNAL from a key. Host: a guest sends its reply, which is accepted like a pasted one, and the host answers with its full invite.
// Guest: the host's full invite (addresses, NAT facts) completes what the short code lacked.
@(private)
LinkHandleSignal :: proc(link: ^Link, from: BoxKey, data: []byte, now_ms: i64) {
    if GetU32BE(data[2:]) != link.tag || link.derp.state != .READY {
        return
    }
    invite, ok := InviteFromBinary(data[PACKET_HEADER:])
    if !ok || invite.session != link.session || !DerpSameRelay(&link.derp, invite) || invite.derp_key != from {
        return                                       // not for this session, or not from the key it claims
    }
    switch {
    case link.role == .HOST && invite.kind == .REPLY:
        slot, accepted := LinkAcceptReply(link, invite, now_ms)
        if accepted {
            LinkSendSignal(link, from, LinkMakeInvite(link))
        }
        _ = slot
    case link.role == .GUEST && invite.kind == .INVITE:
        peer: ^Peer = &link.peers[0]
        if peer.state != .EMPTY && peer.id == invite.id {
            PeerMerge(link, 0, invite)
        }
    }
}

// Adds what a full invite tells (addresses, NAT facts) to a peer that was started from a short one. The relay candidate stays.
@(private)
PeerMerge :: proc(link: ^Link, slot: int, invite: Invite) {
    peer: ^Peer = &link.peers[slot]
    peer.candidate_count = 0
    for i in 0 ..< invite.candidate_count {
        peer.candidates[peer.candidate_count] = invite.candidates[i]
        peer.candidate_count += 1
    }
    PeerAddDerpCandidate(peer, slot)
    peer.nat_mapping = invite.nat_mapping
    peer.nat_filtering = invite.nat_filtering
    peer.port_delta = invite.port_delta
    peer.last_port = invite.last_port
}

// The relay as a candidate of the peer (last in the list: a direct address is always better; a full list gives up its last one).
@(private)
PeerAddDerpCandidate :: proc(peer: ^Peer, slot: int) {
    endpoint: net.Endpoint = DerpEndpoint(slot)
    for i in 0 ..< peer.candidate_count {
        if peer.candidates[i] == endpoint {
            return
        }
    }
    if peer.candidate_count < MAX_CANDIDATES {
        peer.candidates[peer.candidate_count] = endpoint
        peer.candidate_count += 1
    } else {
        peer.candidates[MAX_CANDIDATES - 1] = endpoint
    }
}

// What the guest keeps sending while it is not connected yet: its reply, through the relay, so the host does not need a pasted one.
@(private)
LinkDerpSignalGuest :: proc(link: ^Link, peer: ^Peer, now_ms: i64) {
    if link.role != .GUEST || !peer.has_derp || now_ms - peer.signal_ms < DERP_SIGNAL_MS {
        return
    }
    peer.signal_ms = now_ms
    LinkSendSignal(link, peer.derp_key, LinkMakeInvite(link))
}

// A random identity for tests and tools that do not keep one.
DerpIdentity :: proc() -> (private: BoxKey, public: BoxKey) {
    BoxKeyGenerate(&private, &public)
    return
}
