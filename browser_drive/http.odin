package browser_drive

import "core:fmt"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:time"

HEADER_END :: "\r\n\r\n"

// One GET to a server on this machine, the body of the answer into `buffer` (Chrome lists its tabs at /json this way). The answer is over when the body has the length that the header says (Chrome
// keeps the connection open) or when the stream ends. Returns false for a refused connection, a status other than 200, or an answer that does not fit or does not arrive.
HttpGet :: proc(port: int, path: string, buffer: []u8, timeout_ms: int = 2000) -> (body: string, ok: bool) {
    endpoint, endpoint_ok := net.parse_endpoint(fmt.tprintf("127.0.0.1:%d", port))
    if !endpoint_ok { return }
    socket, dial_error := net.dial_tcp(endpoint)
    if dial_error != nil { return }
    defer net.close(socket)
    request: string = fmt.tprintf("GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\n\r\n", path, port)
    if _, send_error := net.send_tcp(socket, transmute([]u8)request); send_error != nil { return }
    deadline: time.Time = time.time_add(time.now(), time.Duration(timeout_ms) * time.Millisecond)
    length: int
    for length < len(buffer) {
        remaining: time.Duration = time.diff(time.now(), deadline)
        if remaining <= 0 { break }
        net.set_option(socket, .Receive_Timeout, max(remaining, time.Millisecond))
        count, receive_error := net.recv_tcp(socket, buffer[length:])
        if receive_error == .Timeout { continue }
        if receive_error != nil || count == 0 { break }
        length += count
        if httpComplete(string(buffer[:length])) { break }
    }
    answer: string = string(buffer[:length])
    separator: int = strings.index(answer, HEADER_END)
    if separator < 0 || !strings.has_prefix(answer, "HTTP/1.1 200") { return }
    body = answer[separator + len(HEADER_END):]
    return body, true
}

// Has the whole body arrived? Without a Content-Length only the end of the stream says so.
@(private)
httpComplete :: proc(answer: string) -> bool {
    separator: int = strings.index(answer, HEADER_END)
    if separator < 0 { return false }
    lower: string = strings.to_lower(answer[:separator], context.temp_allocator)
    at: int = strings.index(lower, "content-length:")
    if at < 0 { return false }
    digits: string = strings.trim_space(lower[at + len("content-length:"):])
    if end := strings.index(digits, "\r\n"); end >= 0 { digits = digits[:end] }
    expected, ok := strconv.parse_int(digits)
    return ok && len(answer) - (separator + len(HEADER_END)) >= expected
}
