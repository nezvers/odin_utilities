#+build !js
package tunnel

// TCP connections over a p2p Link: a SpacetimeDB server speaks TCP (HTTP and a websocket), p2p connects two programs over UDP through NATs. The host side of a tunnel dials the server on its own
// machine for every connection a guest opens; the guest side listens on a local port, so a client that connects to `127.0.0.1:<port>` talks to the server of the host as if it were local
// (the whole of `spacetimedb` works through it: identities, publishing, the websocket). Several connections at once (a REST call is a connection of its own) and several guests.
//
//     host:  TunnelHostInit(&tunnel, link, {address = net.IP4_Loopback, port = 3000})
//     guest: TunnelGuestInit(&tunnel, link, 0, 3300)                 // clients connect to 127.0.0.1:3300
//     every frame, after p2p.LinkUpdate: TunnelUpdate(&tunnel, now)
//
// The tunnel owns the messages of its Link (it reads the inbox). Frames are `[kind u8][connection u16][bytes]` in reliable Link messages, so a stream arrives complete and in order; a socket
// is read only while the Link has room, which is the back pressure. Fixed storage: no allocation after the Tunnel exists (about 0.6 MB: place it once).

import "core:net"
import "../../p2p"

MAX_CONNECTIONS :: 32
CHUNK :: p2p.MAX_PAYLOAD - 3                    // bytes of a stream in one frame
OUT_BUFFER :: 1 << 14                           // bytes waiting for a socket that cannot take them yet

FrameKind :: enum u8 {
    OPEN = 1,
    DATA = 2,
    CLOSE = 3,
}

Mode :: enum u8 {
    NONE,
    HOST,
    GUEST,
}

Connection :: struct {
    active: bool,
    peer: int,
    id: u16,
    socket: net.TCP_Socket,
    out: [OUT_BUFFER]u8,        // from the Link to the socket
    out_length: int,
    frame: [p2p.MAX_PAYLOAD]u8, // a frame read from the socket that the Link had no room for yet
    frame_length: int,
    close_after_flush: bool,
}

Tunnel :: struct {
    mode: Mode,
    link: ^p2p.Link,
    peer: int,                  // guest: the peer that is the host
    target: net.Endpoint,       // host: the server that connections go to
    listener: net.TCP_Socket,   // guest: where clients connect
    port: int,
    next_id: u16,
    connections: [MAX_CONNECTIONS]Connection,
    opened: int,                // statistics: connections made, bytes carried each way
    bytes_in: int,
    bytes_out: int,
}

// The host side: every OPEN of a guest dials `target`. The tunnel works with every peer of the Link.
TunnelHostInit :: proc(tunnel: ^Tunnel, link: ^p2p.Link, target: net.Endpoint) {
    tunnel^ = {mode = .HOST, link = link, target = target}
}

// The guest side: listens on 127.0.0.1:`port` (0: any free port, read it from `tunnel.port`) and sends what comes in to `peer` (the host: 0). False when the port cannot be bound.
TunnelGuestInit :: proc(tunnel: ^Tunnel, link: ^p2p.Link, peer: int, port: int) -> bool {
    tunnel^ = {mode = .GUEST, link = link, peer = peer}
    listener, listen_error := net.listen_tcp({address = net.IP4_Loopback, port = port})
    if listen_error != nil { return false }
    endpoint, endpoint_error := net.bound_endpoint(listener)
    if endpoint_error != nil {
        net.close(listener)
        return false
    }
    net.set_blocking(listener, false)
    tunnel.listener, tunnel.port = listener, endpoint.port
    return true
}

TunnelClose :: proc(tunnel: ^Tunnel) {
    for &connection in tunnel.connections {
        if connection.active { net.close(connection.socket) }
        connection = {}
    }
    if tunnel.mode == .GUEST { net.close(tunnel.listener) }
    tunnel.mode = .NONE
}

TunnelConnectionCount :: proc(tunnel: ^Tunnel) -> (count: int) {
    for &connection in tunnel.connections { if connection.active { count += 1 } }
    return
}

@(private)
sendFrame :: proc(tunnel: ^Tunnel, peer: int, kind: FrameKind, id: u16, now: i64) -> bool {
    frame: [3]u8 = {u8(kind), u8(id), u8(id >> 8)}
    return p2p.LinkSend(tunnel.link, peer, frame[:], true, now)
}

@(private)
freeSlot :: proc(tunnel: ^Tunnel) -> ^Connection {
    for &connection in tunnel.connections {
        if !connection.active { return &connection }
    }
    return nil
}

@(private)
find :: proc(tunnel: ^Tunnel, peer: int, id: u16) -> ^Connection {
    for &connection in tunnel.connections {
        if connection.active && connection.peer == peer && connection.id == id { return &connection }
    }
    return nil
}

