#+build !js
// Outgoing TCP through an HTTP proxy (the CONNECT method) or a SOCKS5 proxy, for the relay connection (TLS to DERP on port 443) and the relay
// list fetch.
//
// Many company and school networks only let a browser out through a proxy. The proxy is taken from the usual environment variables,
// HTTPS_PROXY / https_proxy / ALL_PROXY / all_proxy ("http://[user:password@]host:port", Basic authentication only; or
// "socks5://[user:password@]host:port", also "socks5h://": the name is always sent to the proxy, which resolves it), and NO_PROXY /
// no_proxy (a comma separated list of names or ".suffix"s that go direct, "*" = everything). The proxy sees only the name and the port
// that is asked for; what flows through is the TLS connection of the relay, which the proxy cannot read, and the packets inside it are
// sealed on top of that.
//
// Not covered: HTTPS proxies (TLS to the proxy itself), SOCKS4, NTLM / Kerberos authentication, and anything that is not TCP. The direct UDP path (STUN, hole
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

// "http://user:pass@host:3128/" -> its parts, views into `url`. A missing scheme counts as http, a missing port as 3128 (socks5: 1080).
ProxyParse :: proc(url: string) -> (host: string, port: int, userinfo: string, socks: bool, ok: bool) {
    rest: string = url
    if at := strings.index(rest, "://"); at >= 0 {
        switch rest[:at] {
        case "http":
        case "socks5", "socks5h":
            socks = true
        case:
            return                                           // https:// and socks4:// are not supported
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
    port = 1080 if socks else 3128
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
    proxy_host, proxy_port, userinfo, socks, parsed := ProxyParse(proxy)
    if !parsed {
        return {}, fmt.aprintf("the proxy setting \"%s\" is not usable (only http:// or socks5://, [user:password@]host:port)", proxy), false
    }
    connection, dial_error := net.dial_tcp_from_hostname_with_port_override(proxy_host, proxy_port)
    if dial_error != nil {
        return {}, fmt.aprintf("cannot connect to the proxy %s:%d: %v", proxy_host, proxy_port, dial_error), false
    }
    net.set_option(connection, .Receive_Timeout, time.Millisecond * PROXY_TIMEOUT_MS)
    net.set_option(connection, .Send_Timeout, time.Millisecond * PROXY_TIMEOUT_MS)
    if socks {
        if socks_error, socks_ok := ProxySocks5(connection, userinfo, host, port); !socks_ok {
            net.close(connection)
            return {}, fmt.aprintf("the SOCKS5 proxy %s:%d %s", proxy_host, proxy_port, socks_error), false
        }
        return connection, "", true
    }
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

// Exactly `out` bytes from the proxy (RFC 1928 answers have fixed sizes).
@(private)
ProxyReadExact :: proc(connection: net.TCP_Socket, out: []byte) -> bool {
    got: int
    for got < len(out) {
        count, error := net.recv_tcp(connection, out[got:])
        if error != nil || count == 0 {
            return false
        }
        got += count
    }
    return true
}

// SOCKS5 (RFC 1928) with no authentication or user name and password (RFC 1929), CONNECT to a domain name. `reason` says what went wrong,
// to be put after "the SOCKS5 proxy host:port".
ProxySocks5 :: proc(connection: net.TCP_Socket, userinfo: string, host: string, port: int) -> (reason: string, ok: bool) {
    user, password: string
    if userinfo != "" {
        user = userinfo
        if colon := strings.index_byte(userinfo, ':'); colon >= 0 {
            user, password = userinfo[:colon], userinfo[colon + 1:]
        }
        if len(user) > 255 || len(password) > 255 {
            return "cannot use such a long user name or password", false
        }
    }
    if len(host) == 0 || len(host) > 255 {
        return "cannot be asked for such a name", false
    }
    // greeting: the methods we can do (no authentication, and user name and password when we have them)
    greeting: [4]byte = {5, 1, 0, 0}
    length: int = 3
    if userinfo != "" {
        greeting = {5, 2, 0, 2}
        length = 4
    }
    if _, error := net.send_tcp(connection, greeting[:length]); error != nil {
        return "did not take the request", false
    }
    choice: [2]byte
    if !ProxyReadExact(connection, choice[:]) || choice[0] != 5 {
        return "did not answer like a SOCKS5 proxy", false
    }
    switch choice[1] {
    case 0:
    case 2:
        if userinfo == "" {
            return "wants a user name and password (ALL_PROXY=socks5://user:password@host:port)", false
        }
        login: [3 + 255 + 255]byte
        at: int = 0
        login[at] = 1
        login[at + 1] = u8(len(user))
        at += 2
        at += copy(login[at:], user)
        login[at] = u8(len(password))
        at += 1
        at += copy(login[at:], password)
        if _, error := net.send_tcp(connection, login[:at]); error != nil {
            return "did not take the login", false
        }
        verdict: [2]byte
        if !ProxyReadExact(connection, verdict[:]) || verdict[1] != 0 {
            return "refused the user name and password", false
        }
    case:
        return "wants a way of logging in that this client does not know", false
    }
    // the request: CONNECT, name, port
    request: [7 + 255]byte
    request[0], request[1], request[2], request[3], request[4] = 5, 1, 0, 3, u8(len(host))
    at: int = 5
    at += copy(request[at:], host)
    request[at] = u8(port >> 8)
    request[at + 1] = u8(port)
    at += 2
    if _, error := net.send_tcp(connection, request[:at]); error != nil {
        return "did not take the request", false
    }
    answer: [4]byte
    if !ProxyReadExact(connection, answer[:]) || answer[0] != 5 {
        return "did not answer like a SOCKS5 proxy", false
    }
    if answer[1] != 0 {
        text: string
        switch answer[1] {
        case 2:
            text = "does not allow this connection"
        case 3, 4:
            text = "cannot reach the network or the host"
        case 5:
            text = "was refused by the destination"
        case 6:
            text = "reports that the connection timed out"
        case 7, 8:
            text = "cannot do what was asked"
        case:
            text = "failed"
        }
        return fmt.tprintf("%s (SOCKS code %d)", text, answer[1]), false          // copied into the caller's message right away
    }
    // the address the proxy bound: not needed, but it is in the stream before the tunnel starts
    rest: int
    switch answer[3] {
    case 1:
        rest = 4 + 2
    case 4:
        rest = 16 + 2
    case 3:
        size: [1]byte
        if !ProxyReadExact(connection, size[:]) {
            return "did not finish its answer", false
        }
        rest = int(size[0]) + 2
    case:
        return "did not answer like a SOCKS5 proxy", false
    }
    skip: [257]byte
    if !ProxyReadExact(connection, skip[:rest]) {
        return "did not finish its answer", false
    }
    return "", true
}

@(test)
ProxyParseTest :: proc(t: ^testing.T) {
    host, port, userinfo, socks, ok := ProxyParse("http://alice:s3cret@proxy.corp.example:8080/")
    testing.expect(t, ok && !socks)
    testing.expect_value(t, host, "proxy.corp.example")
    testing.expect_value(t, port, 8080)
    testing.expect_value(t, userinfo, "alice:s3cret")
    host, port, userinfo, socks, ok = ProxyParse("proxy.corp.example")
    testing.expect(t, ok)
    testing.expect_value(t, port, 3128)
    testing.expect_value(t, userinfo, "")
    host, port, userinfo, socks, ok = ProxyParse("socks5h://bob:pw@proxy")
    testing.expect(t, ok && socks)
    testing.expect_value(t, port, 1080)
    testing.expect_value(t, userinfo, "bob:pw")
    _, _, _, _, ok = ProxyParse("socks4://proxy:1080")
    testing.expect(t, !ok)
    _, _, _, _, ok = ProxyParse("https://proxy:443")
    testing.expect(t, !ok)
    _, _, _, _, ok = ProxyParse("http://proxy:notaport")
    testing.expect(t, !ok)
    _, _, _, _, ok = ProxyParse("http://:8080")
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

SocksTestServer :: struct {
    listener: net.TCP_Socket,
    wants_login: bool,
    reply_code: u8,
    login: [64]byte,
    login_length: int,
    request: [300]byte,
    request_length: int,
}

// A SOCKS5 server on loopback for one connection: the greeting, the login when it wants one, the CONNECT request, then a fixed answer.
SocksTestServe :: proc(data: rawptr) {
    server: ^SocksTestServer = cast(^SocksTestServer)data
    client, _, accept_error := net.accept_tcp(server.listener)
    if accept_error != nil {
        return
    }
    defer net.close(client)
    net.set_option(client, .Receive_Timeout, time.Second * 3)
    head: [2]byte
    if !ProxyReadExact(client, head[:]) {
        return
    }
    methods: [255]byte
    ProxyReadExact(client, methods[:head[1]])
    if server.wants_login {
        net.send_tcp(client, []byte{5, 2})
        header: [2]byte
        ProxyReadExact(client, header[:1])
        ProxyReadExact(client, header[:1])             // the length of the user name
        user_length: int = int(header[0])
        ProxyReadExact(client, server.login[:user_length])
        ProxyReadExact(client, header[:1])             // the length of the password
        password_length: int = int(header[0])
        ProxyReadExact(client, server.login[user_length:user_length + password_length])
        server.login_length = user_length + password_length
        net.send_tcp(client, []byte{1, 0})
    } else {
        net.send_tcp(client, []byte{5, 0})
    }
    request: [4]byte
    if !ProxyReadExact(client, request[:]) {
        return
    }
    size: [1]byte
    ProxyReadExact(client, size[:])
    ProxyReadExact(client, server.request[:int(size[0]) + 2])
    server.request_length = int(size[0]) + 2
    net.send_tcp(client, []byte{5, server.reply_code, 0, 1, 127, 0, 0, 1, 0x1f, 0x90})
    if server.reply_code == 0 {
        net.send_tcp(client, transmute([]byte)string("tunnel works"))
    }
    time.sleep(100 * time.Millisecond)
}

SocksTestRun :: proc(t: ^testing.T, userinfo: string, wants_login: bool, reply_code: u8) -> (socket: net.TCP_Socket, error: string, ok: bool, server: ^SocksTestServer) {
    server = new(SocksTestServer)
    listener, listen_error := net.listen_tcp({address = net.IP4_Loopback, port = 0})
    testing.expect(t, listen_error == nil)
    server.listener = listener
    server.wants_login = wants_login
    server.reply_code = reply_code
    endpoint, _ := net.bound_endpoint(listener)
    worker: ^thread.Thread = thread.create_and_start_with_data(server, SocksTestServe)
    url: string = fmt.tprintf("socks5://%s127.0.0.1:%d", userinfo, endpoint.port)
    socket, error, ok = TcpDialVia(url, "derp.example.test", 443)
    thread.join(worker)
    thread.destroy(worker)
    net.close(listener)
    return
}

@(test)
ProxySocks5Test :: proc(t: ^testing.T) {
    // no login: the name and the port arrive as asked, and the bytes after the answer belong to the tunnel
    socket, error, ok, server := SocksTestRun(t, "", false, 0)
    defer free(server)
    testing.expect(t, ok, error)
    testing.expect_value(t, string(server.request[:server.request_length]), "derp.example.test\x01\xbb")      // 443 = 0x01bb
    if ok {
        text: [32]byte
        count, _ := net.recv_tcp(socket, text[:])
        testing.expect_value(t, string(text[:count]), "tunnel works")
        net.close(socket)
    }
    // with the login the proxy asks for
    server2: ^SocksTestServer
    socket, error, ok, server2 = SocksTestRun(t, "alice:s3cret@", true, 0)
    defer free(server2)
    testing.expect(t, ok, error)
    testing.expect_value(t, string(server2.login[:server2.login_length]), "alices3cret")
    if ok {
        net.close(socket)
    }
    // a login wanted and none given, and a refusal
    server3: ^SocksTestServer
    _, error, ok, server3 = SocksTestRun(t, "", true, 0)
    defer free(server3)
    testing.expect(t, !ok && strings.contains(error, "user name and password"))
    delete(error)
    server4: ^SocksTestServer
    _, error, ok, server4 = SocksTestRun(t, "", false, 5)
    defer free(server4)
    testing.expect(t, !ok && strings.contains(error, "refused by the destination"))
    delete(error)
}
