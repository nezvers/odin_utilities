#+build !js
package tunnel

import "core:net"
import "core:testing"
import "core:time"
import "../../wait_for"
import "../../p2p"

// Two Links on one computer (the loopback addresses), connected the way two programs are: invite, reply, accepted
@(private = "file")
connectLinks :: proc(t: ^testing.T, host: ^p2p.Link, guest: ^p2p.Link, now: ^i64) -> bool {
    p2p.LinkGatherBegin(host, nil, now^)
    p2p.LinkGatherBegin(guest, nil, now^)
    pump(host, guest, nil, nil, now, 3)
    p2p.LinkHost(host, "host")
    text: [p2p.CODE_TEXT_MAX]u8
    invite_text, encoded := p2p.InviteEncode(p2p.LinkMakeInvite(host), text[:])
    invite, decoded := p2p.InviteDecode(invite_text)
    if !encoded || !decoded || !p2p.LinkJoin(guest, invite, "guest", now^) { return false }
    reply_text: [p2p.CODE_TEXT_MAX]u8
    reply_code, reply_encoded := p2p.InviteEncode(p2p.LinkMakeInvite(guest), reply_text[:])
    reply, reply_decoded := p2p.InviteDecode(reply_code)
    if !reply_encoded || !reply_decoded { return false }
    _, accepted := p2p.LinkAcceptReply(host, reply, now^)
    pump(host, guest, nil, nil, now, 60)
    return accepted && p2p.LinkPeerCount(host) == 1 && p2p.LinkPeerCount(guest) == 1
}

@(private = "file")
pump :: proc(host: ^p2p.Link, guest: ^p2p.Link, host_tunnel: ^Tunnel, guest_tunnel: ^Tunnel, now: ^i64, steps: int) {
    for _ in 0 ..< steps {
        now^ += 10
        p2p.LinkUpdate(host, now^)
        p2p.LinkUpdate(guest, now^)
        if host_tunnel != nil { TunnelUpdate(host_tunnel, now^) }
        if guest_tunnel != nil { TunnelUpdate(guest_tunnel, now^) }
        time.sleep(time.Millisecond)
    }
}

// A TCP echo server that is stepped by hand (no thread): accepts, and writes back what it reads
@(private = "file")
Echo :: struct {
    listener: net.TCP_Socket,
    clients: [4]net.TCP_Socket,
    count: int,
}

@(private = "file")
echoStep :: proc(echo: ^Echo) {
    for echo.count < len(echo.clients) {
        client, _, error := net.accept_tcp(echo.listener)
        if error != nil { break }
        net.set_blocking(client, false)
        echo.clients[echo.count] = client
        echo.count += 1
    }
    buffer: [2048]u8
    for i in 0 ..< echo.count {
        count, error := net.recv_tcp(echo.clients[i], buffer[:])
        if error == nil && count > 0 { net.send_tcp(echo.clients[i], buffer[:count]) }
    }
}

@(private = "file")
readAll :: proc(t: ^testing.T, socket: net.TCP_Socket, want: int, host: ^p2p.Link, guest: ^p2p.Link, host_tunnel: ^Tunnel, guest_tunnel: ^Tunnel, echo: ^Echo, now: ^i64) -> []u8 {
    received: [dynamic]u8
    received.allocator = context.temp_allocator
    buffer: [4096]u8
    for deadline := wait_for.DeadlineStart(20); !wait_for.DeadlineExpired(&deadline); {
        pump(host, guest, host_tunnel, guest_tunnel, now, 1)
        echoStep(echo)
        count, error := net.recv_tcp(socket, buffer[:])
        if error == nil && count > 0 { append(&received, ..buffer[:count]) }
        if len(received) >= want { break }
    }
    return received[:]
}

@(test)
test_a_tcp_connection_goes_through_a_p2p_link :: proc(t: ^testing.T) {
    host := new(p2p.Link)
    guest := new(p2p.Link)
    host_tunnel := new(Tunnel)
    guest_tunnel := new(Tunnel)
    defer { free(host); free(guest); free(host_tunnel); free(guest_tunnel) }
    testing.expect(t, p2p.LinkInit(host, {include_loopback = true}))
    testing.expect(t, p2p.LinkInit(guest, {include_loopback = true}))
    defer p2p.LinkClose(host)
    defer p2p.LinkClose(guest)
    now: i64
    if !connectLinks(t, host, guest, &now) { return }

    // the "server" on the host side: an echo
    echo: Echo
    listen_error: net.Network_Error
    echo.listener, listen_error = net.listen_tcp({address = net.IP4_Loopback, port = 0})
    testing.expect(t, listen_error == nil)
    net.set_blocking(echo.listener, false)
    defer net.close(echo.listener)
    server, _ := net.bound_endpoint(echo.listener)
    TunnelHostInit(host_tunnel, host, server)
    testing.expect(t, TunnelGuestInit(guest_tunnel, guest, 0, 0))
    defer TunnelClose(host_tunnel)
    defer TunnelClose(guest_tunnel)

    // a client of the guest side: 20 000 bytes (many frames) come back unchanged
    client, dial_error := net.dial_tcp_from_endpoint({address = net.IP4_Loopback, port = guest_tunnel.port})
    testing.expect(t, dial_error == nil)
    defer net.close(client)
    net.set_blocking(client, false)
    sent: [20000]u8
    for i in 0 ..< len(sent) { sent[i] = u8(i * 7 + i / 251) }
    offset: int
    received: [dynamic]u8
    received.allocator = context.temp_allocator
    buffer: [4096]u8
    for deadline := wait_for.DeadlineStart(40); !wait_for.DeadlineExpired(&deadline); {
        pump(host, guest, host_tunnel, guest_tunnel, &now, 1)
        echoStep(&echo)
        if offset < len(sent) {
            count, send_error := net.send_tcp(client, sent[offset:min(offset + 3000, len(sent))])
            if send_error == nil { offset += count }
        }
        count, receive_error := net.recv_tcp(client, buffer[:])
        if receive_error == nil && count > 0 { append(&received, ..buffer[:count]) }
        if len(received) >= len(sent) { break }
    }
    testing.expect_value(t, len(received), len(sent))
    same: bool = len(received) == len(sent)
    for i in 0 ..< min(len(received), len(sent)) { if received[i] != sent[i] { same = false } }
    testing.expect(t, same, "the echo is the same bytes in the same order")

    // a second connection at the same time, and the close of the first is seen on the other side
    second, second_error := net.dial_tcp_from_endpoint({address = net.IP4_Loopback, port = guest_tunnel.port})
    testing.expect(t, second_error == nil)
    defer net.close(second)
    net.set_blocking(second, false)
    net.send_tcp(second, transmute([]u8)string("ping"))
    answer: []u8 = readAll(t, second, 4, host, guest, host_tunnel, guest_tunnel, &echo, &now)
    testing.expect_value(t, string(answer), "ping")
    testing.expect_value(t, TunnelConnectionCount(guest_tunnel), 2)
    testing.expect_value(t, TunnelConnectionCount(host_tunnel), 2)
    net.close(client)
    pump(host, guest, host_tunnel, guest_tunnel, &now, 60)
    testing.expect_value(t, TunnelConnectionCount(guest_tunnel), 1)
    testing.expect_value(t, TunnelConnectionCount(host_tunnel), 1)
}
