#+build !js
// Outgoing TCP through a proxy, for the relay connection (TLS to DERP on port 443) and the relay list fetch.
//
// Many company and school networks only let a browser out through a proxy. The proxy is taken from the usual environment variables,
// HTTPS_PROXY / https_proxy / ALL_PROXY / all_proxy, and NO_PROXY / no_proxy (a comma separated list of names or ".suffix"s that go direct,
// "*" = everything). The URL says which kind it is (the user name and password may be percent encoded, "%5C" is a backslash):
//   http://[user:password@]host[:3128]    CONNECT over plain TCP; Basic, NTLM and Negotiate (Kerberos) logins
//   https://[user:password@]host[:443]    the same CONNECT inside a TLS connection to the proxy (its certificate is checked like a relay's)
//   socks5://, socks5h://                 SOCKS5 (RFC 1928), no login or user name and password; the name is always sent to the proxy
//   socks4://, socks4a://                 SOCKS4 with the name sent to the proxy (SOCKS4a); the user part is the ident name
// Logins for an HTTP(S) proxy: Basic (user:password in the URL); NTLM and Negotiate when the proxy asks for them: with DOMAIN\user:password
// in the URL on every platform (NTLMv2, proxy_ntlm.odin), and on Windows without any credentials in the URL through SSPI with the login of
// the user (Negotiate = Kerberos, falling back to NTLM; proxy_sspi_windows.odin). Kerberos needs Windows: nowhere else is GSSAPI used.
//
// The proxy sees only the name and the port that is asked for; what flows through is the TLS connection of the relay, which the proxy cannot
// read, and the packets inside it are sealed on top of that. Not covered: anything that is not TCP, a PAC file, WPAD. The direct UDP path
// (STUN, hole punching) cannot go through a proxy: behind one only the relay works, which is what the relay is for.
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
PROXY_REPLY_MAX :: 16384                 // the answer of a proxy to a CONNECT: its head, and the start of the body

ProxyKind :: enum {
    HTTP,
    HTTPS,
    SOCKS4,
    SOCKS5,
}

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

