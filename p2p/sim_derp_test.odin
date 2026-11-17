package p2p

// The DERP relay in the simulation: a switchboard that hands a packet to the host that registered the destination key. Links use it
// through the same three procs the real client sits behind (DerpPath), so the relay path, the signalling and the way back to a
// direct connection run here without a network, and with every NAT combination.

import "core:net"
import "core:testing"

SIM_DERP_QUEUE :: 24

SimDerpPacket :: struct {
    from: BoxKey,
    length: int,
    data: [1300]byte,
}

SimDerpHost :: struct {
    registered: bool,
    key: BoxKey,
    queue: [SIM_DERP_QUEUE]SimDerpPacket,
    head: int,
    count: int,
}

SimDerpSend :: proc(user: rawptr, peer: BoxKey, data: []byte) -> bool {
    host: ^SimHost = cast(^SimHost)user
    sim: ^Sim = host.sim
    if sim.derp_down || len(data) > len(SimDerpPacket{}.data) {
        return false
    }
    peer_copy: BoxKey = peer
    for i in 0 ..< sim.host_count {
        target: ^SimHost = &sim.hosts[i]
        if !target.derp.registered || target.derp.key != peer_copy || target.derp.count >= SIM_DERP_QUEUE {
            continue
        }
        slot: ^SimDerpPacket = &target.derp.queue[(target.derp.head + target.derp.count) % SIM_DERP_QUEUE]
        slot.from = host.derp.key
        slot.length = len(data)
        copy(slot.data[:], data)
        target.derp.count += 1
        sim.derp_relayed += 1
        return true
    }
    return true                                      // like the real relay: no answer when the peer is not there
}

SimDerpPoll :: proc(user: rawptr, out: []byte) -> (from: BoxKey, length: int, ok: bool) {
    host: ^SimHost = cast(^SimHost)user
    if host.derp.count == 0 {
        return
    }
    packet: ^SimDerpPacket = &host.derp.queue[host.derp.head]
    host.derp.head = (host.derp.head + 1) % SIM_DERP_QUEUE
    host.derp.count -= 1
    copy(out, packet.data[:packet.length])
    return packet.from, packet.length, true
}

SimDerpStatus :: proc(user: rawptr) -> DerpPathState {
    host: ^SimHost = cast(^SimHost)user
    return .FAILED if host.sim.derp_down else .READY
}

// Connects a link to the fake relay with a key made from `seed` (the simulation needs no randomness).
// "Reconnecting" in the simulation: nothing to rebuild, the relay answers again when it is up (see SimDerpStatus).
SimDerpRestart :: proc(path: ^DerpPath) {
}

SimDerpAttach :: proc(host: ^SimHost, link: ^Link, seed: u8, now_ms: i64) {
    private: BoxKey
    for i in 0 ..< 32 {
        private[i] = u8(i) ~ seed
    }
    private[0] &= 248
    private[31] = private[31] & 127 | 64
    SimDerpAttachKey(host, link, private, now_ms)
}

SimDerpAttachKey :: proc(host: ^SimHost, link: ^Link, private: BoxKey, now_ms: i64) {
    link.derp = {}
    LinkDerpTransport(link, 8, private, host, SimDerpSend, SimDerpPoll, SimDerpStatus, now_ms, SimDerpRestart)
    host.derp.registered = true
    host.derp.key = link.derp.public
}

SimDerpMode :: enum {
    FULL_CODES,                      // both codes pasted by hand, the relay is only a candidate
    SHORT,                           // the host's code names the relay, the reply goes through it by itself
    ONLY,                            // no addresses anywhere: everything goes through the relay
}

