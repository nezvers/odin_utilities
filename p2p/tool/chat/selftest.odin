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
SelfTest :: proc(use_stun: bool, use_portmap: bool, derp: DerpOptions) -> int {
    host: ^p2p.Link = new(p2p.Link)
    guest: ^p2p.Link = new(p2p.Link)
    config: p2p.LinkConfig
    config.derp_only = derp.only
    if !p2p.LinkInit(host, config) || !p2p.LinkInit(guest, config) {
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
    if derp.enabled {
        server: int = derp.server
        if derp.host == "" && server == 0 {
            candidates: [6]int = {4, 8, 1, 14, 22, 2}
            server = p2p.DerpRace(candidates[:], 6000)
        }
        started: bool = p2p.LinkDerpBeginHost(host, derp.host, p2p.LinkNow()) && p2p.LinkDerpBeginHost(guest, derp.host, p2p.LinkNow()) if derp.host != "" else server != 0 && p2p.LinkDerpBegin(host, server, p2p.LinkNow()) && p2p.LinkDerpBegin(guest, server, p2p.LinkNow())
        if !started {
            fmt.eprintln("FAIL: no DERP relay could be used")
            return 1
        }
        fmt.printfln("DERP relay: %s%s", derp.host if derp.host != "" else p2p.DERP_SERVERS[server - 1].host, ", no addresses offered: everything goes through it" if derp.only else "")
    }
    p2p.LinkGatherBegin(host, servers[:server_count], p2p.LinkNow())
    p2p.LinkGatherBegin(guest, servers[:server_count], p2p.LinkNow())
    for !p2p.LinkGathered(host) || !p2p.LinkGathered(guest) {
        Pump(host, guest)
    }
    if use_portmap {
        mapping: ^p2p.PortMapState = new(p2p.PortMapState)
        if p2p.LinkPortMap(host, mapping, p2p.LinkNow()) {
            fmt.printfln("router forwards %v via %v", net.endpoint_to_string(mapping.external, context.temp_allocator), mapping.protocol)
        } else {
            fmt.println("router did not forward the port")
        }
    }
    // the filtering test runs after the gathering and takes up to 2 seconds
    waited: i64 = p2p.LinkNow()
    for host.filter_state == .BOTH || host.filter_state == .PORT_ONLY {
        Pump(host, guest)
        if p2p.LinkNow() - waited > 4000 {
            break
        }
    }
    PrintAddresses(host)
    if host.candidate_count == 0 {
        fmt.eprintln("FAIL: no address found")
        return 1
    }
    if use_stun && server_count > 0 && !host.stun_answered[0] {
        fmt.eprintln("WARN: STUN servers did not answer (blocked network?)")
    }

    p2p.LinkHost(host, "host")
    text: [p2p.CODE_TEXT_MAX]byte
    short: bool = derp.short && host.derp.state == .READY
    invite_text, _ := p2p.InviteEncode(p2p.LinkMakeInvite(host, short), text[:])
    invite, invite_ok := p2p.InviteDecode(invite_text)
    if !invite_ok || !p2p.LinkJoin(guest, invite, "guest", p2p.LinkNow()) {
        fmt.eprintln("FAIL: invite")
        return 1
    }
    if short {
        fmt.println("short code: the guest's reply goes through the relay by itself")
    } else {
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
    }

    started: i64 = p2p.LinkNow()
    for p2p.LinkPeerCount(host) == 0 || p2p.LinkPeerCount(guest) == 0 {
        Pump(host, guest)
        if p2p.LinkNow() - started > 10000 {
            fmt.eprintln("FAIL: did not connect in 10 s")
            return 1
        }
    }
    fmt.printfln("connected in %d ms, host sees %s%s, guest sees %s%s", p2p.LinkNow() - started,
        net.endpoint_to_string(host.peers[0].endpoint, context.temp_allocator), " (relay)" if host.peers[0].via_relay else "",
        net.endpoint_to_string(guest.peers[0].endpoint, context.temp_allocator), " (relay)" if guest.peers[0].via_relay else "")

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