// "http://user:pass@host:3128/" -> its parts, views into `url`. A missing scheme counts as http, a missing port as the usual one of the
// kind (http 3128, https 443, socks 1080).
ProxyParse :: proc(url: string) -> (host: string, port: int, userinfo: string, kind: ProxyKind, ok: bool) {
    rest: string = url
    if at := strings.index(rest, "://"); at >= 0 {
        switch rest[:at] {
        case "http":
        case "https":
            kind = .HTTPS
        case "socks5", "socks5h":
            kind = .SOCKS5
        case "socks4", "socks4a":
            kind = .SOCKS4
        case:
            return
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
    switch kind {
    case .HTTP:
        port = 3128
    case .HTTPS:
        port = 443
    case .SOCKS4, .SOCKS5:
        port = 1080
    }
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

// %XX in a user name or password of a URL.
ProxyUnescape :: proc(text: string, allocator := context.temp_allocator) -> string {
    if !strings.contains_rune(text, '%') {
        return text
    }
    out: [dynamic]byte
    out.allocator = allocator
    i: int
    for i < len(text) {
        if text[i] == '%' && i + 2 < len(text) {
            value, value_ok := strconv.parse_int(text[i + 1:i + 3], 16)
            if value_ok {
                append(&out, u8(value))
                i += 3
                continue
            }
        }
        append(&out, text[i])
        i += 1
    }
    return string(out[:])
}

// A TCP connection to host:port, through the proxy of the environment when there is one. On failure `error` says what and where.
TcpDial :: proc(host: string, port: int) -> (socket: net.TCP_Socket, error: string, ok: bool) {
    return TcpDialVia(ProxyFromEnv(host), host, port)
}

// The same through the given proxy URL ("" = direct). Through an https:// proxy the socket is one end of a loopback connection that a
// thread of ours joins to the TLS connection of the proxy (proxy_tunnel.odin): the caller sees an ordinary TCP socket.
TcpDialVia :: proc(proxy: string, host: string, port: int) -> (socket: net.TCP_Socket, error: string, ok: bool) {
    if proxy == "" {
        direct, dial_error := net.dial_tcp_from_hostname_with_port_override(host, port)
        if dial_error != nil {
            return {}, fmt.aprintf("cannot connect to %s:%d: %v", host, port, dial_error), false
        }
        return direct, "", true
    }
    proxy_host, proxy_port, userinfo, kind, parsed := ProxyParse(proxy)
    if !parsed {
        return {}, fmt.aprintf("the proxy setting \"%s\" is not usable (http://, https://, socks5:// or socks4://, [user:password@]host[:port])", proxy), false
    }
    connection, dial_error := net.dial_tcp_from_hostname_with_port_override(proxy_host, proxy_port)
    if dial_error != nil {
        return {}, fmt.aprintf("cannot connect to the proxy %s:%d: %v", proxy_host, proxy_port, dial_error), false
    }
    net.set_option(connection, .Receive_Timeout, time.Millisecond * PROXY_TIMEOUT_MS)
    net.set_option(connection, .Send_Timeout, time.Millisecond * PROXY_TIMEOUT_MS)
    credentials: string = ProxyUnescape(userinfo)
    label: string = fmt.tprintf("%s:%d", proxy_host, proxy_port)
    switch kind {
    case .SOCKS5:
        if reason, socks_ok := ProxySocks5(connection, credentials, host, port); !socks_ok {
            net.close(connection)
            return {}, fmt.aprintf("the SOCKS5 proxy %s %s", label, reason), false
        }
        return connection, "", true
    case .SOCKS4:
        if reason, socks_ok := ProxySocks4(connection, credentials, host, port); !socks_ok {
            net.close(connection)
            return {}, fmt.aprintf("the SOCKS4 proxy %s %s", label, reason), false
        }
        return connection, "", true
    case .HTTP:
        io: ProxyIo = {socket = connection}
        if connect_error, connect_ok := ProxyHttpConnect(&io, label, proxy_host, credentials, host, port); !connect_ok {
            net.close(connection)
            return {}, connect_error, false
        }
        return connection, "", true
    case .HTTPS:
        tls: ^Tls = new(Tls)
        if !TlsConnect(tls, connection, proxy_host) {
            net.close(connection)
            error = fmt.aprintf("cannot make a TLS connection to the proxy %s: %s (an https:// proxy with its own authority needs P2P_CA_FILE=<pem file>)", label, tls.failure)
            free(tls)
            return {}, error, false
        }
        io: ProxyIo = {socket = connection, tls = tls}
        if connect_error, connect_ok := ProxyHttpConnect(&io, label, proxy_host, credentials, host, port); !connect_ok {
            TlsClose(tls)
            net.close(connection)
            free(tls)
            return {}, connect_error, false
        }
        local, tunnel_ok := ProxyTunnelStart(tls, connection)
        if !tunnel_ok {
            TlsClose(tls)
            net.close(connection)
            free(tls)
            return {}, fmt.aprintf("cannot start the tunnel through the proxy %s", label), false
        }
        return local, "", true
    }
    return
}

// ---------------------------------------------------------------------------------------------------------------- HTTP CONNECT

// The connection to the proxy: plain TCP, or TLS on top of it.
ProxyIo :: struct {
    socket: net.TCP_Socket,
    tls: ^Tls,
}

@(private)
ProxyIoSend :: proc(io: ^ProxyIo, data: []byte) -> bool {
    if io.tls != nil {
        return TlsWrite(io.tls, data)
    }
    _, error := net.send_tcp(io.socket, data)
    return error == nil
}

// At least one byte (blocking, with the receive timeout of the socket), -1 when the connection ended or timed out.
@(private)
ProxyIoRecv :: proc(io: ^ProxyIo, out: []byte) -> int {
    if io.tls != nil {
        count: int = TlsRead(io.tls, out, true)
        return count if count > 0 else -1
    }
    count, error := net.recv_tcp(io.socket, out)
    if error != nil || count <= 0 {
        return -1
    }
    return count
}

// The head of one answer of the proxy (up to the empty line) into `buffer`, and the body that follows it read and thrown away when the
// answer is not the 200: the connection stays for the next request of a login. `head` is a view into `buffer`.
@(private)
ProxyReadReply :: proc(io: ^ProxyIo, buffer: []byte) -> (head: string, status: int, ok: bool) {
    length: int
    end: int = -1
    for end < 0 {
        if length >= len(buffer) {
            return
        }
        count: int = ProxyIoRecv(io, buffer[length:])
        if count < 0 {
            return
        }
        length += count
        end = strings.index(string(buffer[:length]), "\r\n\r\n")
    }
    head = string(buffer[:end])
    status = DerpHttpStatus(buffer[:end + 4])
    if status != 200 {
        lengths: [1]string
        if ProxyHeaders(head, "content-length", lengths[:]) == 1 {
            remaining: int
            if number, number_ok := strconv.parse_int(lengths[0]); number_ok {
                remaining = number - (length - (end + 4))
            }
            scratch: [1024]byte
            for remaining > 0 {
                count: int = ProxyIoRecv(io, scratch[:min(remaining, len(scratch))])
                if count < 0 {
                    return head, status, false
                }
                remaining -= count
            }
        }
    }
    return head, status, true
}

// The values of the header lines called `name` (case does not matter) into `out`; how many there are.
@(private)
ProxyHeaders :: proc(head: string, name: string, out: []string) -> (count: int) {
    rest: string = head
    first: bool = true
    for line in strings.split_lines_iterator(&rest) {
        if first {
            first = false
            continue
        }
        colon: int = strings.index_byte(line, ':')
        if colon > 0 && strings.equal_fold(strings.trim_space(line[:colon]), name) && count < len(out) {
            out[count] = strings.trim_space(line[colon + 1:])
            count += 1
        }
    }
    return
}

// What a Proxy-Authenticate line carries for `scheme`: its token (may be empty), and whether the proxy offers the scheme at all.
@(private)
ProxyChallenge :: proc(challenges: []string, scheme: string) -> (token: string, found: bool) {
    for challenge in challenges {
        space: int = strings.index_byte(challenge, ' ')
        name: string = challenge if space < 0 else challenge[:space]
        if strings.equal_fold(name, scheme) {
            return strings.trim_space(challenge[space + 1:]) if space >= 0 else "", true
        }
    }
    return "", false
}

@(private)
ProxyBase64 :: proc(data: []byte) -> string {
    encoded, _ := base64.encode(data, allocator = context.temp_allocator)
    return encoded
}

// CONNECT host:port through the proxy on `io`, logging in when it asks. Logins in the order of what the proxy offers: Negotiate / NTLM
// (SSPI with the login of the user when no credentials are given on Windows; NTLMv2 by hand with "DOMAIN\user:password"), Basic. `error` is
// the whole message for the caller (allocated).
@(private)
ProxyHttpConnect :: proc(io: ^ProxyIo, label: string, proxy_host: string, userinfo: string, host: string, port: int) -> (error: string, ok: bool) {
    Exchange :: enum {
        NONE,
        NTLM,                            // our own NTLMv2
        SSPI,                            // Windows
    }
    exchange: Exchange
    scheme: string
    stage: int                           // messages of the login sent so far
    sspi: ^SspiState
    defer SspiClose(sspi)
    authorization: string
    basic_sent: bool
    if userinfo != "" && !strings.contains(userinfo, "\\") {
        // the usual case needs no extra round trip: Basic goes with the first request (a domain user is for NTLM, which asks first)
        authorization = fmt.tprintf("Basic %s", ProxyBase64(transmute([]byte)userinfo))
        basic_sent = true
    }
    reply: [PROXY_REPLY_MAX]byte
    for _ in 0 ..< 6 {
        header: string = fmt.tprintf("Proxy-Authorization: %s\r\n", authorization) if authorization != "" else ""
        request: string = fmt.tprintf("CONNECT %s:%d HTTP/1.1\r\nHost: %s:%d\r\nProxy-Connection: Keep-Alive\r\n%s\r\n", host, port, host, port, header)
        if !ProxyIoSend(io, transmute([]byte)request) {
            return fmt.aprintf("cannot talk to the proxy %s", label), false
        }
        head, status, read_ok := ProxyReadReply(io, reply[:])
        if !read_ok {
            if exchange != .NONE {
                return fmt.aprintf("the proxy %s closed the connection during the login (NTLM and Kerberos logins need it kept open)", label), false
            }
            return fmt.aprintf("the proxy %s did not answer the CONNECT request", label), false
        }
        if status == 200 {
            return "", true
        }
        if status != 407 {
            return fmt.aprintf("the proxy %s refused the connection (HTTP %d)", label, status), false
        }
        challenges: [8]string
        count: int = ProxyHeaders(head, "proxy-authenticate", challenges[:])
        offered: []string = challenges[:count]
        switch exchange {
        case .NONE:
            _, has_negotiate := ProxyChallenge(offered, "Negotiate")
            _, has_ntlm := ProxyChallenge(offered, "NTLM")
            _, has_basic := ProxyChallenge(offered, "Basic")
            switch {
            case (has_negotiate || has_ntlm) && userinfo == "" && SSPI_AVAILABLE:
                scheme = "Negotiate" if has_negotiate else "NTLM"
                state, open_ok := SspiOpen(scheme, proxy_host)
                if !open_ok {
                    return fmt.aprintf("the proxy %s wants a Windows login, which could not be started on this computer", label), false
                }
                sspi = state
                token, _, step_ok := SspiStep(sspi, nil)
                defer delete(token)
                if !step_ok || len(token) == 0 {
                    return fmt.aprintf("the proxy %s wants a Windows login, which this computer could not make", label), false
                }
                authorization = fmt.tprintf("%s %s", scheme, ProxyBase64(token))
                exchange = .SSPI
                stage = 1
            case (has_negotiate || has_ntlm) && userinfo != "":
                scheme = "NTLM" if has_ntlm else "Negotiate"
                message: [32]byte
                length: int = NtlmNegotiate(message[:])
                authorization = fmt.tprintf("%s %s", scheme, ProxyBase64(message[:length]))
                exchange = .NTLM
                stage = 1
            case has_negotiate || has_ntlm:
                return fmt.aprintf("the proxy %s wants a Windows login (NTLM / Negotiate): give DOMAIN\\user:password in the proxy URL (Kerberos without a password needs Windows)", label), false
            case has_basic && userinfo != "" && !basic_sent:
                authorization = fmt.tprintf("Basic %s", ProxyBase64(transmute([]byte)userinfo))
                basic_sent = true
            case userinfo != "" && (basic_sent || count > 0):
                return fmt.aprintf("the proxy %s refused the user name and password", label), false
            case:
                return fmt.aprintf("the proxy %s wants a user name and password (HTTPS_PROXY=http://user:password@host:port)", label), false
            }
        case .NTLM:
            token, found := ProxyChallenge(offered, scheme)
            if !found || token == "" || stage >= 2 {
                return fmt.aprintf("the proxy %s refused the user name and password", label), false
            }
            challenge_message, decode_error := base64.decode(token, allocator = context.temp_allocator)
            server_challenge, flags, target_info, parsed := NtlmParseChallenge(challenge_message)
            if decode_error != nil || !parsed {
                return fmt.aprintf("the proxy %s sent an NTLM answer that cannot be read", label), false
            }
            // the server's own clock when it states one (the blob is checked against it), ours otherwise
            file_time: u64 = NtlmServerTime(target_info)
            if file_time == 0 {
                file_time = NtlmNow()
            }
            user, password: string = userinfo, ""
            if colon := strings.index_byte(userinfo, ':'); colon >= 0 {
                user, password = userinfo[:colon], userinfo[colon + 1:]
            }
            message: []byte = NtlmAuthenticate(user, password, server_challenge, flags, target_info, NtlmRandom(), file_time, context.temp_allocator)
            authorization = fmt.tprintf("%s %s", scheme, ProxyBase64(message))
            stage = 2
        case .SSPI:
            token, found := ProxyChallenge(offered, scheme)
            if !found || token == "" || stage >= 4 {
                return fmt.aprintf("the proxy %s did not accept the Windows login", label), false
            }
            server_token, decode_error := base64.decode(token, allocator = context.temp_allocator)
            if decode_error != nil {
                return fmt.aprintf("the proxy %s sent a token that cannot be read", label), false
            }
            output, _, step_ok := SspiStep(sspi, server_token)
            defer delete(output)
            if !step_ok || len(output) == 0 {
                return fmt.aprintf("the proxy %s did not accept the Windows login", label), false
            }
            authorization = fmt.tprintf("%s %s", scheme, ProxyBase64(output))
            stage += 1
        }
    }
    return fmt.aprintf("the proxy %s kept asking for a login", label), false
}

// ---------------------------------------------------------------------------------------------------------------- SOCKS4

// SOCKS4 with the name sent to the proxy (SOCKS4a), or the address when `host` is one. The user part of the URL is the ident name.
ProxySocks4 :: proc(connection: net.TCP_Socket, userinfo: string, host: string, port: int) -> (reason: string, ok: bool) {
    ident: string = userinfo
    if colon := strings.index_byte(userinfo, ':'); colon >= 0 {
        ident = userinfo[:colon]
    }
    if len(ident) > 255 || len(host) == 0 || len(host) > 255 {
        return "cannot be asked for such a name", false
    }
    request: [8 + 256 + 256]byte
    request[0], request[1], request[2], request[3] = 4, 1, u8(port >> 8), u8(port)
    at: int = 8
    at += copy(request[at:], ident)
    request[at] = 0
    at += 1
    if address, parsed := net.parse_ip4_address(host); parsed {
        request[4], request[5], request[6], request[7] = address[0], address[1], address[2], address[3]
    } else {
        request[4], request[5], request[6], request[7] = 0, 0, 0, 1           // 0.0.0.x: the name follows (SOCKS4a)
        at += copy(request[at:], host)
        request[at] = 0
        at += 1
    }
    if _, error := net.send_tcp(connection, request[:at]); error != nil {
        return "did not take the request", false
    }
    answer: [8]byte
    if !ProxyReadExact(connection, answer[:]) || answer[0] != 0 {
        return "did not answer like a SOCKS4 proxy", false
    }
    switch answer[1] {
    case 90:
        return "", true
    case 92:
        return "wants the ident program of this computer to answer (SOCKS code 92)", false
    case 93:
        return "says the ident user is not the user name given (SOCKS code 93)", false
    }
    return "rejected or could not make the connection (SOCKS code 91)", false
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
    host, port, userinfo, kind, ok := ProxyParse("http://alice:s3cret@proxy.corp.example:8080/")
    testing.expect(t, ok && kind == .HTTP)
    testing.expect_value(t, host, "proxy.corp.example")
    testing.expect_value(t, port, 8080)
    testing.expect_value(t, userinfo, "alice:s3cret")
    host, port, userinfo, kind, ok = ProxyParse("proxy.corp.example")
    testing.expect(t, ok)
    testing.expect_value(t, port, 3128)
    testing.expect_value(t, userinfo, "")
    host, port, userinfo, kind, ok = ProxyParse("socks5h://bob:pw@proxy")
    testing.expect(t, ok && kind == .SOCKS5)
    testing.expect_value(t, port, 1080)
    testing.expect_value(t, userinfo, "bob:pw")
    host, port, userinfo, kind, ok = ProxyParse("socks4a://proxy")
    testing.expect(t, ok && kind == .SOCKS4)
    testing.expect_value(t, port, 1080)
    host, port, userinfo, kind, ok = ProxyParse("https://alice:pw@proxy.corp.example/")
    testing.expect(t, ok && kind == .HTTPS)
    testing.expect_value(t, port, 443)
    _, _, _, _, ok = ProxyParse("ftp://proxy:21")
    testing.expect(t, !ok)
    testing.expect_value(t, ProxyUnescape("CORP%5Calice"), "CORP\\alice")
    testing.expect_value(t, ProxyUnescape("100%"), "100%")
    testing.expect_value(t, ProxyUnescape("p%2"), "p%2")
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

SocksTest4Server :: struct {
    listener: net.TCP_Socket,
    request: [300]byte,
    length: int,
    code: u8,
}

SocksTest4Serve :: proc(data: rawptr) {
    server: ^SocksTest4Server = cast(^SocksTest4Server)data
    client, _, accept_error := net.accept_tcp(server.listener)
    if accept_error != nil {
        return
    }
    defer net.close(client)
    net.set_option(client, .Receive_Timeout, time.Second * 3)
    // the request ends at the second zero byte of a SOCKS4a request (address 0.0.0.x), at the first of a plain one
    for server.length < len(server.request) {
        count, error := net.recv_tcp(client, server.request[server.length:])
        if error != nil || count <= 0 {
            return
        }
        server.length += count
        zeros: int
        if server.length > 8 {
            for b in server.request[8:server.length] {
                if b == 0 {
                    zeros += 1
                }
            }
            if zeros >= (2 if server.request[4] == 0 else 1) {
                break
            }
        }
    }
    net.send_tcp(client, []byte{0, server.code, 0, 0, 0, 0, 0, 0})
    if server.code == 90 {
        net.send_tcp(client, transmute([]byte)string("tunnel works"))
    }
    time.sleep(100 * time.Millisecond)
}

SocksTest4Run :: proc(t: ^testing.T, code: u8, user: string, host: string) -> (socket: net.TCP_Socket, error: string, ok: bool, server: ^SocksTest4Server) {
    server = new(SocksTest4Server)
    listener, listen_error := net.listen_tcp({address = net.IP4_Loopback, port = 0})
    testing.expect(t, listen_error == nil)
    server.listener = listener
    server.code = code
    endpoint, _ := net.bound_endpoint(listener)
    worker: ^thread.Thread = thread.create_and_start_with_data(server, SocksTest4Serve)
    socket, error, ok = TcpDialVia(fmt.tprintf("socks4a://%s127.0.0.1:%d", user, endpoint.port), host, 443)
    thread.join(worker)
    thread.destroy(worker)
    net.close(listener)
    return
}

@(test)
ProxySocks4Test :: proc(t: ^testing.T) {
    // a name: SOCKS4a (address 0.0.0.1, the name after the ident name)
    socket, error, ok, server := SocksTest4Run(t, 90, "ident:ignored@", "derp.example.test")
    defer free(server)
    testing.expect(t, ok, error)
    testing.expect_value(t, string(server.request[:server.length]), "\x04\x01\x01\xbb\x00\x00\x00\x01ident\x00derp.example.test\x00")
    if ok {
        text: [32]byte
        count, _ := net.recv_tcp(socket, text[:])
        testing.expect_value(t, string(text[:count]), "tunnel works")
        net.close(socket)
    }
    // an address goes as itself, and a refusal is said in words
    server2: ^SocksTest4Server
    _, error, ok, server2 = SocksTest4Run(t, 91, "", "192.0.2.7")
    defer free(server2)
    testing.expect(t, !ok && strings.contains(error, "SOCKS code 91"))
    delete(error)
    testing.expect_value(t, string(server2.request[:server2.length]), "\x04\x01\x01\xbb\xc0\x00\x02\x07\x00")
}

// A proxy that wants a login of the NTLM kind (our own NTLMv2 against the example user) or of the Windows kind (SSPI against this
// computer's accounts), on one connection, with a body on every 407 that has to be read and thrown away.
LoginTestServer :: struct {
    listener: net.TCP_Socket,
    sspi: bool,
    authenticated: bool,
    requests: int,
}

LOGIN_TEST_CHALLENGE :: [8]byte{0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef}
LOGIN_TEST_TIME :: u64(0x01d9_0000_0000_0011)

// The answer of the proxy to one request, and whether the login is complete.
LoginTestAnswer :: proc(server: ^LoginTestServer, authorization: string, sspi_server: rawptr) -> (reply: string) {
    if authorization == "" {
        return "HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Negotiate\r\nProxy-Authenticate: NTLM\r\nContent-Length: 5\r\n\r\nhello"
    }
    space: int = strings.index_byte(authorization, ' ')
    token_bytes, _ := base64.decode(authorization[space + 1:], allocator = context.temp_allocator)
    reply = "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n"
    if server.sspi {
        when ODIN_OS == .Windows {
            output, done, step_ok := SspiServerStep(cast(^SspiServer)sspi_server, token_bytes)
            defer delete(output)
            if step_ok && done {
                server.authenticated = true
                reply = "HTTP/1.1 200 Connection established\r\n\r\n"
            } else if step_ok {
                reply = fmt.tprintf("HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Negotiate %s\r\nContent-Length: 0\r\n\r\n", ProxyBase64(output))
            }
        }
    } else if len(token_bytes) > 8 && token_bytes[8] == 1 {
        // the CHALLENGE of the example, with a timestamp in its target information
        info: [12]byte
        info[0], info[2] = 7, 8
        for i in 0 ..< 8 {
            info[4 + i] = u8(LOGIN_TEST_TIME >> (8 * uint(i)))
        }
        challenge: [48 + len(info)]byte
        copy(challenge[:], NTLM_SIGNATURE)
        challenge[8] = 2
        challenge[20], challenge[21], challenge[22], challenge[23] = 0x05, 0x82, 0x88, 0xA0
        fixed: [8]byte = LOGIN_TEST_CHALLENGE
        copy(challenge[24:], fixed[:])
        challenge[40], challenge[44] = u8(len(info)), 48
        copy(challenge[48:], info[:])
        reply = fmt.tprintf("HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: NTLM %s\r\nContent-Length: 0\r\n\r\n", ProxyBase64(challenge[:]))
    } else if len(token_bytes) > 64 && token_bytes[8] == 3 {
        // the response is checked as the server would: the same proof from the password it knows
        size: int = int(token_bytes[20]) | int(token_bytes[21]) << 8
        offset: int = int(token_bytes[24]) | int(token_bytes[25]) << 8
        response: []byte = token_bytes[offset:offset + size]
        blob: []byte = response[16:]
        file_time: u64
        for i in 0 ..< 8 {
            file_time |= u64(blob[8 + i]) << (8 * uint(i))
        }
        client_challenge: [8]byte
        copy(client_challenge[:], blob[16:24])
        key: [16]byte = NtlmHashV2("alice", "CORP", "s3cret")
        expected: []byte = NtlmResponseV2(key, LOGIN_TEST_CHALLENGE, client_challenge, file_time, blob[28:len(blob) - 4], context.temp_allocator)
        if string(expected) == string(response) && file_time == LOGIN_TEST_TIME {
            server.authenticated = true
            reply = "HTTP/1.1 200 Connection established\r\n\r\n"
        }
    }
    return
}

LoginTestServe :: proc(data: rawptr) {
    server: ^LoginTestServer = cast(^LoginTestServer)data
    client, _, accept_error := net.accept_tcp(server.listener)
    if accept_error != nil {
        return
    }
    defer net.close(client)
    net.set_option(client, .Receive_Timeout, time.Second * 5)
    io: ProxyIo = {socket = client}
    sspi_pointer: rawptr
    when ODIN_OS == .Windows {
        sspi_server: SspiServer
        sspi_ready: bool = server.sspi && SspiServerOpen(&sspi_server)
        sspi_pointer = &sspi_server
        defer if sspi_ready {
            SspiServerClose(&sspi_server)
        }
    }
    request: [4096]byte
    for _ in 0 ..< 6 {
        length: int
        for !strings.contains(string(request[:length]), "\r\n\r\n") {
            count: int = ProxyIoRecv(&io, request[length:])
            if count < 0 {
                return
            }
            length += count
        }
        server.requests += 1
        values: [1]string
        authorization: string
        if ProxyHeaders(string(request[:length]), "proxy-authorization", values[:]) == 1 {
            authorization = values[0]
        }
        reply: string = LoginTestAnswer(server, authorization, sspi_pointer)
        ProxyIoSend(&io, transmute([]byte)reply)
        if server.authenticated {
            time.sleep(50 * time.Millisecond)
            return
        }
    }
}

LoginTestRun :: proc(t: ^testing.T, userinfo: string, sspi: bool) -> (error: string, ok: bool, server: ^LoginTestServer) {
    server = new(LoginTestServer)
    listener, listen_error := net.listen_tcp({address = net.IP4_Loopback, port = 0})
    testing.expect(t, listen_error == nil)
    server.listener = listener
    server.sspi = sspi
    endpoint, _ := net.bound_endpoint(listener)
    worker: ^thread.Thread = thread.create_and_start_with_data(server, LoginTestServe)
    socket: net.TCP_Socket
    socket, error, ok = TcpDialVia(fmt.tprintf("http://%s127.0.0.1:%d", userinfo, endpoint.port), "derp.example.test", 443)
    if ok {
        net.close(socket)
    }
    thread.join(worker)
    thread.destroy(worker)
    net.close(listener)
    return
}

@(test)
ProxyNtlmLoginTest :: proc(t: ^testing.T) {
    // a domain user: no Basic first, NEGOTIATE, the CHALLENGE (with a timestamp), AUTHENTICATE that the server verifies
    error, ok, server := LoginTestRun(t, "CORP%5Calice:s3cret@", false)
    defer free(server)
    testing.expect(t, ok, error)
    testing.expect(t, server.authenticated)
    testing.expect_value(t, server.requests, 3)
    // a wrong password is refused in words
    server2: ^LoginTestServer
    error, ok, server2 = LoginTestRun(t, "CORP%5Calice:wrong@", false)
    defer free(server2)
    testing.expect(t, !ok && strings.contains(error, "refused"))
    delete(error)
    // no credentials, and (outside Windows) no SSPI to ask: the message says what to give
    when ODIN_OS != .Windows {
        server3: ^LoginTestServer
        error, ok, server3 = LoginTestRun(t, "", false)
        defer free(server3)
        testing.expect(t, !ok && strings.contains(error, "DOMAIN"))
        delete(error)
    }
}

// The login of the Windows user through SSPI, with the proxy checking it against the accounts of this computer.
@(test)
ProxySspiLoginTest :: proc(t: ^testing.T) {
    when ODIN_OS == .Windows {
        error, ok, server := LoginTestRun(t, "", true)
        defer free(server)
        testing.expect(t, ok, error)
        testing.expect(t, server.authenticated)
    }
}

// An https:// proxy that is not speaking TLS: the failure says so and nothing hangs or leaks.
@(test)
ProxyHttpsFailureTest :: proc(t: ^testing.T) {
    server := new(ProxyTestServer)
    defer free(server)
    listener, listen_error := net.listen_tcp({address = net.IP4_Loopback, port = 0})
    testing.expect(t, listen_error == nil)
    server.listener = listener
    server.answer = "HTTP/1.1 400 Bad Request\r\n\r\nthis is not TLS"
    endpoint, _ := net.bound_endpoint(listener)
    worker: ^thread.Thread = thread.create_and_start_with_data(server, ProxyTestServe)
    _, error, ok := TcpDialVia(fmt.tprintf("https://127.0.0.1:%d", endpoint.port), "derp.example.test", 443)
    thread.join(worker)
    thread.destroy(worker)
    net.close(listener)
    testing.expect(t, !ok && strings.contains(error, "TLS connection to the proxy"))
    delete(error)
}
