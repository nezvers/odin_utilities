package spacetimedb

// The bytes between this library and a server: a TCP socket, with TLS 1.3 on top of it for `https://` and `wss://` (databases on maincloud or behind a proxy; p2p/tls13.odin does the
// handshake and checks the certificate against the host name). HTTP and the websocket use only this, so both work in both ways.

import "core:net"
import "core:time"
import p2p "../p2p"

StreamStatus :: enum u8 {
    OK,             // bytes were moved
    NONE,           // nothing yet (a non blocking socket, or the time limit)
    CLOSED,         // the other side closed it, or it broke
}

// A program that reaches the server through something that has to be stepped by the same thread (a tunnel over a p2p Link, see tunnel/) sets this: every wait of a blocking call
// (an HTTP request, the websocket handshake) calls it in between, so the other end keeps being served while this one waits. Plain sockets only.
// Per thread: a test thread that plays a server in the same thread must not slow down the sockets of another thread.
@(thread_local)
StreamIdle: proc(user: rawptr)
@(thread_local)
StreamIdleUser: rawptr

Stream :: struct {
    socket: net.TCP_Socket,
    timeout: time.Duration,
    polling: bool,              // the idle hook was set when this stream was opened: waits are polls
    secure: bool,
    tls: p2p.Tls,   // used when `secure` (about 55 KB: a stream lives in the struct of its connection, not on a small stack)
}

// Connects (and runs the TLS handshake when the endpoint is secure). `timeout` is the time limit of every blocking step.
streamOpen :: proc(stream: ^Stream, endpoint: Endpoint, timeout: time.Duration) -> (ok: bool, error: string) {
    stream.secure = endpoint.secure
    socket, dial_error := net.dial_tcp_from_hostname_with_port_override(endpoint.host, endpoint.port)
    if dial_error != nil { return false, "could not connect" }
    net.set_option(socket, .Receive_Timeout, timeout)
    net.set_option(socket, .Send_Timeout, timeout)
    stream.socket, stream.timeout = socket, timeout
    if StreamIdle != nil && !endpoint.secure {
        stream.polling = true
        net.set_blocking(socket, false)
    }
    if endpoint.secure {
        if !p2p.TlsConnect(&stream.tls, socket, endpoint.host) {
            net.close(socket)
            return false, stream.tls.failure if stream.tls.failure != "" else "the TLS handshake failed"
        }
    }
    return true, ""
}

streamClose :: proc(stream: ^Stream) {
    if stream.secure { p2p.TlsClose(&stream.tls) }
    net.close(stream.socket)
}

// Sends all of `bytes`. A non blocking socket that cannot take them yet is retried for up to `patience`.
streamSend :: proc(stream: ^Stream, bytes: []u8, patience: time.Duration = 0) -> bool {
    if stream.secure { return p2p.TlsWrite(&stream.tls, bytes) }
    sent: int
    start: time.Tick = time.tick_now()
    for sent < len(bytes) {
        count, error := net.send_tcp(stream.socket, bytes[sent:])
        if error == .Would_Block && (patience > 0 || stream.polling) {
            if time.tick_since(start) > (patience if patience > 0 else stream.timeout) { return false }
            if stream.polling { StreamIdle(StreamIdleUser) }
            time.sleep(time.Millisecond)
            continue
        }
        if error != nil || count <= 0 { return false }
        sent += count
    }
    return true
}

// Reads what there is (`wait`: block up to the time limit of the socket). Plain sockets and TLS answer the same way.
streamRecv :: proc(stream: ^Stream, buffer: []u8, wait: bool) -> (count: int, status: StreamStatus) {
    if stream.secure {
        read: int = p2p.TlsRead(&stream.tls, buffer, wait)
        if read < 0 { return 0, .CLOSED }
        if read == 0 { return 0, .NONE }
        return read, .OK
    }
    if stream.polling && wait {
        start: time.Tick = time.tick_now()
        for {
            received, error := net.recv_tcp(stream.socket, buffer)
            if error == .Would_Block || error == .Timeout {
                if time.tick_since(start) > stream.timeout { return 0, .NONE }
                StreamIdle(StreamIdleUser)
                time.sleep(time.Millisecond)
                continue
            }
            if error != nil { return received, .OK if received > 0 else .CLOSED }
            if received == 0 { return 0, .CLOSED }
            return received, .OK
        }
    }
    received, error := net.recv_tcp(stream.socket, buffer)
    if error == .Would_Block || error == .Timeout { return received, .OK if received > 0 else .NONE }
    if error != nil { return received, .OK if received > 0 else .CLOSED }
    if received == 0 { return 0, .CLOSED }
    return received, .OK
}

// A plain socket that a game polls: after this `streamRecv(wait = false)` returns at once
streamNonBlocking :: proc(stream: ^Stream) {
    net.set_blocking(stream.socket, false)
}
