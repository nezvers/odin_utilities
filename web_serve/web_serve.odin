#+build !js
// Static file server for trying a web build (web_build) in a browser: a browser refuses wasm from file://, so bin/web has to be served.
// Small on purpose: GET and HEAD, no keep-alive, every response says Cache-Control: no-store so a rebuilt main.wasm is always fetched.
// Meant for localhost, it listens on the loopback address unless told otherwise.
//
// No hidden allocations: connections, request buffers and the file chunk are fixed arrays inside of `Server`.
// The server never blocks on a client that is slow to send its request: connections are polled, so a browser that opens a
// connection and sends nothing (speculative connects) costs nothing.
//
//     server: web_serve.Server
//     web_serve.ServerInit(&server, {directory = "game/bin/web"})
//     web_serve.ServerRun(&server)                 // or call ServerPoll every frame of your own loop
package web_serve

import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"

MAX_CONNECTIONS :: 16
REQUEST_CAPACITY :: 4096
PATH_CAPACITY :: 1024
CHUNK_CAPACITY :: 64 * 1024
REQUEST_TIMEOUT :: 5 * time.Second

Status :: enum {
    OK = 200,
    BAD_REQUEST = 400,
    FORBIDDEN = 403,
    NOT_FOUND = 404,
    METHOD_NOT_ALLOWED = 405,
}

ServerConfig :: struct {
    directory: string,              // the folder that is served, for a web_build it is <source>/bin/web
    index: string,                  // served for a folder, default "index.html"
    port: int,                      // 0 - any free port, read it from Server.port
    address: net.Address,           // nil - loopback (127.0.0.1). net.IP4_Any makes it reachable from other devices
    cross_origin_isolated: bool,    // send COOP and COEP, needed for SharedArrayBuffer (threads in wasm)
    log: bool,                      // print one line per request
}

Connection :: struct {
    socket: net.TCP_Socket,
    active: bool,
    received: int,
    started: time.Time,
    request: [REQUEST_CAPACITY]u8,
}

Server :: struct {
    config: ServerConfig,
    listener: net.TCP_Socket,
    port: int,
    request_count: int,
    connections: [MAX_CONNECTIONS]Connection,
    path_buffer: [PATH_CAPACITY]u8,
    header_buffer: [1024]u8,
    chunk: [CHUNK_CAPACITY]u8,
}

// Content type by file extension. Wasm has to be application/wasm or browsers refuse to stream-compile it
MimeType :: proc(path: string) -> string {
    dot: int = strings.last_index_byte(path, '.')
    if dot < 0 {
        return "application/octet-stream"
    }
    extension: string = path[dot + 1:]
    switch {
    case strings.equal_fold(extension, "html"), strings.equal_fold(extension, "htm"): return "text/html; charset=utf-8"
    case strings.equal_fold(extension, "js"), strings.equal_fold(extension, "mjs"): return "text/javascript; charset=utf-8"
    case strings.equal_fold(extension, "css"): return "text/css; charset=utf-8"
    case strings.equal_fold(extension, "json"): return "application/json"
    case strings.equal_fold(extension, "wasm"): return "application/wasm"
    case strings.equal_fold(extension, "txt"), strings.equal_fold(extension, "csv"): return "text/plain; charset=utf-8"
    case strings.equal_fold(extension, "png"): return "image/png"
    case strings.equal_fold(extension, "jpg"), strings.equal_fold(extension, "jpeg"): return "image/jpeg"
    case strings.equal_fold(extension, "gif"): return "image/gif"
    case strings.equal_fold(extension, "webp"): return "image/webp"
    case strings.equal_fold(extension, "svg"): return "image/svg+xml"
    case strings.equal_fold(extension, "ico"): return "image/x-icon"
    case strings.equal_fold(extension, "ogg"): return "audio/ogg"
    case strings.equal_fold(extension, "wav"): return "audio/wav"
    case strings.equal_fold(extension, "mp3"): return "audio/mpeg"
    case strings.equal_fold(extension, "ttf"): return "font/ttf"
    case strings.equal_fold(extension, "otf"): return "font/otf"
    case strings.equal_fold(extension, "woff"): return "font/woff"
    case strings.equal_fold(extension, "woff2"): return "font/woff2"
    }
    return "application/octet-stream"
}

