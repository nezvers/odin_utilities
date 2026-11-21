#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

// The little HTTP(S) client that the login needs: discovery, the keys, the token endpoint, the user info. One request on one connection (`Connection: close`), answer into a buffer of the caller,
// no redirects followed (a redirect is what the authorization endpoint answers: the caller reads `location`). https goes through the TLS 1.3 client of p2p (the certificate is checked against the host).
//
// A program that serves the other end in the same thread (a test with a provider of its own, oidc/mock) sets `HttpIdle`: every wait of a request calls it, so the server is stepped meanwhile.

import "core:fmt"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:time"
import "../p2p"

// Per thread, so that a test that steps a provider in its own thread does not touch the requests of another thread.
@(thread_local)
HttpIdle: proc(user: rawptr)
@(thread_local)
HttpIdleUser: rawptr

HTTP_TIMEOUT :: 15 * time.Second

Header :: struct {
    name: string,
    value: string,
}

Response :: struct {
    status: int,
    body: []u8,                 // a slice of the response buffer
    location: string,           // the Location header of a redirect
    content_type: string,
}

Url :: struct {
    secure: bool,
    host: string,
    port: int,
    path: string,               // with the query; "/" when there is none
}

// `https://host:port/path?query`
UrlParse :: proc(url: string) -> (parsed: Url, ok: bool) {
    rest: string = url
    if strings.has_prefix(rest, "https://") {
        parsed.secure = true
        rest = rest[8:]
    } else if strings.has_prefix(rest, "http://") {
        rest = rest[7:]
    } else {
        return {}, false
    }
    slash: int = strings.index_byte(rest, '/')
    authority: string = rest if slash < 0 else rest[:slash]
    parsed.path = "/" if slash < 0 else rest[slash:]
    colon: int = strings.last_index_byte(authority, ':')
    parsed.port = 443 if parsed.secure else 80
    if colon >= 0 && !strings.has_suffix(authority, "]") {
        port, port_ok := strconv.parse_int(authority[colon + 1:])
        if !port_ok { return {}, false }
        parsed.port = port
        authority = authority[:colon]
    }
    parsed.host = authority
    return parsed, parsed.host != ""
}

@(private)
Connection :: struct {
    socket: net.TCP_Socket,
    secure: bool,
    polling: bool,
    tls: p2p.Tls,
}

@(private)
connSend :: proc(connection: ^Connection, bytes: []u8) -> bool {
    if connection.secure { return p2p.TlsWrite(&connection.tls, bytes) }
    sent: int
    start: time.Tick = time.tick_now()
    for sent < len(bytes) {
        count, error := net.send_tcp(connection.socket, bytes[sent:])
        if error == .Would_Block {
            if time.tick_since(start) > HTTP_TIMEOUT { return false }
            if HttpIdle != nil { HttpIdle(HttpIdleUser) }
            time.sleep(time.Millisecond)
            continue
        }
        if error != nil || count <= 0 { return false }
        sent += count
    }
    return true
}

// Reads what there is; `closed` when the other side ended; (0, false) when there is nothing yet at the end of the time limit
@(private)
connRecv :: proc(connection: ^Connection, buffer: []u8) -> (count: int, closed: bool) {
    start: time.Tick = time.tick_now()
    for {
        if connection.secure {
            read: int = p2p.TlsRead(&connection.tls, buffer, true)
            if read < 0 { return 0, true }
            if read > 0 { return read, false }
        } else {
            received, error := net.recv_tcp(connection.socket, buffer)
            if error == nil { return received, received == 0 }
            if error != .Would_Block && error != .Timeout { return received, true }
            if connection.polling && HttpIdle != nil { HttpIdle(HttpIdleUser) }
            if connection.polling { time.sleep(time.Millisecond) }
        }
        if time.tick_since(start) > HTTP_TIMEOUT { return 0, true }
    }
}

// Sends the request and reads the whole answer into `buffer`. `ok` false: no connection, no answer, an answer that does not fit.
Request :: proc(url: string, method: string, headers: []Header, body: []u8, buffer: []u8) -> (response: Response, ok: bool) {
    parsed := UrlParse(url) or_return
    connection: ^Connection = new(Connection)
    defer free(connection)
    socket, dial_error := net.dial_tcp_from_hostname_with_port_override(parsed.host, parsed.port)
    if dial_error != nil { return {}, false }
    defer net.close(socket)
    connection.socket, connection.secure = socket, parsed.secure
    net.set_option(socket, .Receive_Timeout, HTTP_TIMEOUT)
    net.set_option(socket, .Send_Timeout, HTTP_TIMEOUT)
    defer if connection.secure { p2p.TlsClose(&connection.tls) }
    if parsed.secure {
        if !p2p.TlsConnect(&connection.tls, socket, parsed.host) {
            connection.secure = false
            return {}, false
        }
    } else if HttpIdle != nil {
        connection.polling = true
        net.set_blocking(socket, false)
    }

    head: strings.Builder
    strings.builder_init(&head, context.temp_allocator)
    fmt.sbprintf(&head, "%s %s HTTP/1.1\r\nHost: %s:%d\r\nConnection: close\r\nAccept: application/json\r\n", method, parsed.path, parsed.host, parsed.port)
    for header in headers { fmt.sbprintf(&head, "%s: %s\r\n", header.name, header.value) }
    if body != nil || method == "POST" { fmt.sbprintf(&head, "Content-Length: %d\r\n", len(body)) }
    strings.write_string(&head, "\r\n")
    if !connSend(connection, transmute([]u8)strings.to_string(head)) { return {}, false }
    if len(body) > 0 && !connSend(connection, body) { return {}, false }

    length: int
    header_end: int = -1
    for length < len(buffer) {
        count, closed := connRecv(connection, buffer[length:])
        length += count
        if header_end < 0 { header_end = indexOf(buffer[:length], "\r\n\r\n") }
        if header_end >= 0 && complete(buffer[:length], header_end) { break }
        if closed { break }
    }
    if header_end < 0 { return {}, false }
    return parseResponse(buffer[:length], header_end)
}