@(private)
drop :: proc(connection: ^Connection) {
    if connection.active { net.close(connection.socket) }
    connection^ = {}
}

// One step: new local connections (guest), the frames of the Link, and every socket: what the Link brought goes out, what the socket has goes into the Link. Call it once a frame after
// `p2p.LinkUpdate`. Returns how many frames came in (nothing to do when 0 and the sockets are quiet).
TunnelUpdate :: proc(tunnel: ^Tunnel, now: i64) -> (frames: int) {
    if tunnel.mode == .NONE { return }
    if tunnel.mode == .GUEST { acceptLocal(tunnel, now) }
    buffer: [p2p.MAX_PAYLOAD]u8
    for {
        peer, length, ok := p2p.LinkReceive(tunnel.link, buffer[:])
        if !ok { break }
        frames += 1
        if length < 3 { continue }
        id: u16 = u16(buffer[1]) | u16(buffer[2]) << 8
        switch FrameKind(buffer[0]) {
        case .OPEN:
            if tunnel.mode == .HOST { openRemote(tunnel, peer, id, now) }
        case .DATA:
            connection: ^Connection = find(tunnel, peer, id)
            if connection == nil { continue }
            data: []u8 = buffer[3:length]
            if connection.out_length + len(data) > OUT_BUFFER {
                drop(connection)                    // a socket that does not take what comes: the connection is over
                sendFrame(tunnel, peer, .CLOSE, id, now)
                continue
            }
            copy(connection.out[connection.out_length:], data)
            connection.out_length += len(data)
            tunnel.bytes_in += len(data)
        case .CLOSE:
            connection: ^Connection = find(tunnel, peer, id)
            if connection != nil { connection.close_after_flush = true }
        }
    }
    for &connection in tunnel.connections {
        if connection.active { pumpSocket(tunnel, &connection, now) }
    }
    return
}

@(private)
acceptLocal :: proc(tunnel: ^Tunnel, now: i64) {
    for {
        client, _, accept_error := net.accept_tcp(tunnel.listener)
        if accept_error != nil { return }
        slot: ^Connection = freeSlot(tunnel)
        tunnel.next_id += 1
        if slot == nil || !sendFrame(tunnel, tunnel.peer, .OPEN, tunnel.next_id, now) {
            net.close(client)
            continue
        }
        net.set_blocking(client, false)
        net.set_option(client, .TCP_Nodelay, true)
        slot^ = {active = true, peer = tunnel.peer, id = tunnel.next_id, socket = client}
        tunnel.opened += 1
    }
}

@(private)
openRemote :: proc(tunnel: ^Tunnel, peer: int, id: u16, now: i64) {
    slot: ^Connection = freeSlot(tunnel)
    if slot == nil {
        sendFrame(tunnel, peer, .CLOSE, id, now)
        return
    }
    socket, dial_error := net.dial_tcp_from_endpoint(tunnel.target)
    if dial_error != nil {
        sendFrame(tunnel, peer, .CLOSE, id, now)
        return
    }
    net.set_blocking(socket, false)
    net.set_option(socket, .TCP_Nodelay, true)
    slot^ = {active = true, peer = peer, id = id, socket = socket}
    tunnel.opened += 1
}

@(private)
pumpSocket :: proc(tunnel: ^Tunnel, connection: ^Connection, now: i64) {
    // what the Link brought: out to the socket
    for connection.out_length > 0 {
        count, send_error := net.send_tcp(connection.socket, connection.out[:connection.out_length])
        if send_error == .Would_Block { break }
        if send_error != nil || count <= 0 {
            sendFrame(tunnel, connection.peer, .CLOSE, connection.id, now)
            drop(connection)
            return
        }
        copy(connection.out[:], connection.out[count:connection.out_length])
        connection.out_length -= count
    }
    if connection.close_after_flush && connection.out_length == 0 {
        drop(connection)
        return
    }
    // what the socket has: into the Link, while the Link has room
    for {
        if connection.frame_length == 0 {
            connection.frame[0], connection.frame[1], connection.frame[2] = u8(FrameKind.DATA), u8(connection.id), u8(connection.id >> 8)
            count, receive_error := net.recv_tcp(connection.socket, connection.frame[3:3 + CHUNK])
            if receive_error == .Would_Block { return }
            if receive_error != nil || count <= 0 {
                sendFrame(tunnel, connection.peer, .CLOSE, connection.id, now)
                drop(connection)
                return
            }
            connection.frame_length = 3 + count
        }
        if !p2p.LinkSend(tunnel.link, connection.peer, connection.frame[:connection.frame_length], true, now) { return }
        tunnel.bytes_out += connection.frame_length - 3
        connection.frame_length = 0
    }
}