// The flow of two people with a relay on both sides. Returns milliseconds until both are connected, or -1.
SimConnectDerp :: proc(sim: ^Sim, a: ^Link, b: ^Link, now: ^i64, mode: SimDerpMode, limit_ms: i64 = 30000) -> i64 {
    servers: [2]net.Endpoint = {sim.stuns[0].endpoint, sim.stuns[1].endpoint}
    SimDerpAttach((^SimHost)(a.transport.user), a, 1, now^)
    SimDerpAttach((^SimHost)(b.transport.user), b, 2, now^)
    if mode == .ONLY {
        a.config.derp_only = true
        b.config.derp_only = true
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
    invite_text, _ := InviteEncode(LinkMakeInvite(a, mode == .SHORT), text[:])
    invite, invite_ok := InviteDecode(invite_text)
    if !invite_ok || !LinkJoin(b, invite, "B", now^) {
        return -1
    }
    started: i64 = now^
    if mode != .SHORT {
        reply_text: [CODE_TEXT_MAX]byte
        reply_code, _ := InviteEncode(LinkMakeInvite(b), reply_text[:])
        reply, reply_ok := InviteDecode(reply_code)
        if !reply_ok {
            return -1
        }
        if _, accepted := LinkAcceptReply(a, reply, now^); !accepted {
            return -1
        }
    }
    for now^ - started < limit_ms {
        SimPump(a, b, now, 1)
        if LinkPeerCount(a) == 1 && LinkPeerCount(b) == 1 {
            return now^ - started
        }
    }
    return -1
}

SimPairDerp :: proc(kind_a: SimKind, kind_b: SimKind, mode: SimDerpMode) -> (milliseconds: i64) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    nat_a: int = -1 if kind_a == .PUBLIC else SimAddNat(sim, SimConfigOf(kind_a))
    nat_b: int = -1 if kind_b == .PUBLIC else SimAddNat(sim, SimConfigOf(kind_b))
    a: ^Link = SimLink(SimAddHost(sim, nat_a))
    b: ^Link = SimLink(SimAddHost(sim, nat_b))
    defer free(a)
    defer free(b)
    now: i64
    return SimConnectDerp(sim, a, b, &now, mode)
}

// The reason for the relay: with it EVERY pair connects, including the two unpredictable symmetric NATs that nothing else can
// connect without a router mapping or IPv6. Once with a hand made reply, once with the guest's reply travelling through the relay.
@(test)
SimDerpMatrixTest :: proc(t: ^testing.T) {
    for mode in ([?]SimDerpMode{.FULL_CODES, .SHORT}) {
        for a in SimKind {
            for b in SimKind {
                testing.expectf(t, SimPairDerp(a, b, mode) >= 0, "%v with %v (%v): not connected through the relay", a, b, mode)
            }
        }
    }
}

// No addresses at all in the codes: the connection can only be the relay's, and stays there.
@(test)
SimDerpOnlyTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    a: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.FULL_CONE))))
    b: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.FULL_CONE))))
    defer free(a)
    defer free(b)
    now: i64
    testing.expect(t, SimConnectDerp(sim, a, b, &now, .ONLY) >= 0)
    SimPump(a, b, &now, 600)
    testing.expect(t, a.peers[0].via_relay && b.peers[0].via_relay)
    testing.expect_value(t, a.peers[0].candidate_count, 1)          // only the relay
    before: int = sim.derp_relayed

    // a chat through it, both directions, reliable
    for i in 0 ..< 5 {
        message: [16]byte
        message[0] = u8(i)
        testing.expect(t, LinkSend(a, 0, message[:4], true, now))
        testing.expect(t, LinkSend(b, 0, message[:8], true, now))
    }
    SimPump(a, b, &now, 100)
    buffer: [MAX_PAYLOAD]byte
    got_a, got_b: int
    for {
        _, length, ok := LinkReceive(a, buffer[:])
        if !ok {
            break
        }
        got_a += 1
        testing.expect_value(t, length, 8)
    }
    for {
        _, length, ok := LinkReceive(b, buffer[:])
        if !ok {
            break
        }
        got_b += 1
        testing.expect_value(t, length, 4)
    }
    testing.expect_value(t, got_a, 5)
    testing.expect_value(t, got_b, 5)
    testing.expect(t, sim.derp_relayed > before)
}

// The relay is a way in, not a home: two cone NATs connect through it first and then end up on the direct path.
@(test)
SimDerpUpgradeTest :: proc(t: ^testing.T) {
    for kind in ([?]SimKind{.FULL_CONE, .ADDRESS_RESTRICTED, .PORT_RESTRICTED}) {
        sim: ^Sim = new(Sim)
        defer free(sim)
        SimInit(sim)
        a: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(kind))))
        b: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(kind))))
        defer free(a)
        defer free(b)
        now: i64
        testing.expect(t, SimConnectDerp(sim, a, b, &now, .SHORT) >= 0)
        SimPump(a, b, &now, 600)
        testing.expectf(t, !a.peers[0].via_relay && !b.peers[0].via_relay, "%v: still on the relay after 6 s", kind)
    }
}

// Two unpredictable symmetric NATs have no direct path: the connection stays on the relay and survives a long chat with loss.
@(test)
SimDerpLossTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    a: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.SYMMETRIC_RANDOM))))
    b: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.SYMMETRIC_RANDOM))))
    defer free(a)
    defer free(b)
    now: i64
    testing.expect(t, SimConnectDerp(sim, a, b, &now, .SHORT) >= 0)
    a.drop_percent = 20
    b.drop_percent = 20
    sent: int
    received: int
    buffer: [MAX_PAYLOAD]byte
    for step in 0 ..< 3000 {
        if sent < 150 && LinkSend(a, 0, transmute([]byte)string("a message through the relay"), true, now) {
            sent += 1
        }
        SimPump(a, b, &now, 1)
        for {
            _, _, ok := LinkReceive(b, buffer[:])
            if !ok {
                break
            }
            received += 1
        }
        _ = step
    }
    testing.expect_value(t, received, 150)
    testing.expect(t, b.peers[0].via_relay)
}