StatusText :: proc(status: Status) -> string {
    switch status {
    case .OK: return "OK"
    case .BAD_REQUEST: return "Bad Request"
    case .FORBIDDEN: return "Forbidden"
    case .NOT_FOUND: return "Not Found"
    case .METHOD_NOT_ALLOWED: return "Method Not Allowed"
    }
    return ""
}

// Split the request line "GET /path HTTP/1.1". `complete` is true once the blank line that ends the headers has arrived.
RequestParse :: proc(data: []byte) -> (method: string, target: string, complete: bool, ok: bool) {
    text: string = string(data)
    end: int = strings.index(text, "\r\n\r\n")
    if end < 0 {
        return
    }
    complete = true
    line_end: int = strings.index(text, "\r\n")
    parts: [3]string
    count: int
    line: string = text[:line_end]
    for part in strings.split_iterator(&line, " ") {
        if count < 3 { parts[count] = part }
        count += 1
    }
    if count != 3 || !strings.has_prefix(parts[2], "HTTP/") || len(parts[1]) == 0 {
        return
    }
    return parts[0], parts[1], true, true
}

@(private)
HexValue :: proc(character: u8) -> int {
    switch character {
    case '0' ..= '9': return int(character - '0')
    case 'a' ..= 'f': return int(character - 'a') + 10
    case 'A' ..= 'F': return int(character - 'A') + 10
    }
    return -1
}

// The file that a request target means, built in `buffer`. The query and the fragment are dropped, %XX is decoded, a folder gets the
// index file. Anything that could leave the served folder ("..", backslashes, NUL, a target that doesn't start with "/") is FORBIDDEN.
ResolvePath :: proc(directory: string, index: string, target: string, buffer: []u8) -> (path: string, status: Status) {
    cut: int = len(target)
    for character, i in transmute([]u8)target {
        if character == '?' || character == '#' {
            cut = i
            break
        }
    }
    request: string = target[:cut]
    if len(request) == 0 || request[0] != '/' {
        return "", .BAD_REQUEST
    }

    // decode into the buffer after the directory
    root: string = strings.trim_right(directory, "/\\")
    length: int = copy(buffer, root)
    decoded_start: int = length
    i: int = 0
    for i < len(request) {
        character: u8 = request[i]
        if character == '%' {
            if i + 2 >= len(request) {
                return "", .BAD_REQUEST
            }
            high: int = HexValue(request[i + 1])
            low: int = HexValue(request[i + 2])
            if high < 0 || low < 0 {
                return "", .BAD_REQUEST
            }
            character = u8(high * 16 + low)
            i += 2
        }
        if character == 0 || character == '\\' {
            return "", .FORBIDDEN
        }
        if length >= len(buffer) - len(index) - 2 {
            return "", .BAD_REQUEST
        }
        buffer[length] = character
        length += 1
        i += 1
    }

    decoded: string = string(buffer[decoded_start:length])
    segments: string = decoded
    for segment in strings.split_iterator(&segments, "/") {
        if segment == ".." {
            return "", .FORBIDDEN
        }
    }

    if buffer[length - 1] == '/' {
        length += copy(buffer[length:], index)
    }
    path = string(buffer[:length])
    // a folder without the trailing slash also gets its index
    if os.is_dir(path) {
        buffer[length] = '/'
        length += 1
        length += copy(buffer[length:], index)
        path = string(buffer[:length])
    }
    return path, .OK
}

ServerInit :: proc(server: ^Server, config: ServerConfig) -> bool {
    assert(len(config.directory) > 0)
    server^ = {}
    server.config = config
    if len(server.config.index) == 0 {
        server.config.index = "index.html"
    }
    if server.config.address == nil {
        server.config.address = net.IP4_Loopback
    }

    listener, listen_error := net.listen_tcp({server.config.address, config.port})
    if listen_error != nil {
        return false
    }
    endpoint, endpoint_error := net.bound_endpoint(listener)
    if endpoint_error != nil || net.set_blocking(listener, false) != nil {
        net.close(listener)
        return false
    }
    server.listener = listener
    server.port = endpoint.port
    return true
}

ServerShutdown :: proc(server: ^Server) {
    for &connection in server.connections {
        if connection.active {
            net.close(connection.socket)
        }
    }
    net.close(server.listener)
    server^ = {}
}

// "http://localhost:8000/"
ServerUrl :: proc(server: ^Server, buffer: []u8) -> string {
    return fmt.bprintf(buffer, "http://localhost:%d/", server.port)
}

