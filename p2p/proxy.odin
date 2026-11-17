#+build !js
// Outgoing TCP through an HTTP proxy (the CONNECT method), for the relay connection (TLS to DERP on port 443) and the relay list fetch.
//
// Many company and school networks only let a browser out through a proxy. The proxy is taken from the usual environment variables,
// HTTPS_PROXY / https_proxy / ALL_PROXY / all_proxy ("http://[user:password@]host:port", Basic authentication only), and NO_PROXY /
// no_proxy (a comma separated list of names or ".suffix"s that go direct, "*" = everything). The proxy sees only the name and the port
// that is asked for; what flows through is the TLS connection of the relay, which the proxy cannot read, and the packets inside it are
// sealed on top of that.
//
// Not covered: SOCKS and HTTPS proxies, NTLM / Kerberos authentication, and anything that is not TCP. The direct UDP path (STUN, hole
// punching) cannot go through a proxy: behind one only the relay works, which is what the relay is for.
package p2p

import "core:encoding/base64"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:thread"
import "core:time"

PROXY_TIMEOUT_MS :: 8000

// The proxy URL from the environment, "" when there is none (or it is switched off for `host`).
ProxyFromEnv :: proc(host: string, allocator := context.temp_allocator) -> string {
    for name in ([?]string{"HTTPS_PROXY", "https_proxy", "ALL_PROXY", "all_proxy"}) {
        value: string = os.get_env(name, allocator)
        if value != "" {
            for bypass_name in ([?]string{"NO_PROXY", "no_proxy"}) {
                if ProxyBypass(os.get_env(bypass_name, allocator), host) {
                    return ""
                }
            }
            return value
        }
    }
    return ""
}

// Is `host` on the NO_PROXY list?
ProxyBypass :: proc(list: string, host: string) -> bool {
    rest: string = list
    for entry in strings.split_iterator(&rest, ",") {
        item: string = strings.trim_space(entry)
        switch {
        case item == "":
        case item == "*":
            return true
        case item[0] == '.':
            if strings.has_suffix(host, item) || host == item[1:] {
                return true
            }
        case host == item || strings.has_suffix(host, strings.concatenate({".", item}, context.temp_allocator)):
            return true
        }
    }
    return false
}

// "http://user:pass@host:3128/" -> its parts, views into `url`. A missing scheme counts as http, a missing port as 3128.
ProxyParse :: proc(url: string) -> (host: string, port: int, userinfo: string, ok: bool) {
    rest: string = url
    if at := strings.index(rest, "://"); at >= 0 {
        if rest[:at] != "http" {
            return                                           // https://, socks5://: not supported
        }
        rest = rest[at + 3:]
    }
    if slash := strings.index_byte(rest, '/'); slash >= 0 {
        rest = rest[:slash]
    }
    if at := strings.last_index_byte(rest, '@'); at >= 0 {
        userinfo = rest[:at]
        rest = rest[at + 1:]
    }
    port = 3128
    if colon := strings.last_index_byte(rest, ':'); colon >= 0 {
        number, number_ok := strconv.parse_int(rest[colon + 1:])
        if !number_ok || number < 1 || number > 65535 {
            return
        }
        port = number
        rest = rest[:colon]
    }
    host = rest
    ok = host != ""
    return
}

// A TCP connection to host:port, through the proxy of the environment when there is one. On failure `error` says what and where.
TcpDial :: proc(host: string, port: int) -> (socket: net.TCP_Socket, error: string, ok: bool) {
    return TcpDialVia(ProxyFromEnv(host), host, port)
}

// The same through the given proxy URL ("" = direct).
TcpDialVia :: proc(proxy: string, host: string, port: int) -> (socket: net.TCP_Socket, error: string, ok: bool) {
    if proxy == "" {
        direct, dial_error := net.dial_tcp_from_hostname_with_port_override(host, port)
        if dial_error != nil {
            return {}, fmt.aprintf("cannot connect to %s:%d: %v", host, port, dial_error), false
        }
        return direct, "", true
    }
    proxy_host, proxy_port, userinfo, parsed := ProxyParse(proxy)
    if !parsed {
        return {}, fmt.aprintf("the proxy setting \"%s\" is not usable (only http://[user:password@]host:port)", proxy), false
    }
    connection, dial_error := net.dial_tcp_from_hostname_with_port_override(proxy_host, proxy_port)
    if dial_error != nil {
        return {}, fmt.aprintf("cannot connect to the proxy %s:%d: %v", proxy_host, proxy_port, dial_error), false
    }
    net.set_option(connection, .Receive_Timeout, time.Millisecond * PROXY_TIMEOUT_MS)
    net.set_option(connection, .Send_Timeout, time.Millisecond * PROXY_TIMEOUT_MS)
    authorization: string
    if userinfo != "" {
        encoded, _ := base64.encode(transmute([]byte)userinfo, allocator = context.temp_allocator)
        authorization = fmt.tprintf("Proxy-Authorization: Basic %s\r\n", encoded)
    }
    request: string = fmt.tprintf("CONNECT %s:%d HTTP/1.1\r\nHost: %s:%d\r\n%s\r\n", host, port, host, port, authorization)
    if _, send_error := net.send_tcp(connection, transmute([]byte)request); send_error != nil {
        net.close(connection)
        return {}, fmt.aprintf("cannot talk to the proxy %s:%d", proxy_host, proxy_port), false
    }
    // the answer ends at the empty line; the proxy says nothing more until we speak, so nothing of the tunnel is read here
    head: [2048]byte
    length: int
    for length < len(head) && !strings.contains(string(head[:length]), "\r\n\r\n") {
        count, receive_error := net.recv_tcp(connection, head[length:])
        if receive_error != nil || count == 0 {
            net.close(connection)
            return {}, fmt.aprintf("the proxy %s:%d did not answer the CONNECT request", proxy_host, proxy_port), false
        }
        length += count
    }
    status: int = DerpHttpStatus(head[:length])
    if status != 200 {
        net.close(connection)
        reason: string = "refused the connection"
        if status == 407 {
            reason = "wants a user name and password (HTTPS_PROXY=http://user:password@host:port)"
        }
        return {}, fmt.aprintf("the proxy %s:%d %s (HTTP %d)", proxy_host, proxy_port, reason, status), false
    }
    return connection, "", true
}