// A relay that is down changes nothing for the rest: the failure is reported, gathering does not hang, and ordinary codes still connect
// the pairs that can connect without it.
@(test)
SimDerpDownTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    sim.derp_down = true
    a: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.FULL_CONE))))
    b: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.PORT_RESTRICTED))))
    defer free(a)
    defer free(b)
    now: i64
    testing.expect(t, SimConnectDerp(sim, a, b, &now, .FULL_CODES) >= 0)
    testing.expect(t, a.derp.state != DerpPathState.READY)
    failed: bool
    for {
        event, ok := LinkPollEvent(a)
        if !ok {
            break
        }
        failed ||= event.kind == .DERP_FAILED
    }
    testing.expect(t, failed)
    // the codes made without a working relay carry none
    invite: Invite = LinkMakeInvite(a)
    testing.expect_value(t, invite.derp_server, u8(0))
}

// A SIGNAL packet is accepted only for the right session and only from the key it names.
@(test)
SimDerpSignalSecurityTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    a: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.FULL_CONE))))
    b: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.FULL_CONE))))
    c: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.FULL_CONE))))
    defer free(a)
    defer free(b)
    defer free(c)
    now: i64
    servers: [2]net.Endpoint = {sim.stuns[0].endpoint, sim.stuns[1].endpoint}
    SimDerpAttach((^SimHost)(a.transport.user), a, 1, now)
    SimDerpAttach((^SimHost)(c.transport.user), c, 3, now)
    LinkGatherBegin(a, servers[:], now)
    LinkGatherBegin(c, servers[:], now)
    for !LinkGathered(a) || !LinkGathered(c) {
        SimPump(a, c, &now, 1)
    }
    LinkHost(a, "A")
    // the stranger C knows nothing: a SIGNAL with a wrong session is dropped
    LinkHost(c, "C")                                                 // C plays the attacker with a session of its own
    stranger: Invite = LinkMakeInvite(c)
    stranger.kind = .REPLY
    LinkSendSignal(c, a.derp.public, stranger)
    SimPump(a, c, &now, 50)
    testing.expect_value(t, LinkPeerCount(a), 0)
    testing.expect_value(t, a.peers[0].state, PeerState.EMPTY)

    // the right session, but sent from a key that is not the one inside the invite: dropped
    forged: Invite = LinkMakeInvite(c)
    forged.kind = .REPLY
    forged.session = a.session
    forged.derp_key[0] = 9                                           // claims to be somebody else
    LinkSendSignal(c, a.derp.public, forged)
    SimPump(a, c, &now, 50)
    testing.expect_value(t, a.peers[0].state, PeerState.EMPTY)

    // the honest one with the right session and its own key is accepted
    honest: Invite = LinkMakeInvite(c)
    honest.kind = .REPLY
    honest.session = a.session
    c.tag = a.tag                                                    // the packet header carries the session tag
    LinkSendSignal(c, a.derp.public, honest)
    SimPump(a, c, &now, 50)
    testing.expect(t, a.peers[0].state != PeerState.EMPTY)
}

