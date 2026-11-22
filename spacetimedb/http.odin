package spacetimedb

// A small HTTP/1.1 client over a TCP socket (core:net), enough for the REST side of SpacetimeDB: ping, identities, publishing a module, SQL, calling a reducer. One request on one connection
// (`Connection: close`), blocking with a time limit, the answer read into a buffer of the caller; a body with a Content-Length or a chunked one is understood. Plain `http://` only: a database
// behind TLS: `Endpoint.secure` puts TLS 1.3 under the socket (stream.odin).
//
//     response: [4096]u8
//     result: HttpResult = HttpRequest({host = "127.0.0.1", port = 3000}, .GET, "/v1/ping", nil, nil, response[:])
//     if result.ok && result.status == 200 { ... string(result.body) ... }

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"

HttpMethod :: enum u8 {
    GET,
    POST,
    PUT,
    DELETE,
}

HttpHeader :: struct {
    name: string,
    value: string,
}

Endpoint :: struct {
    host: string,       // an address or a name
    port: int,
    secure: bool,       // https / wss: TLS 1.3 over the socket (the certificate is checked against `host`)
}

HttpResult :: struct {
    ok: bool,           // an answer came and could be read (a status of 404 is an answer)
    status: int,
    body: []u8,         // a slice of the response buffer
    error: string,      // what went wrong when ok is false
}

HTTP_TIMEOUT :: 10 * time.Second

// How many times slower than a quiet computer the device is: every timeout of this library that depends on the speed of the device (a request, the handshake of a websocket, the start of a server,
// a wait for a message) is this many times longer. 1 unless the program sets it; the programs get it from the environment variable ODIN_SLOW (time_scale.odin), e.g. `ODIN_SLOW=3`.
TimeScale: f64 = 1

Scaled :: proc(duration: time.Duration) -> time.Duration {
    return scaledBy(duration, TimeScale)
}

// A scale below 1 does not make a timeout shorter than the one that was chosen
@(private)
scaledBy :: proc(duration: time.Duration, scale: f64) -> time.Duration {
    return time.Duration(f64(duration) * max(scale, 1))
}

// Sends the request and reads the whole answer into `response`. The headers `Host`, `Connection` and `Content-Length` are added. An answer that does not fit in `response` is an error.
HttpRequest :: proc(endpoint: Endpoint, method: HttpMethod, path: string, headers: []HttpHeader, body: []u8, response: []u8, timeout: time.Duration = 0) -> HttpResult {         // 0: HTTP_TIMEOUT, scaled
    stream: Stream
    limit: time.Duration = timeout if timeout > 0 else Scaled(HTTP_TIMEOUT)
    if opened, open_error := streamOpen(&stream, endpoint, limit); !opened { return {error = open_error} }
    defer streamClose(&stream)

    names: [HttpMethod]string = {.GET = "GET", .POST = "POST", .PUT = "PUT", .DELETE = "DELETE"}
    head: strings.Builder
    strings.builder_init(&head, context.temp_allocator)
    fmt.sbprintf(&head, "%s %s HTTP/1.1\r\nHost: %s:%d\r\nConnection: close\r\n", names[method], path, endpoint.host, endpoint.port)
    for header in headers { fmt.sbprintf(&head, "%s: %s\r\n", header.name, header.value) }
    if body != nil || method == .POST || method == .PUT { fmt.sbprintf(&head, "Content-Length: %d\r\n", len(body)) }
    strings.write_string(&head, "\r\n")
    if !streamSend(&stream, transmute([]u8)strings.to_string(head)) || !streamSend(&stream, body) { return {error = "could not send"} }

    length: int
    header_end: int = -1
    for length < len(response) {
        count, status := streamRecv(&stream, response[length:], true)
        if count > 0 { length += count }
        if header_end < 0 { header_end = indexOf(response[:length], "\r\n\r\n") }
        if status != .OK { break }
        if header_end >= 0 && httpComplete(response[:length], header_end) { break }
    }
    if header_end < 0 { return {error = "no answer"} }
    return httpParse(response[:length], header_end)
}

@(private)
indexOf :: proc(bytes: []u8, needle: string) -> int {
    if len(bytes) < len(needle) { return -1 }
    for i in 0 ..< len(bytes) - len(needle) + 1 {
        if string(bytes[i:i + len(needle)]) == needle { return i }
    }
    return -1
}

// The value of a header (the name without case), "" when there is none
@(private)
headerValue :: proc(head: string, name: string) -> string {
    rest: string = head
    for len(rest) > 0 {
        newline: int = strings.index(rest, "\r\n")
        line: string = rest if newline < 0 else rest[:newline]
        rest = "" if newline < 0 else rest[newline + 2:]
        colon: int = strings.index_byte(line, ':')
        if colon < 0 { continue }
        if strings.equal_fold(strings.trim_space(line[:colon]), name) { return strings.trim_space(line[colon + 1:]) }
    }
    return ""
}

// Whether everything the headers announce has arrived (a length, or the last chunk)
@(private)
httpComplete :: proc(received: []u8, header_end: int) -> bool {
    head: string = string(received[:header_end])
    body_start: int = header_end + 4
    if value := headerValue(head, "Content-Length"); value != "" {
        wanted, ok := strconv.parse_int(value)
        return ok && len(received) - body_start >= wanted
    }
    if strings.equal_fold(headerValue(head, "Transfer-Encoding"), "chunked") {
        return strings.has_suffix(string(received[body_start:]), "0\r\n\r\n")
    }
    return false        // until the server closes
}

@(private)
httpParse :: proc(received: []u8, header_end: int) -> HttpResult {
    head: string = string(received[:header_end])
    line_end: int = strings.index(head, "\r\n")
    status_line: string = head if line_end < 0 else head[:line_end]
    parts: []string = strings.split(status_line, " ", context.temp_allocator)
    if len(parts) < 2 { return {error = "bad status line"} }
    status, ok := strconv.parse_int(parts[1])
    if !ok { return {error = "bad status"} }
    body_start: int = header_end + 4
    body: []u8 = received[body_start:]
    if strings.equal_fold(headerValue(head, "Transfer-Encoding"), "chunked") {
        // the chunks are moved together in place: size line, data, CRLF
        out: int
        at: int
        for at < len(body) {
            size_end: int = indexOf(body[at:], "\r\n")
            if size_end < 0 { break }
            size, size_ok := strconv.parse_int(strings.trim_space(string(body[at:at + size_end])), 16)
            if !size_ok { return {error = "bad chunk"} }
            at += size_end + 2
            if size == 0 { break }
            if at + size > len(body) { return {error = "short chunk"} }
            copy(body[out:], body[at:at + size])
            out += size
            at += size + 2
        }
        body = body[:out]
    } else if value := headerValue(head, "Content-Length"); value != "" {
        wanted, length_ok := strconv.parse_int(value)
        if length_ok && wanted <= len(body) { body = body[:wanted] }
    }
    return {ok = true, status = status, body = body}
}