@(test)
ProxyParseTest :: proc(t: ^testing.T) {
    host, port, userinfo, ok := ProxyParse("http://alice:s3cret@proxy.corp.example:8080/")
    testing.expect(t, ok)
    testing.expect_value(t, host, "proxy.corp.example")
    testing.expect_value(t, port, 8080)
    testing.expect_value(t, userinfo, "alice:s3cret")
    host, port, userinfo, ok = ProxyParse("proxy.corp.example")
    testing.expect(t, ok)
    testing.expect_value(t, port, 3128)
    testing.expect_value(t, userinfo, "")
    _, _, _, ok = ProxyParse("socks5://proxy:1080")
    testing.expect(t, !ok)
    _, _, _, ok = ProxyParse("http://proxy:notaport")
    testing.expect(t, !ok)
    _, _, _, ok = ProxyParse("http://:8080")
    testing.expect(t, !ok)

    testing.expect(t, ProxyBypass("localhost,.corp.example, 10.0.0.1", "localhost"))
    testing.expect(t, ProxyBypass("localhost,.corp.example, 10.0.0.1", "derp.corp.example"))
    testing.expect(t, ProxyBypass("localhost,.corp.example, 10.0.0.1", "10.0.0.1"))
    testing.expect(t, !ProxyBypass("localhost,.corp.example", "derp1.tailscale.com"))
    testing.expect(t, ProxyBypass("*", "anything.example"))
    testing.expect(t, !ProxyBypass("", "anything.example"))
}

ProxyTestServer :: struct {
    listener: net.TCP_Socket,
    request: [512]byte,
    request_length: int,
    answer: string,
    tunnel_text: string,
}

ProxyTestServe :: proc(data: rawptr) {
    server: ^ProxyTestServer = cast(^ProxyTestServer)data
    client, _, accept_error := net.accept_tcp(server.listener)
    if accept_error != nil {
        return
    }
    defer net.close(client)
    net.set_option(client, .Receive_Timeout, time.Second * 3)
    for server.request_length < len(server.request) && !strings.contains(string(server.request[:server.request_length]), "\r\n\r\n") {
        count, error := net.recv_tcp(client, server.request[server.request_length:])
        if error != nil || count == 0 {
            return
        }
        server.request_length += count
    }
    net.send_tcp(client, transmute([]byte)server.answer)
    if server.tunnel_text != "" {
        net.send_tcp(client, transmute([]byte)server.tunnel_text)
    }
    time.sleep(100 * time.Millisecond)
}

// A fake proxy on loopback: the CONNECT request is what a real one would get, the answer decides what the client sees.
ProxyTestRun :: proc(t: ^testing.T, answer: string, userinfo: string) -> (socket: net.TCP_Socket, request: string, error: string, ok: bool, server: ^ProxyTestServer) {
    server = new(ProxyTestServer)
    listener, listen_error := net.listen_tcp({address = net.IP4_Loopback, port = 0})
    testing.expect(t, listen_error == nil)
    server.listener = listener
    server.answer = answer
    server.tunnel_text = "tunnel works" if strings.has_prefix(answer, "HTTP/1.1 200") else ""
    endpoint, _ := net.bound_endpoint(listener)
    worker: ^thread.Thread = thread.create_and_start_with_data(server, ProxyTestServe)
    url: string = fmt.tprintf("http://%s%s:%d", userinfo, "127.0.0.1", endpoint.port)
    socket, error, ok = TcpDialVia(url, "derp.example.test", 443)
    thread.join(worker)
    thread.destroy(worker)
    net.close(listener)
    request = string(server.request[:server.request_length])
    return
}

@(test)
ProxyConnectTest :: proc(t: ^testing.T) {
    socket, request, error, ok, server := ProxyTestRun(t, "HTTP/1.1 200 Connection established\r\n\r\n", "alice:s3cret@")
    defer free(server)
    testing.expect(t, ok)
    testing.expect(t, strings.has_prefix(request, "CONNECT derp.example.test:443 HTTP/1.1\r\n"))
    testing.expect(t, strings.contains(request, "Proxy-Authorization: Basic YWxpY2U6czNjcmV0\r\n"))       // alice:s3cret
    if ok {
        // the bytes after the proxy's header belong to the tunnel and were not eaten
        text: [32]byte
        count, _ := net.recv_tcp(socket, text[:])
        testing.expect_value(t, string(text[:count]), "tunnel works")
        net.close(socket)
    }

    server2: ^ProxyTestServer
    _, _, error, ok, server2 = ProxyTestRun(t, "HTTP/1.1 407 Proxy Authentication Required\r\n\r\n", "")
    defer free(server2)
    testing.expect(t, !ok)
    testing.expect(t, strings.contains(error, "user name and password"))
    delete(error)
    server3: ^ProxyTestServer
    _, _, error, ok, server3 = ProxyTestRun(t, "HTTP/1.1 403 Forbidden\r\n\r\n", "")
    defer free(server3)
    testing.expect(t, !ok)
    testing.expect(t, strings.contains(error, "403"))
    delete(error)
}