// A channel found by its name alone: the host sits at the relay under a key derived from the name, a guest asks that key, gets the host's
// short invite and joins; nobody pasted anything. A guest that knows another name asks another key and gets no answer.
@(test)
SimDerpChannelTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    a: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.SYMMETRIC_RANDOM))))
    b: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.SYMMETRIC_RANDOM))))
    c: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.FULL_CONE))))
    defer free(a)
    defer free(b)
    defer free(c)
    now: i64
    servers: [2]net.Endpoint = {sim.stuns[0].endpoint, sim.stuns[1].endpoint}
    private, public: BoxKey = DerpChannelKey("my-team")
    SimDerpAttachKey((^SimHost)(a.transport.user), a, private, now)
    SimDerpAttach((^SimHost)(b.transport.user), b, 2, now)
    SimDerpAttach((^SimHost)(c.transport.user), c, 3, now)
    for link in ([?]^Link{a, b, c}) {
        LinkGatherBegin(link, servers[:], now)
    }
    for !LinkGathered(a) || !LinkGathered(b) || !LinkGathered(c) {
        SimPump(a, b, &now, 1)
        LinkUpdate(c, now)
    }
    testing.expect_value(t, a.derp.public, public)
    LinkHost(a, "host")

    other_private, other_public: BoxKey = DerpChannelKey("another-team")
    _ = other_private
    LinkDerpFind(b, public, now)
    LinkDerpFind(c, other_public, now)
    found: bool
    for _ in 0 ..< 400 {
        SimPump(a, b, &now, 1)
        LinkUpdate(c, now)
        for {
            event, ok := LinkPollEvent(b)
            if !ok {
                break
            }
            found ||= event.kind == .DERP_HOST_FOUND
        }
        if found {
            break
        }
    }
    testing.expect(t, found)
    testing.expect_value(t, b.derp.found.session, a.session)
    testing.expect(t, LinkJoin(b, b.derp.found, "guest", now))
    connected: bool
    for _ in 0 ..< 1500 {
        SimPump(a, b, &now, 1)
        if LinkPeerCount(a) == 1 && LinkPeerCount(b) == 1 {
            connected = true
            break
        }
    }
    testing.expect(t, connected)                                     // two random-port symmetric NATs, through the relay
    // the wrong channel name never got an answer
    for _ in 0 ..< 300 {
        LinkUpdate(c, now)
        now += 10
        SimPump(a, b, &now, 1)
    }
    testing.expect(t, c.derp.find)
    testing.expect_value(t, c.role, LinkRole.NONE)
}

// The relay goes away for a few seconds in the middle of a chat and comes back: the link reports DERP_LOST, reconnects by itself, the
// reliable channel resends what was lost meanwhile, nothing arrives twice or out of order, the peers never notice more than a pause.
@(test)
SimDerpReconnectTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    a: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.SYMMETRIC_RANDOM))))
    b: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.SYMMETRIC_RANDOM))))
    defer free(a)
    defer free(b)
    now: i64
    testing.expect(t, SimConnectDerp(sim, a, b, &now, .SHORT) >= 0)
    sent, received: int
    buffer: [MAX_PAYLOAD]byte
    lost, recovered: bool
    for step in 0 ..< 2500 {
        if step == 300 {
            sim.derp_down = true
        }
        if step == 700 {
            sim.derp_down = false                       // 4 s of nothing
        }
        if sent < 200 {
            message: [4]byte = {byte(sent), byte(sent >> 8), 0, 0}
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
            testing.expect_value(t, length, 4)
            testing.expect_value(t, int(buffer[0]) | int(buffer[1]) << 8, received)      // in order, none twice
            received += 1
        }
        for {
            event, ok := LinkPollEvent(a)
            if !ok {
                break
            }
            lost ||= event.kind == .DERP_LOST
            recovered ||= event.kind == .DERP_READY && lost
            testing.expect(t, event.kind != .PEER_LOST)
        }
    }
    testing.expect(t, lost)
    testing.expect(t, recovered)
    testing.expect_value(t, a.derp.state, DerpPathState.READY)
    testing.expect_value(t, received, 200)
    testing.expect_value(t, LinkPeerCount(a), 1)
}

// A relay that is down from the start: gathering does not wait for it, the link says why, keeps trying, and a relay that comes up later
// is used by the codes made after that.
@(test)
SimDerpLateTest :: proc(t: ^testing.T) {
    sim: ^Sim = new(Sim)
    defer free(sim)
    SimInit(sim)
    sim.derp_down = true
    a: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.FULL_CONE))))
    b: ^Link = SimLink(SimAddHost(sim, SimAddNat(sim, SimConfigOf(.FULL_CONE))))
    defer free(a)
    defer free(b)
    now: i64
    servers: [2]net.Endpoint = {sim.stuns[0].endpoint, sim.stuns[1].endpoint}
    SimDerpAttach((^SimHost)(a.transport.user), a, 1, now)
    LinkGatherBegin(a, servers[:], now)
    LinkGatherBegin(b, servers[:], now)
    for !LinkGathered(a) {
        SimPump(a, b, &now, 1)
        testing.expect(t, now < 5000)
    }
    LinkHost(a, "A")
    testing.expect_value(t, LinkMakeInvite(a).derp_server, u8(0))     // no relay in the code
    sim.derp_down = false
    SimPump(a, b, &now, 800)                                          // the retry (a few seconds at most)
    testing.expect_value(t, a.derp.state, DerpPathState.READY)
    ready: bool
    for {
        event, ok := LinkPollEvent(a)
        if !ok {
            break
        }
        ready ||= event.kind == .DERP_READY
    }
    testing.expect(t, ready)
    testing.expect(t, LinkMakeInvite(a).derp_server != 0)
}