@(private)
SendAll :: proc(socket: net.TCP_Socket, data: []byte) -> bool {
    sent: int
    for sent < len(data) {
        count, error := net.send_tcp(socket, data[sent:])
        if error != nil || count <= 0 {
            return false
        }
        sent += count
    }
    return true
}

@(private)
SendHeader :: proc(server: ^Server, socket: net.TCP_Socket, status: Status, content_type: string, length: i64) -> bool {
    isolation: string = "Cross-Origin-Opener-Policy: same-origin\r\nCross-Origin-Embedder-Policy: require-corp\r\n" if server.config.cross_origin_isolated else ""
    header: string = fmt.bprintf(server.header_buffer[:],
        "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n%s\r\n",
        int(status), StatusText(status), content_type, length, isolation)
    return SendAll(socket, transmute([]byte)header)
}

@(private)
SendError :: proc(server: ^Server, socket: net.TCP_Socket, status: Status, head_only: bool) {
    body: string = fmt.bprintf(server.chunk[:128], "%d %s", int(status), StatusText(status))
    if SendHeader(server, socket, status, "text/plain; charset=utf-8", i64(len(body))) && !head_only {
        SendAll(socket, transmute([]byte)body)
    }
}

@(private)
Respond :: proc(server: ^Server, socket: net.TCP_Socket, method: string, target: string, valid: bool) -> Status {
    head_only: bool = method == "HEAD"
    status: Status
    if !valid {
        SendError(server, socket, .BAD_REQUEST, false)
        return .BAD_REQUEST
    }
    if method != "GET" && !head_only {
        SendError(server, socket, .METHOD_NOT_ALLOWED, false)
        return .METHOD_NOT_ALLOWED
    }

    path: string
    path, status = ResolvePath(server.config.directory, server.config.index, target, server.path_buffer[:])
    if status != .OK {
        SendError(server, socket, status, head_only)
        return status
    }

    file, open_error := os.open(path)
    if open_error != nil || os.is_dir(path) {
        SendError(server, socket, .NOT_FOUND, head_only)
        return .NOT_FOUND
    }
    defer os.close(file)
    size, size_error := os.file_size(file)
    if size_error != nil {
        SendError(server, socket, .NOT_FOUND, head_only)
        return .NOT_FOUND
    }

    if !SendHeader(server, socket, .OK, MimeType(path), size) || head_only {
        return .OK
    }
    for {
        count, read_error := os.read(file, server.chunk[:])
        if count <= 0 || read_error != nil {
            break
        }
        if !SendAll(socket, server.chunk[:count]) {
            break
        }
    }
    return .OK
}

// Accept new connections and answer every request that has arrived completely. Never blocks. Returns the number of answered requests.
ServerPoll :: proc(server: ^Server) -> int {
    answered: int

    for {
        client, _, accept_error := net.accept_tcp(server.listener)
        if accept_error != nil {
            break
        }
        net.set_blocking(client, false)
        slot: int = -1
        oldest: int = 0
        for connection, i in server.connections {
            if !connection.active {
                slot = i
                break
            }
            if time.diff(connection.started, server.connections[oldest].started) > 0 {
                oldest = i
            }
        }
        if slot < 0 {
            // all slots are busy: the connection that waited longest is dropped
            net.close(server.connections[oldest].socket)
            slot = oldest
        }
        server.connections[slot] = {socket = client, active = true, started = time.now()}
    }

    for &connection in server.connections {
        if !connection.active { continue }

        if connection.received < REQUEST_CAPACITY {
            count, recv_error := net.recv_tcp(connection.socket, connection.request[connection.received:])
            if recv_error == nil && count > 0 {
                connection.received += count
            } else if recv_error == nil || recv_error != .Would_Block {
                // closed by the client or broken
                net.close(connection.socket)
                connection.active = false
                continue
            }
        }

        method, target, complete, ok := RequestParse(connection.request[:connection.received])
        if complete || connection.received >= REQUEST_CAPACITY {
            net.set_blocking(connection.socket, true)
            status: Status = Respond(server, connection.socket, method, target, ok && complete)
            if server.config.log {
                fmt.printfln("%s %s -> %d", method, target, int(status))
            }
            net.close(connection.socket)
            connection.active = false
            server.request_count += 1
            answered += 1
        } else if time.diff(connection.started, time.now()) > REQUEST_TIMEOUT {
            net.close(connection.socket)
            connection.active = false
        }
    }
    return answered
}

