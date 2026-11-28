package browser_drive

// A WebSocket client (RFC 6455) over core:net, enough to talk to a browser on the same machine: text messages in and out, fragments, ping and pong, close. No TLS, no extensions. All memory is the
// caller's: `incoming` holds the bytes of the socket that are not used yet and has to be bigger than the biggest single frame that arrives (a screenshot is one frame), `message` holds the text that is
// being assembled, `outgoing` holds the frame that is being sent. Nothing allocates.

import "core:crypto"
import "core:crypto/legacy/sha1"
import "core:encoding/base64"
import "core:fmt"
import "core:net"
import "core:strings"
import "core:time"

WEBSOCKET_GUID :: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

Opcode :: enum u8 {
    CONTINUATION = 0x0,
    TEXT = 0x1,
    BINARY = 0x2,
    CLOSE = 0x8,
    PING = 0x9,
    PONG = 0xA,
}

WebSocket :: struct {
    socket: net.TCP_Socket,
    open: bool,
    incoming: []u8,
    incoming_length: int,
    message: []u8,
    message_length: int,
    outgoing: []u8,
    mask_state: u64,                    // the masks of the frames: any value will do, they only have to change
}

ReceiveStatus :: enum {
    MESSAGE,
    TIMEOUT,                            // nothing arrived in time
    CLOSED,                             // the other side closed, or the connection broke
    TOO_BIG,                            // a frame or a message does not fit the buffers
}

// A frame as it is on the wire, without the copy: `payload` points into the bytes it was parsed from
Frame :: struct {
    fin: bool,
    opcode: Opcode,
    masked: bool,
    payload: []u8,
}

WebSocketInit :: proc(ws: ^WebSocket, incoming: []u8, message: []u8, outgoing: []u8) {
    ws^ = {incoming = incoming, message = message, outgoing = outgoing}
}

// The Sec-WebSocket-Accept that the server has to answer to a key (RFC 6455, 1.3)
WebSocketAccept :: proc(key: string, buffer: []u8) -> string {
    context_sha: sha1.Context
    sha1.init(&context_sha)
    sha1.update(&context_sha, transmute([]u8)key)
    sha1.update(&context_sha, transmute([]u8)string(WEBSOCKET_GUID))
    digest: [sha1.DIGEST_SIZE]u8
    sha1.final(&context_sha, digest[:])
    encoded, _ := base64.encode_into_buf(buffer, digest[:])
    return string(encoded)
}

// Connect to ws://host:port/path on this machine and do the handshake. `host` is an address ("127.0.0.1").
WebSocketConnect :: proc(ws: ^WebSocket, host: string, port: int, path: string, timeout_ms: int = 5000) -> bool {
    endpoint, endpoint_ok := net.parse_endpoint(fmt.tprintf("%s:%d", host, port))
    if !endpoint_ok { return false }
    socket, dial_error := net.dial_tcp(endpoint)
    if dial_error != nil { return false }
    ws.socket = socket
    ws.incoming_length, ws.message_length = 0, 0

    random: [16]u8
    crypto.rand_bytes(random[:])
    ws.mask_state = u64(random[0]) | u64(random[1]) << 8 | u64(random[2]) << 16 | u64(random[3]) << 24 | 1
    key_buffer: [32]u8
    key_bytes, _ := base64.encode_into_buf(key_buffer[:], random[:])
    key: string = string(key_bytes)
    request: string = fmt.tprintf("GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n", path, host, port, key)
    if _, send_error := net.send_tcp(socket, transmute([]u8)request); send_error != nil {
        net.close(socket)
        return false
    }

    // the answer ends with an empty line; what comes after it (the server may already talk) stays in the buffer
    deadline: time.Time = time.time_add(time.now(), time.Duration(timeout_ms) * time.Millisecond)
    header_end: int = -1
    for header_end < 0 {
        if time.diff(time.now(), deadline) <= 0 || ws.incoming_length >= len(ws.incoming) {
            net.close(socket)
            return false
        }
        net.set_option(socket, .Receive_Timeout, 100 * time.Millisecond)
        count, receive_error := net.recv_tcp(socket, ws.incoming[ws.incoming_length:])
        if receive_error != nil && receive_error != .Timeout {
            net.close(socket)
            return false
        }
        ws.incoming_length += count
        header_end = strings.index(string(ws.incoming[:ws.incoming_length]), "\r\n\r\n")
    }
    header: string = string(ws.incoming[:header_end])
    accept_buffer: [32]u8
    expected: string = WebSocketAccept(key, accept_buffer[:])
    // header names are case insensitive
    lower: string = strings.to_lower(header, context.temp_allocator)
    if !strings.has_prefix(header, "HTTP/1.1 101") || !strings.contains(lower, strings.to_lower(fmt.tprintf("sec-websocket-accept: %s", expected), context.temp_allocator)) {
        net.close(socket)
        return false
    }
    consumed: int = header_end + 4
    copy(ws.incoming[:], ws.incoming[consumed:ws.incoming_length])
    ws.incoming_length -= consumed
    ws.open = true
    return true
}

WebSocketClose :: proc(ws: ^WebSocket) {
    if !ws.open { return }
    websocketSendFrame(ws, .CLOSE, nil)
    net.close(ws.socket)
    ws.open = false
}