@(private)
indexOf :: proc(bytes: []u8, needle: string) -> int {
    if len(bytes) < len(needle) { return -1 }
    for i in 0 ..< len(bytes) - len(needle) + 1 {
        if string(bytes[i:i + len(needle)]) == needle { return i }
    }
    return -1
}

@(private)
headerValue :: proc(head: string, name: string) -> string {
    rest: string = head
    for len(rest) > 0 {
        newline: int = strings.index(rest, "\r\n")
        line: string = rest if newline < 0 else rest[:newline]
        rest = "" if newline < 0 else rest[newline + 2:]
        colon: int = strings.index_byte(line, ':')
        if colon > 0 && strings.equal_fold(line[:colon], name) { return strings.trim_space(line[colon + 1:]) }
    }
    return ""
}

// Is the body there in full: by the length that the headers say, the end of the chunks, or (neither) never, until the connection closes
@(private)
complete :: proc(received: []u8, header_end: int) -> bool {
    head: string = string(received[:header_end])
    body: []u8 = received[header_end + 4:]
    if length_text := headerValue(head, "Content-Length"); length_text != "" {
        length, ok := strconv.parse_int(length_text)
        return ok && len(body) >= length
    }
    if strings.equal_fold(headerValue(head, "Transfer-Encoding"), "chunked") { return strings.has_suffix(string(body), "0\r\n\r\n") }
    return false
}

@(private)
parseResponse :: proc(received: []u8, header_end: int) -> (response: Response, ok: bool) {
    head: string = string(received[:header_end])
    first_line_end: int = strings.index(head, "\r\n")
    status_line: string = head if first_line_end < 0 else head[:first_line_end]
    parts: []string = strings.split(status_line, " ", context.temp_allocator)
    if len(parts) < 2 { return {}, false }
    status, status_ok := strconv.parse_int(parts[1])
    if !status_ok { return {}, false }
    response.status = status
    response.location = headerValue(head, "Location")
    response.content_type = headerValue(head, "Content-Type")
    body: []u8 = received[header_end + 4:]
    if strings.equal_fold(headerValue(head, "Transfer-Encoding"), "chunked") {
        // the chunks are put back to back in place
        at: int
        read: int
        for read < len(body) {
            line_end: int = indexOf(body[read:], "\r\n")
            if line_end < 0 { break }
            size, size_ok := strconv.parse_int(string(body[read:read + line_end]), 16)
            if !size_ok || size == 0 { break }
            read += line_end + 2
            if read + size > len(body) { break }
            copy(body[at:], body[read:read + size])
            at += size
            read += size + 2
        }
        body = body[:at]
    } else if length_text := headerValue(head, "Content-Length"); length_text != "" {
        length, length_ok := strconv.parse_int(length_text)
        if length_ok && length <= len(body) { body = body[:length] }
    }
    response.body = body
    return response, true
}

// ---- percent encoding (RFC 3986) and the forms of the token endpoint ---------------------------------------------------------------------------------------------------------

UrlEncode :: proc(text: string, builder: ^strings.Builder) {
    hex: string = "0123456789ABCDEF"
    for i in 0 ..< len(text) {
        c: u8 = text[i]
        switch c {
        case 'A' ..= 'Z', 'a' ..= 'z', '0' ..= '9', '-', '.', '_', '~': strings.write_byte(builder, c)
        case:
            strings.write_byte(builder, '%')
            strings.write_byte(builder, hex[c >> 4])
            strings.write_byte(builder, hex[c & 15])
        }
    }
}

// The value of `name` in a query string (`a=1&b=two%20words`), decoded into `out`; "" when it is not there
QueryValue :: proc(query: string, name: string, out: []u8) -> string {
    rest: string = query
    for len(rest) > 0 {
        amp: int = strings.index_byte(rest, '&')
        pair: string = rest if amp < 0 else rest[:amp]
        rest = "" if amp < 0 else rest[amp + 1:]
        equals: int = strings.index_byte(pair, '=')
        if equals < 0 || pair[:equals] != name { continue }
        value: string = pair[equals + 1:]
        at: int
        for i := 0; i < len(value) && at < len(out); i += 1 {
            if value[i] == '%' && i + 2 < len(value) {
                high, high_ok := strconv.parse_int(value[i + 1:i + 2], 16)
                low, low_ok := strconv.parse_int(value[i + 2:i + 3], 16)
                if high_ok && low_ok {
                    out[at] = u8(high * 16 + low)
                    at += 1
                    i += 2
                    continue
                }
            }
            out[at] = ' ' if value[i] == '+' else value[i]
            at += 1
        }
        return string(out[:at])
    }
    return ""
}

// Builds `a=1&b=2` (values encoded) for a form
FormField :: proc(builder: ^strings.Builder, name: string, value: string) {
    if strings.builder_len(builder^) > 0 { strings.write_byte(builder, '&') }
    strings.write_string(builder, name)
    strings.write_byte(builder, '=')
    UrlEncode(value, builder)
}

// POSTs a form (`application/x-www-form-urlencoded`)
PostForm :: proc(url: string, form: string, buffer: []u8, basic_auth: string = "") -> (response: Response, ok: bool) {
    headers: [3]Header = {{"Content-Type", "application/x-www-form-urlencoded"}, {}, {}}
    count: int = 1
    if basic_auth != "" {
        headers[count] = {"Authorization", basic_auth}
        count += 1
    }
    return Request(url, "POST", headers[:count], transmute([]u8)form, buffer)
}
