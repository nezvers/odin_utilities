package main

import "core:fmt"
import "core:net"
import "core:time"
import p2p "../.."

SELFTEST_MESSAGES :: 200

// Host and guest in one process, over real sockets: the real STUN servers, the real local network addresses (loopback is not
// offered, so the packets take the same routes two computers would use), codes passed as text, 20% of the datagrams dropped.
// It proves the whole chain on this machine and prints what the NAT looks like. It cannot prove a crossing of two different
// networks: for that run host and join on two computers.
SelfTest :: proc(use_stun: bool) -> int {
    host: ^p2p.Link = new(p2p.Link)
    guest: ^p2p.Link = new(p2p.Link)
    if !p2p.LinkInit(host) || !p2p.LinkInit(guest) {
        fmt.eprintln("FAIL: cannot open sockets")
        return 1
    }
    defer p2p.LinkClose(host)
    defer p2p.LinkClose(guest)

    servers: [p2p.STUN_MAX_SERVERS]net.Endpoint
    server_count: int
    if use_stun {
        server_count = p2p.LinkResolveStun(servers[:])
        fmt.printfln("STUN servers resolved: %d of %d", server_count, p2p.STUN_MAX_SERVERS)
    }
    p2p.LinkGatherBegin(host, servers[:server_count], p2p.LinkNow())
    p2p.LinkGatherBegin(guest, servers[:server_count], p2p.LinkNow())
    for !p2p.LinkGathered(host) || !p2p.LinkGathered(guest) {
        Pump(host, guest)
    }
    PrintAddresses(host)
    if host.candidate_count == 0 {
        fmt.eprintln("FAIL: no address found")
        return 1
    }
    if use_stun && server_count > 0 && host.stun_port[0] == 0 {
        fmt.eprintln("WARN: STUN servers did not answer (blocked network?)")
    }

    p2p.LinkHost(host, "host")
    text: [p2p.CODE_TEXT_MAX]byte
    invite_text, _ := p2p.InviteEncode(p2p.LinkMakeInvite(host), text[:])
    invite, invite_ok := p2p.InviteDecode(invite_text)
    if !invite_ok || !p2p.LinkJoin(guest, invite, "guest", p2p.LinkNow()) {
        fmt.eprintln("FAIL: invite")
        return 1
    }
    reply_buffer: [p2p.CODE_TEXT_MAX]byte
    reply_text, _ := p2p.InviteEncode(p2p.LinkMakeInvite(guest), reply_buffer[:])
    reply, reply_ok := p2p.InviteDecode(reply_text)
    if !reply_ok {
        fmt.eprintln("FAIL: reply")
        return 1
    }
    _, accepted := p2p.LinkAcceptReply(host, reply, p2p.LinkNow())
    if !accepted {
        fmt.eprintln("FAIL: reply not accepted")
        return 1
    }

    started: i64 = p2p.LinkNow()
    for p2p.LinkPeerCount(host) == 0 || p2p.LinkPeerCount(guest) == 0 {
        Pump(host, guest)
        if p2p.LinkNow() - started > 10000 {
            fmt.eprintln("FAIL: did not connect in 10 s")
            return 1
        }
    }
    fmt.printfln("connected in %d ms, host sees %s, guest sees %s", p2p.LinkNow() - started,
        net.endpoint_to_string(host.peers[0].endpoint, context.temp_allocator),
        net.endpoint_to_string(guest.peers[0].endpoint, context.temp_allocator))

    host.drop_percent = 20
    guest.drop_percent = 20
    sent: [2]int
    got: [2]int
    buffer: [p2p.MAX_PAYLOAD]byte
    started = p2p.LinkNow()
    for got[0] < SELFTEST_MESSAGES || got[1] < SELFTEST_MESSAGES {
        links: [2]^p2p.Link = {host, guest}
        for who in 0 ..< 2 {
            if sent[who] < SELFTEST_MESSAGES {
                message: [4]byte = {byte(sent[who]), byte(sent[who] >> 8), 0, 0}
                if p2p.LinkSend(links[who], 0, message[:], true, p2p.LinkNow()) {
                    sent[who] += 1
                }
            }
        }
        Pump(host, guest)
        for who in 0 ..< 2 {
            for {
                _, length, ok := p2p.LinkReceive(links[1 - who], buffer[:])
                if !ok {
                    break
                }
                if length != 4 || int(buffer[0]) | int(buffer[1]) << 8 != got[who] {
                    fmt.eprintln("FAIL: message out of order or damaged")
                    return 1
                }
                got[who] += 1
            }
        }
        if p2p.LinkNow() - started > 30000 {
            fmt.eprintfln("FAIL: only %d and %d of %d messages arrived in 30 s", got[0], got[1], SELFTEST_MESSAGES)
            return 1
        }
    }
    fmt.printfln("%d messages each way in order over 20%% loss, %d ms, resent %d and %d datagrams",
        SELFTEST_MESSAGES, p2p.LinkNow() - started, host.peers[0].resent, guest.peers[0].resent)
    fmt.println("PASS")
    return 0
}

Pump :: proc(a: ^p2p.Link, b: ^p2p.Link) {
    now: i64 = p2p.LinkNow()
    p2p.LinkUpdate(a, now)
    p2p.LinkUpdate(b, now)
    time.sleep(2 * time.Millisecond)
}