// Serve until `stop` becomes true (set it from another thread), or forever when it is nil
ServerRun :: proc(server: ^Server, stop: ^bool = nil) {
    for stop == nil || !stop^ {
        if ServerPoll(server) == 0 {
            time.sleep(2 * time.Millisecond)
        }
    }
}

// Open the page in the default browser
ServerOpenBrowser :: proc(url: string) {
    when ODIN_OS == .Windows {
        command: []string = {"cmd", "/c", "start", "", url}
    } else when ODIN_OS == .Darwin {
        command: []string = {"open", url}
    } else {
        command: []string = {"xdg-open", url}
    }
    _, _, _, _ = os.process_exec({command = command}, context.temp_allocator)
}

// --- Tests ---
// The server tests use real sockets on the loopback address with a free port, nothing leaves the machine.

@(test)
test_mime_types :: proc(t: ^testing.T) {
    testing.expect_value(t, MimeType("bin/web/main.wasm"), "application/wasm")
    testing.expect_value(t, MimeType("index.html"), "text/html; charset=utf-8")
    testing.expect_value(t, MimeType("odin.js"), "text/javascript; charset=utf-8")
    testing.expect_value(t, MimeType("a/b.PNG"), "image/png")
    testing.expect_value(t, MimeType("font.woff2"), "font/woff2")
    testing.expect_value(t, MimeType("no_extension"), "application/octet-stream")
    testing.expect_value(t, MimeType("archive.unknown"), "application/octet-stream")
}

@(test)
test_request_parse :: proc(t: ^testing.T) {
    method, target, complete, ok := RequestParse(transmute([]byte)string("GET /index.html HTTP/1.1\r\nHost: x\r\n\r\n"))
    testing.expect(t, complete && ok)
    testing.expect_value(t, method, "GET")
    testing.expect_value(t, target, "/index.html")

    _, _, partial, partial_ok := RequestParse(transmute([]byte)string("GET /index.html HTTP/1.1\r\nHost: x\r\n"))
    testing.expect(t, !partial && !partial_ok, "the headers have not ended yet")
    _, _, _, bad := RequestParse(transmute([]byte)string("GET only\r\n\r\n"))
    testing.expect(t, !bad, "not a request line")
    _, _, bad_complete, bad_version := RequestParse(transmute([]byte)string("GET / FTP/1.1\r\n\r\n"))
    testing.expect(t, bad_complete && !bad_version)
}

@(test)
test_resolve_path :: proc(t: ^testing.T) {
    buffer: [256]u8
    path, status := ResolvePath("site", "index.html", "/", buffer[:])
    testing.expect_value(t, status, Status.OK)
    testing.expect_value(t, path, "site/index.html")

    path, status = ResolvePath("site/", "index.html", "/dir/file.wasm?v=3#top", buffer[:])
    testing.expect_value(t, status, Status.OK)
    testing.expect_value(t, path, "site/dir/file.wasm")                                   // query and fragment are dropped

    path, status = ResolvePath("site", "index.html", "/my%20file.txt", buffer[:])
    testing.expect_value(t, path, "site/my file.txt")
    testing.expect_value(t, status, Status.OK)

    path, status = ResolvePath("site", "index.html", "/sub/", buffer[:])
    testing.expect_value(t, path, "site/sub/index.html")

    for forbidden in ([]string{"/../secret", "/a/../../secret", "/%2e%2e/secret", "/a/%2E%2E/b", "/a\\b", "/a%5Cb", "/a%00b"}) {
        _, forbidden_status := ResolvePath("site", "index.html", forbidden, buffer[:])
        testing.expectf(t, forbidden_status == .FORBIDDEN, "%s must not resolve", forbidden)
    }
    for bad in ([]string{"", "index.html", "/bad%2", "/bad%zz"}) {
        _, bad_status := ResolvePath("site", "index.html", bad, buffer[:])
        testing.expectf(t, bad_status == .BAD_REQUEST, "%q is a bad request", bad)
    }
    tiny: [8]u8
    _, too_long := ResolvePath("site", "index.html", "/a/very/long/path.txt", tiny[:])
    testing.expect_value(t, too_long, Status.BAD_REQUEST)
}

// every test gets its own folder, the test runner runs them in parallel
@(private="file")
site_counter: int

@(private="file")
TestSite :: struct {
    directory: string,
    server: Server,
}

