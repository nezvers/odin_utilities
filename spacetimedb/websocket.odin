package spacetimedb

// A WebSocket client (RFC 6455) over a TCP socket: the handshake (blocking, with a time limit), then a non blocking socket that a game polls once a frame (`WebSocketPoll`) so no thread is
// needed. The buffers are the caller's: `receive` holds the bytes that came and are not yet a whole frame, `message` holds a message that is put together from frames; a message or a frame
// that does not fit closes the socket with an error (a size that suits the biggest subscription of the application: the first answer of a subscription is the largest). Pings are answered here,
// a close is answered and reported. Plain `ws://` (see TODO.md for TLS).
//
//     socket: WebSocket
//     if WebSocketOpen(&socket, {host, port}, "/v1/database/chat/subscribe?compression=None", {PROTOCOL_V2}, headers, receive[:], message[:]) { ... }
//     for {
//         event, payload := WebSocketPoll(&socket)
//         #partial switch event { case .BINARY: ...; case .CLOSED: ...; case .NONE: break }
//     }
//     WebSocketSend(&socket, .BINARY, bytes)

import "core:crypto"
import "core:crypto/legacy/sha1"
import "core:encoding/base64"
import "core:fmt"
import "core:net"
import "core:strings"
import "core:time"

WebSocketEvent :: enum u8 {
    NONE,           // nothing new
    TEXT,
    BINARY,
    CLOSED,         // the other side closed (or the socket broke): see `close_code`
    ERROR,          // a buffer is too small, a frame is not valid: the socket is closed
}

WebSocketOpcode :: enum u8 {
    CONTINUATION = 0,
    TEXT = 1,
    BINARY = 2,
    CLOSE = 8,
    PING = 9,
    PONG = 10,
}

WebSocket :: struct {
    socket: net.TCP_Socket,
    open: bool,
    receive: []u8,                  // bytes that came and are not used yet
    received: int,
    message: []u8,                  // the message that is being put together
    message_length: int,
    message_opcode: WebSocketOpcode,
    close_code: u16,
    error: string,
    consumed: int,                  // the bytes of `receive` that the last returned message used: dropped at the next poll
    send_buffer: [WEBSOCKET_SEND_BUFFER]u8,
}

WEBSOCKET_SEND_BUFFER :: 4096    // a client message that is bigger is sent in parts from the caller's own buffer (WebSocketSend copes with any size)

WEBSOCKET_GUID :: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

// Connects, asks for the upgrade and waits for the answer. `protocols` are the sub protocols that are offered (the first the server accepts is used), `headers` are added to the request (an
// `Authorization: Bearer <token>`). False with `socket.error` set when the server refuses or does not answer.
WebSocketOpen :: proc(ws: ^WebSocket, endpoint: Endpoint, path: string, protocols: []string, headers: []HttpHeader, receive: []u8, message: []u8, timeout: time.Duration = HTTP_TIMEOUT) -> bool {
    ws^ = {receive = receive, message = message}
    socket, dial_error := net.dial_tcp_from_hostname_with_port_override(endpoint.host, endpoint.port)
    if dial_error != nil {
        ws.error = "could not connect"
        return false
    }
    net.set_option(socket, .Receive_Timeout, timeout)
    net.set_option(socket, .Send_Timeout, timeout)

    key_bytes: [16]u8
    crypto.rand_bytes(key_bytes[:])
    key: string = base64.encode(key_bytes[:], allocator = context.temp_allocator)
    head: strings.Builder
    strings.builder_init(&head, context.temp_allocator)
    fmt.sbprintf(&head, "GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n", path, endpoint.host, endpoint.port, key)
    if len(protocols) > 0 { fmt.sbprintf(&head, "Sec-WebSocket-Protocol: %s\r\n", strings.join(protocols, ", ", context.temp_allocator)) }
    for header in headers { fmt.sbprintf(&head, "%s: %s\r\n", header.name, header.value) }
    strings.write_string(&head, "\r\n")
    if !sendAll(socket, transmute([]u8)strings.to_string(head)) {
        net.close(socket)
        ws.error = "could not send the request"
        return false
    }

    // the answer: the headers, up to the empty line; what comes after them already is the start of the frames
    length: int
    end: int = -1
    for end < 0 && length < len(receive) {
        count, error := net.recv_tcp(socket, receive[length:])
        if count > 0 { length += count }
        end = indexOf(receive[:length], "\r\n\r\n")
        if error != nil || count == 0 { break }
    }
    if end < 0 {
        net.close(socket)
        ws.error = "no answer to the upgrade"
        return false
    }
    answer: string = string(receive[:end])
    if !strings.has_prefix(answer, "HTTP/1.1 101") {
        net.close(socket)
        ws.error = "the server refused the upgrade" if strings.has_prefix(answer, "HTTP/1.1 ") else "not an HTTP answer"
        return false
    }
    // the proof that the server read the key: base64(sha1(key + guid))
    context_sha: sha1.Context
    sha1.init(&context_sha)
    sha1.update(&context_sha, transmute([]u8)key)
    sha1.update(&context_sha, transmute([]u8)string(WEBSOCKET_GUID))
    digest: [sha1.DIGEST_SIZE]u8
    sha1.final(&context_sha, digest[:])
    accept: string = base64.encode(digest[:], allocator = context.temp_allocator)
    if headerValue(answer, "Sec-WebSocket-Accept") != accept {
        net.close(socket)
        ws.error = "the accept key is wrong"
        return false
    }
    leftover: int = length - (end + 4)
    copy(receive[:leftover], receive[end + 4:length])
    ws.received = leftover
    ws.socket = socket
    ws.open = true
    net.set_blocking(socket, false)
    return true
}