// Send a text message
WebSocketSend :: proc(ws: ^WebSocket, text: string) -> bool {
    return websocketSendFrame(ws, .TEXT, transmute([]u8)text)
}

@(private)
websocketSendFrame :: proc(ws: ^WebSocket, opcode: Opcode, payload: []u8) -> bool {
    if !ws.open { return false }
    // xorshift: the mask only has to differ from frame to frame (it keeps proxies from mistaking data for a request)
    ws.mask_state ~= ws.mask_state << 13
    ws.mask_state ~= ws.mask_state >> 7
    ws.mask_state ~= ws.mask_state << 17
    mask: [4]u8 = {u8(ws.mask_state), u8(ws.mask_state >> 8), u8(ws.mask_state >> 16), u8(ws.mask_state >> 24)}
    length: int = FrameEncode(ws.outgoing, opcode, payload, mask)
    if length == 0 { return false }
    sent: int
    for sent < length {
        count, send_error := net.send_tcp(ws.socket, ws.outgoing[sent:length])
        if send_error != nil {
            ws.open = false
            return false
        }
        sent += count
    }
    return true
}

// A client frame (always masked, FIN set) into `out`. Returns its length, 0 when it does not fit.
FrameEncode :: proc(out: []u8, opcode: Opcode, payload: []u8, mask: [4]u8) -> int {
    header: int = 2 + 4
    if len(payload) >= 65536 { header += 8 } else if len(payload) >= 126 { header += 2 }
    if len(out) < header + len(payload) { return 0 }
    out[0] = 0x80 | u8(opcode)
    at: int = 1
    switch {
    case len(payload) >= 65536:
        out[at] = 0x80 | 127
        for i in 0 ..< 8 { out[at + 1 + i] = u8(u64(len(payload)) >> u64(8 * (7 - i))) }
        at += 9
    case len(payload) >= 126:
        out[at] = 0x80 | 126
        out[at + 1], out[at + 2] = u8(len(payload) >> 8), u8(len(payload))
        at += 3
    case:
        out[at] = 0x80 | u8(len(payload))
        at += 1
    }
    mask_copy: [4]u8 = mask
    copy(out[at:], mask_copy[:])
    at += 4
    for b, i in payload { out[at + i] = b ~ mask[i % 4] }
    return at + len(payload)
}

// The first frame in `data`: `used` is how many bytes it took, `complete` is false when more bytes are needed. A masked payload is unmasked in place.
FrameParse :: proc(data: []u8) -> (frame: Frame, used: int, complete: bool) {
    if len(data) < 2 { return }
    frame.fin = data[0] & 0x80 != 0
    frame.opcode = Opcode(data[0] & 0x0F)
    frame.masked = data[1] & 0x80 != 0
    length: u64 = u64(data[1] & 0x7F)
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
    if frame.masked {
        if len(data) < at + 4 { return }
        copy(mask[:], data[at:at + 4])
        at += 4
    }
    if length > u64(len(data) - at) { return }
    frame.payload = data[at:at + int(length)]
    if frame.masked {
        for i in 0 ..< len(frame.payload) { frame.payload[i] ~= mask[i % 4] }
    }
    return frame, at + int(length), true
}

// The next text message (or the end of the connection). Frames of other kinds are handled here: a ping is answered, a pong ignored, a close answered and reported.
// `timeout_ms` is how long to wait for the whole message to begin to arrive; the text is valid until the next call.
WebSocketReceive :: proc(ws: ^WebSocket, timeout_ms: int) -> (text: string, status: ReceiveStatus) {
    deadline: time.Time = time.time_add(time.now(), time.Duration(timeout_ms) * time.Millisecond)
    for {
        frame, used, complete := FrameParse(ws.incoming[:ws.incoming_length])
        if complete {
            handled: bool = true
            switch frame.opcode {
            case .TEXT, .BINARY, .CONTINUATION:
                if frame.opcode != .CONTINUATION { ws.message_length = 0 }
                if ws.message_length + len(frame.payload) > len(ws.message) { return "", .TOO_BIG }
                copy(ws.message[ws.message_length:], frame.payload)
                ws.message_length += len(frame.payload)
                if frame.fin { handled = false }
            case .PING:
                websocketSendFrame(ws, .PONG, frame.payload)
            case .PONG:
            case .CLOSE:
                ws.open = false
                net.close(ws.socket)
                return "", .CLOSED
            }
            copy(ws.incoming[:], ws.incoming[used:ws.incoming_length])
            ws.incoming_length -= used
            if !handled { return string(ws.message[:ws.message_length]), .MESSAGE }
            continue
        }
        if ws.incoming_length >= len(ws.incoming) { return "", .TOO_BIG }
        remaining: time.Duration = time.diff(time.now(), deadline)
        if remaining <= 0 { return "", .TIMEOUT }
        net.set_option(ws.socket, .Receive_Timeout, max(remaining, time.Millisecond))
        count, receive_error := net.recv_tcp(ws.socket, ws.incoming[ws.incoming_length:])
        if receive_error == .Timeout { continue }
        if receive_error != nil || count == 0 {
            ws.open = false
            return "", .CLOSED
        }
        ws.incoming_length += count
    }
}
