// Tries a TURN server with your credentials, and optionally sends chat messages through it end to end.
//
//   odin run p2p/tool/turn -- <host:port> <username> <password> [--relay-test]
//
// Free TURN needs an account at a provider (Cloudflare, Metered, ExpressTURN, Xirsys, ...): they give a host, a username and a
// password. Without real credentials the tool still shows the first half of the handshake (the server answers 401 with its
// realm: it is alive and wants a login, which is what tool/probe reports too).
//
// --relay-test: two links in this process, the first one offers ONLY its relayed address, so every packet between them goes
// through the server: 20 messages each way, in order.
package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:time"
import p2p "../.."

main :: proc() {
    if len(os.args) < 4 {
        fmt.eprintln("usage: turn <host:port> <username> <password> [--relay-test]")
        os.exit(2)
    }
    server, resolved := p2p.LinkResolve(os.args[1])
    if !resolved {
        fmt.eprintfln("cannot resolve %s", os.args[1])
        os.exit(1)
    }
    relay_test: bool = len(os.args) > 4 && os.args[4] == "--relay-test"

    host: ^p2p.Link = new(p2p.Link)
    if !p2p.LinkInit(host, {relay_only = relay_test}) {
        fmt.eprintln("cannot open a UDP socket")
        os.exit(1)
    }
    defer p2p.LinkClose(host)
    fmt.printfln("TURN server %s = %s", os.args[1], net.endpoint_to_string(server, context.temp_allocator))
    started: i64 = p2p.LinkNow()
    p2p.LinkTurnBegin(host, server, os.args[2], os.args[3], started)
    for host.turn.phase == .ALLOCATING {
        p2p.LinkUpdate(host, p2p.LinkNow())
        time.sleep(5 * time.Millisecond)
    }
    switch host.turn.phase {
    case .READY:
        fmt.printfln("allocated in %d ms: relayed address %s (the server saw us as %s), lease %d s", p2p.LinkNow() - started,
            net.endpoint_to_string(host.turn.relayed, context.temp_allocator),
            net.endpoint_to_string(host.turn.mapped, context.temp_allocator), host.turn.lifetime_s)
    case .FAILED:
        switch host.turn.failure {
        case 401:
            fmt.printfln("the server answered but refused the credentials (401) after %d ms: wrong username or password", p2p.LinkNow() - started)
        case 0:
            fmt.printfln("no usable answer in %d ms (server down, blocked, or not TURN over UDP)", p2p.LinkNow() - started)
        case:
            fmt.printfln("the server refused the allocation with error %d", host.turn.failure)
        }
        os.exit(1)
    case .OFF, .ALLOCATING:
    }
    if !relay_test {
        return
    }

    guest: ^p2p.Link = new(p2p.Link)
    p2p.LinkInit(guest)
    defer p2p.LinkClose(guest)
    servers: [p2p.STUN_MAX_SERVERS]net.Endpoint
    count: int = p2p.LinkResolveStun(servers[:])
    p2p.LinkGatherBegin(host, servers[:count], p2p.LinkNow())
    p2p.LinkGatherBegin(guest, servers[:count], p2p.LinkNow())
    for !p2p.LinkGathered(host) || !p2p.LinkGathered(guest) {
        Pump(host, guest)
    }
    p2p.LinkHost(host, "relay")
    text: [p2p.CODE_TEXT_MAX]byte
    invite, _ := p2p.InviteDecode(Encode(p2p.LinkMakeInvite(host), text[:]))
    fmt.printfln("the code offers %d address(es): %s", invite.candidate_count, net.endpoint_to_string(invite.candidates[0], context.temp_allocator))
    p2p.LinkJoin(guest, invite, "guest", p2p.LinkNow())
    reply_text: [p2p.CODE_TEXT_MAX]byte
    reply, _ := p2p.InviteDecode(Encode(p2p.LinkMakeInvite(guest), reply_text[:]))
    p2p.LinkAcceptReply(host, reply, p2p.LinkNow())

    connected: i64 = p2p.LinkNow()
    for p2p.LinkPeerCount(host) == 0 || p2p.LinkPeerCount(guest) == 0 {
        Pump(host, guest)
        if p2p.LinkNow() - connected > 15000 {
            fmt.eprintln("FAIL: not connected through the relay in 15 s")
            os.exit(1)
        }
    }
    fmt.printfln("connected through the relay in %d ms (host via relay: %v, guest via relay: %v)", p2p.LinkNow() - connected,
        host.peers[0].via_relay, guest.peers[0].via_relay)

    TOTAL :: 20
    sent: [2]int
    got: [2]int
    links: [2]^p2p.Link = {host, guest}
    buffer: [p2p.MAX_PAYLOAD]byte
    for got[0] < TOTAL || got[1] < TOTAL {
        for who in 0 ..< 2 {
            if sent[who] < TOTAL {
                message: [1]byte = {byte(sent[who])}
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
                if length != 1 || int(buffer[0]) != got[who] {
                    fmt.eprintln("FAIL: message out of order")
                    os.exit(1)
                }
                got[who] += 1
            }
        }
        if p2p.LinkNow() - connected > 30000 {
            fmt.eprintfln("FAIL: %d and %d of %d messages in 30 s", got[0], got[1], TOTAL)
            os.exit(1)
        }
    }
    fmt.printfln("PASS: %d messages each way in order through %s", TOTAL, os.args[1])
}

Encode :: proc(invite: p2p.Invite, buffer: []byte) -> string {
    text, ok := p2p.InviteEncode(invite, buffer)
    assert(ok)
    return text
}

Pump :: proc(a: ^p2p.Link, b: ^p2p.Link) {
    now: i64 = p2p.LinkNow()
    p2p.LinkUpdate(a, now)
    p2p.LinkUpdate(b, now)
    time.sleep(2 * time.Millisecond)
}