WebSocketClose :: proc(ws: ^WebSocket, code: u16 = 1000) {
    if !ws.open { return }
    payload: [2]u8 = {u8(code >> 8), u8(code)}
    WebSocketSend(ws, .CLOSE, payload[:])
    net.close(ws.socket)
    ws.open = false
}

// Sends a message as one frame (masked, as a client has to). A message of any size: the frame is written in parts through the socket's buffer. False when the socket is closed or broke.
WebSocketSend :: proc(ws: ^WebSocket, opcode: WebSocketOpcode, payload: []u8) -> bool {
    if !ws.open { return false }
    header: [14]u8
    header[0] = 0x80 | u8(opcode)
    length: int
    switch {
    case len(payload) < 126:
        header[1] = 0x80 | u8(len(payload))
        length = 2
    case len(payload) < 65536:
        header[1] = 0x80 | 126
        header[2], header[3] = u8(len(payload) >> 8), u8(len(payload))
        length = 4
    case:
        header[1] = 0x80 | 127
        for i in 0 ..< 8 { header[2 + i] = u8(u64(len(payload)) >> u32((7 - i) * 8)) }
        length = 10
    }
    mask: [4]u8
    crypto.rand_bytes(mask[:])
    copy(header[length:], mask[:])
    length += 4
    if !wsSend(ws, header[:length]) { return false }
    sent: int
    for sent < len(payload) {
        chunk: int = min(len(ws.send_buffer), len(payload) - sent)
        for i in 0 ..< chunk { ws.send_buffer[i] = payload[sent + i] ~ mask[(sent + i) & 3] }
        if !wsSend(ws, ws.send_buffer[:chunk]) { return false }
        sent += chunk
    }
    return true
}

// A non blocking socket: a send that cannot go at once is tried again until it does (a frame is small next to the buffers of the system; a stalled peer is a closed socket after the time limit)
@(private)
wsSend :: proc(ws: ^WebSocket, bytes: []u8) -> bool {
    sent: int
    deadline: time.Tick = time.tick_now()
    for sent < len(bytes) {
        count, error := net.send_tcp(ws.socket, bytes[sent:])
        if error == .Would_Block {
            if time.duration_seconds(time.tick_since(deadline)) > 5 {
                wsFail(ws, "a send did not go")
                return false
            }
            time.sleep(time.Millisecond)
            continue
        }
        if error != nil || count <= 0 {
            wsFail(ws, "the socket broke")
            return false
        }
        sent += count
    }
    return true
}

@(private)
wsFail :: proc(ws: ^WebSocket, why: string) {
    ws.error = why
    if ws.open { net.close(ws.socket) }
    ws.open = false
}