// A served folder with a few files and a secret next to it, a server on a free port
@(private="file")
make_test_site :: proc(site: ^TestSite, config: ServerConfig = {}) -> bool {
    temp, temp_error := os.temp_directory(context.temp_allocator)
    if temp_error != nil { return false }
    root: string = fmt.tprintf("%s/odin_utilities_web_serve_test_%d", temp, sync.atomic_add(&site_counter, 1))
    os.remove_all(root)
    site.directory = fmt.tprintf("%s/site", root)
    os.make_directory_all(fmt.tprintf("%s/sub", site.directory))
    written: bool = true
    written &&= os.write_entire_file(fmt.tprintf("%s/secret.txt", root), "do not serve") == nil
    written &&= os.write_entire_file(fmt.tprintf("%s/index.html", site.directory), "<html>hello</html>") == nil
    written &&= os.write_entire_file(fmt.tprintf("%s/sub/index.html", site.directory), "<html>sub</html>") == nil
    written &&= os.write_entire_file(fmt.tprintf("%s/my file.txt", site.directory), "spaced") == nil

    // binary data with NUL bytes, bigger than one chunk so that streaming is exercised
    binary := make([]byte, CHUNK_CAPACITY * 3 + 123, context.temp_allocator)
    for &value, i in binary { value = u8(i * 7) }
    written &&= os.write_entire_file(fmt.tprintf("%s/main.wasm", site.directory), binary) == nil

    if !written { return false }
    server_config: ServerConfig = config
    server_config.directory = site.directory
    return ServerInit(&site.server, server_config)
}

@(private="file")
remove_test_site :: proc(site: ^TestSite) {
    ServerShutdown(&site.server)
    os.remove_all(fmt.tprintf("%s/..", site.directory))
}

// Send a request, let the server answer, read until the server closes the connection
@(private="file")
fetch :: proc(site: ^TestSite, request: string) -> []byte {
    client, dial_error := net.dial_tcp(net.IP4_Loopback, site.server.port)
    if dial_error != nil { return nil }
    defer net.close(client)
    net.send_tcp(client, transmute([]byte)request)

    for _ in 0 ..< 200 {
        if ServerPoll(&site.server) > 0 { break }
        time.sleep(time.Millisecond)
    }

    response: [dynamic]byte
    response.allocator = context.temp_allocator
    buffer: [8192]byte
    for {
        count, recv_error := net.recv_tcp(client, buffer[:])
        if count <= 0 || recv_error != nil { break }
        append(&response, ..buffer[:count])
    }
    return response[:]
}

@(private="file")
split_response :: proc(response: []byte) -> (header: string, body: []byte) {
    text: string = string(response)
    end: int = strings.index(text, "\r\n\r\n")
    if end < 0 { return text, nil }
    return text[:end], response[end + 4:]
}

@(test)
test_serves_files_and_folders :: proc(t: ^testing.T) {
    site: TestSite
    if !make_test_site(&site) { testing.fail_now(t, "could not start the server") }
    defer remove_test_site(&site)
    testing.expect(t, site.server.port > 0, "a free port was picked")

    header, body := split_response(fetch(&site, "GET /index.html HTTP/1.1\r\nHost: localhost\r\n\r\n"))
    testing.expect(t, strings.has_prefix(header, "HTTP/1.1 200 OK"))
    testing.expect(t, strings.contains(header, "Content-Type: text/html; charset=utf-8"))
    testing.expect(t, strings.contains(header, "Content-Length: 18"))
    testing.expect(t, strings.contains(header, "Cache-Control: no-store"))
    testing.expect_value(t, string(body), "<html>hello</html>")

    _, root_body := split_response(fetch(&site, "GET / HTTP/1.1\r\n\r\n"))
    testing.expect_value(t, string(root_body), "<html>hello</html>")                      // the folder gets its index
    _, sub_body := split_response(fetch(&site, "GET /sub HTTP/1.1\r\n\r\n"))
    testing.expect_value(t, string(sub_body), "<html>sub</html>")                         // also without the trailing slash
    _, spaced_body := split_response(fetch(&site, "GET /my%20file.txt?x=1 HTTP/1.1\r\n\r\n"))
    testing.expect_value(t, string(spaced_body), "spaced")
}

