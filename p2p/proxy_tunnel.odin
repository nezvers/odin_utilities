#+build !js
package p2p

import "core:net"
import "core:thread"
import "core:time"

// The TLS connection to an https:// proxy, after the CONNECT, joined to a plain loopback socket: what the caller gets is one end of the
// loopback pair, and a thread of ours copies in both directions between the other end and the TLS connection. Everything that takes a TCP
// socket (the TLS client of the relay, the DERP code that polls it) works unchanged, and TLS goes inside TLS without a second layering in
// tls13.odin. The thread ends, and frees everything, when either side closes.
@(private)
ProxyTunnel :: struct {
    tls: ^Tls,
    upstream: net.TCP_Socket,               // TCP to the proxy, under `tls`
    local: net.TCP_Socket,                  // our end of the loopback pair
}

// `local` is the socket for the caller. The pair is made with a listener of port 0 that is closed again at once, and the accepted
// connection must really come from the socket that was dialed (another program on this computer could connect to the port first).
@(private)
ProxyTunnelStart :: proc(tls: ^Tls, upstream: net.TCP_Socket) -> (local: net.TCP_Socket, ok: bool) {
    listener, listen_error := net.listen_tcp({address = net.IP4_Loopback, port = 0})
    if listen_error != nil {
        return
    }
    defer net.close(listener)
    endpoint, endpoint_error := net.bound_endpoint(listener)
    if endpoint_error != nil {
        return
    }
    caller, dial_error := net.dial_tcp_from_endpoint({address = net.IP4_Loopback, port = endpoint.port})
    if dial_error != nil {
        return
    }
    inner, source, accept_error := net.accept_tcp(listener)
    if accept_error != nil {
        net.close(caller)
        return
    }
    caller_end, caller_error := net.bound_endpoint(caller)
    if caller_error != nil || source.port != caller_end.port {
        net.close(caller)
        net.close(inner)
        return
    }
    net.set_blocking(upstream, false)
    net.set_blocking(inner, false)
    tunnel: ^ProxyTunnel = new(ProxyTunnel)
    tunnel^ = {tls = tls, upstream = upstream, local = inner}
    thread.create_and_start_with_data(tunnel, ProxyTunnelRun, self_cleanup = true)
    return caller, true
}

// Sends everything to a non blocking socket (it may be full for a moment).
@(private)
ProxyTunnelSend :: proc(socket: net.TCP_Socket, data: []byte) -> bool {
    sent: int
    waited: int
    for sent < len(data) {
        count, error := net.send_tcp(socket, data[sent:])
        if error == .Would_Block || error == .Timeout {
            waited += 1
            if waited > 8000 {
                return false
            }
            time.sleep(time.Millisecond)
            continue
        }
        if error != nil || count <= 0 {
            return false
        }
        sent += count
        waited = 0
    }
    return true
}

@(private)
ProxyTunnelRun :: proc(data: rawptr) {
    tunnel: ^ProxyTunnel = cast(^ProxyTunnel)data
    buffer: [16384]byte
    for {
        busy: bool
        count, error := net.recv_tcp(tunnel.local, buffer[:])
        if error != nil && error != .Would_Block && error != .Timeout {
            break
        }
        if error == nil {
            if count == 0 || !TlsWrite(tunnel.tls, buffer[:count]) {
                break
            }
            busy = true
        }
        received: int = TlsRead(tunnel.tls, buffer[:], false)
        if received < 0 {
            break
        }
        if received > 0 {
            if !ProxyTunnelSend(tunnel.local, buffer[:received]) {
                break
            }
            busy = true
        }
        if !busy {
            time.sleep(time.Millisecond)
        }
    }
    TlsClose(tunnel.tls)
    net.close(tunnel.upstream)
    net.close(tunnel.local)
    free(tunnel.tls)
    free(tunnel)
}