// One step: reads what the socket has and returns the next whole message (`payload` is a slice of the socket's buffers: it is good until the next call). `.NONE` when there is nothing new.
// Pings are answered, a close is answered and reported once.
WebSocketPoll :: proc(ws: ^WebSocket) -> (event: WebSocketEvent, payload: []u8) {
    if ws.consumed > 0 {
        copy(ws.receive[:ws.received - ws.consumed], ws.receive[ws.consumed:ws.received])
        ws.received -= ws.consumed
        ws.consumed = 0
    }
    if !ws.open && ws.received == 0 { return .NONE, nil }
    // what the socket has, as much as fits
    if ws.open && ws.received < len(ws.receive) {
        count, error := net.recv_tcp(ws.socket, ws.receive[ws.received:])
        if count > 0 { ws.received += count }
        if error != nil && error != .Would_Block {
            wsFail(ws, "the socket broke")
            return .CLOSED, nil
        }
        if count == 0 && error == nil {
            wsFail(ws, "the server closed the socket")
            return .CLOSED, nil
        }
    }
    for {
        frame_event, frame_payload, used, complete := wsFrame(ws)
        if !complete { break }
        ws.consumed = used
        if frame_event != .NONE {
            return frame_event, frame_payload
        }
        // a frame that is only a part (or a ping): its bytes go and the next one is looked at
        copy(ws.receive[:ws.received - used], ws.receive[used:ws.received])
        ws.received -= used
        ws.consumed = 0
    }
    if ws.received == len(ws.receive) {
        wsFail(ws, "a frame does not fit the receive buffer")
        return .ERROR, nil
    }
    return .NONE, nil
}

// Reads the first frame of the receive buffer. `used` is its size; `event` is NONE for a frame that only adds to a message or is a ping or pong.
@(private)
wsFrame :: proc(ws: ^WebSocket) -> (event: WebSocketEvent, payload: []u8, used: int, complete: bool) {
    data: []u8 = ws.receive[:ws.received]
    if len(data) < 2 { return }
    fin: bool = data[0] & 0x80 != 0
    opcode: WebSocketOpcode = WebSocketOpcode(data[0] & 0x0f)
    masked: bool = data[1] & 0x80 != 0
    length: u64 = u64(data[1] & 0x7f)
    at: int = 2
    switch length {
    case 126:
        if len(data) < 4 { return }
        length = u64(data[2]) << 8 | u64(data[3])
        at = 4
    case 127:
        if len(data) < 10 { return }
        length = 0
        for i in 0 ..< 8 { length = length << 8 | u64(data[2 + i]) }
        at = 10
    }
    mask: [4]u8
    if masked {
        if len(data) < at + 4 { return }
        copy(mask[:], data[at:at + 4])
        at += 4
    }
    if length > u64(len(ws.receive)) {
        wsFail(ws, "a frame does not fit the receive buffer")
        return .ERROR, nil, ws.received, true
    }
    if len(data) < at + int(length) { return }
    body: []u8 = data[at:at + int(length)]
    if masked { for i in 0 ..< len(body) { body[i] ~= mask[i & 3] } }
    used, complete = at + int(length), true
    switch opcode {
    case .PING:
        WebSocketSend(ws, .PONG, body)
    case .PONG:
    case .CLOSE:
        if len(body) >= 2 { ws.close_code = u16(body[0]) << 8 | u16(body[1]) }
        if ws.open {
            WebSocketSend(ws, .CLOSE, body[:min(len(body), 2)])
            net.close(ws.socket)
            ws.open = false
        }
        return .CLOSED, nil, used, true
    case .TEXT, .BINARY, .CONTINUATION:
        if opcode != .CONTINUATION { ws.message_opcode, ws.message_length = opcode, 0 }
        if fin && ws.message_length == 0 {
            // a whole message in one frame: no copy, the payload is a slice of the receive buffer
            return .TEXT if ws.message_opcode == .TEXT else .BINARY, body, used, true
        }
        if ws.message_length + len(body) > len(ws.message) {
            wsFail(ws, "a message does not fit the message buffer")
            return .ERROR, nil, ws.received, true
        }
        copy(ws.message[ws.message_length:], body)
        ws.message_length += len(body)
        if fin {
            total: int = ws.message_length
            ws.message_length = 0
            return .TEXT if ws.message_opcode == .TEXT else .BINARY, ws.message[:total], used, true
        }
    }
    return .NONE, nil, used, true
}