@(test)
test_serves_wasm_in_chunks :: proc(t: ^testing.T) {
    site: TestSite
    if !make_test_site(&site) { testing.fail_now(t, "could not start the server") }
    defer remove_test_site(&site)

    header, body := split_response(fetch(&site, "GET /main.wasm HTTP/1.1\r\n\r\n"))
    testing.expect(t, strings.contains(header, "Content-Type: application/wasm"))
    expected_length: int = CHUNK_CAPACITY * 3 + 123
    testing.expect(t, strings.contains(header, fmt.tprintf("Content-Length: %d", expected_length)))
    testing.expect_value(t, len(body), expected_length)
    identical: bool = len(body) == expected_length
    for value, i in body {
        if value != u8(i * 7) {
            identical = false
            break
        }
    }
    testing.expect(t, identical, "every byte arrived, including the NUL bytes and the chunk borders")
}

@(test)
test_refuses_what_it_should_not_serve :: proc(t: ^testing.T) {
    site: TestSite
    if !make_test_site(&site) { testing.fail_now(t, "could not start the server") }
    defer remove_test_site(&site)

    header, _ := split_response(fetch(&site, "GET /missing.html HTTP/1.1\r\n\r\n"))
    testing.expect(t, strings.has_prefix(header, "HTTP/1.1 404 Not Found"))

    for attempt in ([]string{"/../secret.txt", "/%2e%2e/secret.txt", "/sub/../../secret.txt"}) {
        forbidden_header, forbidden_body := split_response(fetch(&site, fmt.tprintf("GET %s HTTP/1.1\r\n\r\n", attempt)))
        testing.expectf(t, strings.has_prefix(forbidden_header, "HTTP/1.1 403"), "%s is forbidden", attempt)
        testing.expectf(t, !strings.contains(string(forbidden_body), "do not serve"), "%s does not leak the file", attempt)
    }

    post_header, _ := split_response(fetch(&site, "POST /index.html HTTP/1.1\r\n\r\n"))
    testing.expect(t, strings.has_prefix(post_header, "HTTP/1.1 405"))
    bad_header, _ := split_response(fetch(&site, "nonsense\r\n\r\n"))
    testing.expect(t, strings.has_prefix(bad_header, "HTTP/1.1 400"))

    head_header, head_body := split_response(fetch(&site, "HEAD /index.html HTTP/1.1\r\n\r\n"))
    testing.expect(t, strings.has_prefix(head_header, "HTTP/1.1 200"))
    testing.expect(t, strings.contains(head_header, "Content-Length: 18"), "HEAD reports the size")
    testing.expect_value(t, len(head_body), 0)
}

@(test)
test_idle_connection_does_not_block_others :: proc(t: ^testing.T) {
    site: TestSite
    if !make_test_site(&site) { testing.fail_now(t, "could not start the server") }
    defer remove_test_site(&site)

    // a browser can open a connection and send nothing
    idle, idle_error := net.dial_tcp(net.IP4_Loopback, site.server.port)
    testing.expect_value(t, idle_error, nil)
    defer net.close(idle)
    ServerPoll(&site.server)

    _, body := split_response(fetch(&site, "GET /index.html HTTP/1.1\r\n\r\n"))
    testing.expect_value(t, string(body), "<html>hello</html>")
}

@(test)
test_cross_origin_isolation_headers :: proc(t: ^testing.T) {
    site: TestSite
    if !make_test_site(&site, {cross_origin_isolated = true}) { testing.fail_now(t, "could not start the server") }
    defer remove_test_site(&site)
    header, _ := split_response(fetch(&site, "GET /index.html HTTP/1.1\r\n\r\n"))
    testing.expect(t, strings.contains(header, "Cross-Origin-Opener-Policy: same-origin"))
    testing.expect(t, strings.contains(header, "Cross-Origin-Embedder-Policy: require-corp"))

    plain: TestSite
    if !make_test_site(&plain) { testing.fail_now(t, "could not start the server") }
    defer remove_test_site(&plain)
    plain_header, _ := split_response(fetch(&plain, "GET /index.html HTTP/1.1\r\n\r\n"))
    testing.expect(t, !strings.contains(plain_header, "Cross-Origin"), "off unless asked for")
}

@(test)
test_url_and_run_stops :: proc(t: ^testing.T) {
    site: TestSite
    if !make_test_site(&site) { testing.fail_now(t, "could not start the server") }
    defer remove_test_site(&site)

    buffer: [64]u8
    testing.expect_value(t, ServerUrl(&site.server, buffer[:]), fmt.tprintf("http://localhost:%d/", site.server.port))

    stop: bool = true
    ServerRun(&site.server, &stop)                                                          // returns at once when asked to stop
}
