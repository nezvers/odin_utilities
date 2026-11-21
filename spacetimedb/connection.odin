package spacetimedb

// A client connection to a database (the websocket protocol v2): the part that a game or an application polls once a frame. No thread, no callback from another thread: `ConnectionPoll` returns
// the messages that came, one at a time, and the program decides what to do with them (that is what makes it fit a game loop, a Godot node, a test).
//
//     connection: Connection
//     if ConnectionOpen(&connection, {endpoint = {"127.0.0.1", 3000}, database = "chat"}, receive[:], message[:]) {
//         ConnectionSubscribe(&connection, 1, {"SELECT * FROM person"})
//         for {                                                                // the frame of the game
//             for {
//                 message, got := ConnectionPoll(&connection, context.temp_allocator)
//                 if !got { break }
//                 switch value in message { ... }                              // a SubscribeApplied has the rows, a TransactionUpdate the changes
//             }
//             free_all(context.temp_allocator)
//         }
//     }
//
// The token: without one in the config a new identity is made (the server is asked for it) and kept in `connection.token`; keep it (a file, the settings) and give it back to be the same
// client next time: the identity owns what it made.

import "base:runtime"
import "core:fmt"
import "core:time"

CONNECTION_SEND_BUFFER :: 1 << 16
CONNECTION_TOKEN_LENGTH :: 1024

ConnectionConfig :: struct {
    endpoint: Endpoint,
    database: string,           // the name or the identity (hex) of the database
    token: string,              // "": a new identity is made
}

Connection :: struct {
    socket: WebSocket,
    identity: Identity,         // set by the server's first message
    connection_id: ConnectionId,
    token: [CONNECTION_TOKEN_LENGTH]u8,
    token_length: int,
    connected: bool,            // the first message (InitialConnection) came
    next_request: u32,
    send: [CONNECTION_SEND_BUFFER]u8,
    error: string,
}

ConnectionToken :: proc(connection: ^Connection) -> string {
    return string(connection.token[:connection.token_length])
}

// Connects (asks the server for an identity first when there is no token). `receive` and `message` are the socket's buffers (websocket.odin: they have to hold the biggest message of the
// application: the first answer of a subscription is the largest). Returns when the socket is open; `InitialConnection` comes through ConnectionPoll.
ConnectionOpen :: proc(connection: ^Connection, config: ConnectionConfig, receive: []u8, message: []u8) -> bool {
    connection^ = {}
    token: string = config.token
    if token == "" {
        response: [2048]u8
        _, made, ok := IdentityCreate(config.endpoint, response[:])
        if !ok {
            connection.error = "could not get an identity"
            return false
        }
        token = made
    }
    if len(token) > CONNECTION_TOKEN_LENGTH {
        connection.error = "the token is too long"
        return false
    }
    connection.token_length = copy(connection.token[:], token)
    path: string = fmt.tprintf("/v1/database/%s/subscribe?compression=None", config.database)
    headers: [1]HttpHeader = {{"Authorization", fmt.tprintf("Bearer %s", token)}}
    protocols: [1]string = {PROTOCOL_V2}
    if !WebSocketOpen(&connection.socket, config.endpoint, path, protocols[:], headers[:], receive, message) {
        connection.error = connection.socket.error
        return false
    }
    return true
}

ConnectionClose :: proc(connection: ^Connection) {
    WebSocketClose(&connection.socket)
    connection.connected = false
}

ConnectionOpenState :: proc(connection: ^Connection) -> bool {
    return connection.socket.open
}

@(private)
nextRequest :: proc(connection: ^Connection) -> u32 {
    connection.next_request += 1
    return connection.next_request
}

@(private)
sendFrame :: proc(connection: ^Connection, writer: ^Writer) -> bool {
    if WriterFailed(writer) {
        connection.error = "the message does not fit the send buffer"
        return false
    }
    return WebSocketSend(&connection.socket, .BINARY, WriterBytes(writer))
}

// Subscribes to queries (`SELECT * FROM person`, one SELECT each) under your own `query_set_id` (unique in this connection). Returns the request id (0 when it could not be sent): the
// SubscribeApplied that answers has it.
ConnectionSubscribe :: proc(connection: ^Connection, query_set_id: u32, queries: []string) -> u32 {
    request: u32 = nextRequest(connection)
    writer: Writer = WriterMake(connection.send[:])
    EncodeSubscribe(&writer, request, query_set_id, queries)
    return request if sendFrame(connection, &writer) else 0
}

ConnectionUnsubscribe :: proc(connection: ^Connection, query_set_id: u32) -> u32 {
    request: u32 = nextRequest(connection)
    writer: Writer = WriterMake(connection.send[:])
    EncodeUnsubscribe(&writer, request, query_set_id)
    return request if sendFrame(connection, &writer) else 0
}

ConnectionOneOffQuery :: proc(connection: ^Connection, query: string) -> u32 {
    request: u32 = nextRequest(connection)
    writer: Writer = WriterMake(connection.send[:])
    EncodeOneOffQuery(&writer, request, query)
    return request if sendFrame(connection, &writer) else 0
}

// Calls a reducer with its arguments as BSATN (a Writer of yours: the fields one after the other). Returns the request id: the ReducerResult that answers has it.
ConnectionCallReducer :: proc(connection: ^Connection, reducer: string, arguments: []u8) -> u32 {
    request: u32 = nextRequest(connection)
    writer: Writer = WriterMake(connection.send[:])
    EncodeCallReducer(&writer, request, reducer, arguments)
    return request if sendFrame(connection, &writer) else 0
}

// The next message that came, if there is one. `allocator` is for the arrays of the message (see protocol.odin), strings and bytes point into the socket's buffer: both are good until the
// next call. `got` false: nothing new (or the socket closed: see `ConnectionOpenState` and `connection.error`).
ConnectionPoll :: proc(connection: ^Connection, allocator: runtime.Allocator) -> (message: ServerMessage, got: bool) {
    for {
        event, payload := WebSocketPoll(&connection.socket)
        switch event {
        case .NONE:
            return nil, false
        case .CLOSED, .ERROR:
            connection.error = connection.socket.error
            connection.connected = false
            return nil, false
        case .TEXT:
            continue                        // the server speaks binary on this protocol
        case .BINARY:
            body, ok := ServerFrame(payload)
            if !ok { continue }
            decoded, decoded_ok := ServerMessageDecode(body, allocator)
            if !decoded_ok { continue }
            if initial, is_initial := decoded.(InitialConnection); is_initial {
                connection.identity, connection.connection_id, connection.connected = initial.identity, initial.connection_id, true
            }
            return decoded, true
        }
    }
}

// Waits (polls) until a message that `wanted` accepts comes or the time runs out: for a test or a start up, not for a frame of a game. The messages that are not wanted are dropped.
ConnectionWait :: proc(connection: ^Connection, wanted: proc(message: ServerMessage, user: rawptr) -> bool, user: rawptr, allocator: runtime.Allocator, timeout: time.Duration = 5 * time.Second) -> (message: ServerMessage, got: bool) {
    start: time.Tick = time.tick_now()
    for time.tick_since(start) < timeout {
        candidate, ok := ConnectionPoll(connection, allocator)
        if ok && wanted(candidate, user) { return candidate, true }
        if !ok {
            if !connection.socket.open { return nil, false }
            time.sleep(2 * time.Millisecond)
        }
    }
    return nil, false
}
