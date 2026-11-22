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
CONNECTION_TOKEN_LENGTH :: 4096

CONNECTION_SUBSCRIPTIONS :: 16
CONNECTION_QUERIES :: 8

ConnectionConfig :: struct {
    endpoint: Endpoint,
    database: string,           // the name or the identity (hex) of the database (kept by reference: it has to live as long as the connection, for a reconnect)
    token: string,              // "": a new identity is made
    confirmed: bool,            // `confirmed=true`: the server tells a change only when it is durable (slower, never taken back)
    refresh: proc(user: rawptr) -> string,      // for a login that expires (OIDC, see auth.odin): asked for the token again at every reconnect; "" keeps the one in use. The text is copied.
    refresh_user: rawptr,
}

// What the connection subscribed to, to do it again after a reconnect (the query strings are kept by reference)
ConnectionSubscription :: struct {
    query_set_id: u32,
    queries: [CONNECTION_QUERIES]string,
    count: int,
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
    config: ConnectionConfig,                       // with the token filled in: a reconnect is the same client
    receive_buffer, message_buffer: []u8,           // the socket's buffers, again for a reconnect
    subscriptions: [CONNECTION_SUBSCRIPTIONS]ConnectionSubscription,
    subscription_count: int,
    attempts: int,                                  // failed reconnects in a row (the backoff)
    next_attempt: time.Tick,
    dropped: bool,                                  // the socket closed after it was open: `ConnectionMaintain` reconnects
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
    connection.config = config
    connection.config.token = ""
    connection.receive_buffer, connection.message_buffer = receive, message
    return connectSocket(connection)
}

@(private)
connectSocket :: proc(connection: ^Connection) -> bool {
    config: ConnectionConfig = connection.config
    if config.refresh != nil {
        // a token that expires is asked for again: the reconnect must not present the one of the first connection
        renewed: string = config.refresh(config.refresh_user)
        if renewed != "" && len(renewed) <= CONNECTION_TOKEN_LENGTH { connection.token_length = copy(connection.token[:], renewed) }
    }
    token: string = ConnectionToken(connection)
    path: string = fmt.tprintf("/v1/database/%s/subscribe?compression=None%s", config.database, "&confirmed=true" if config.confirmed else "")
    headers: [1]HttpHeader = {{"Authorization", fmt.tprintf("Bearer %s", token)}}
    protocols: [1]string = {PROTOCOL_V2}
    if !WebSocketOpen(&connection.socket, config.endpoint, path, protocols[:], headers[:], connection.receive_buffer, connection.message_buffer) {
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
    if !sendFrame(connection, &writer) { return 0 }
    remember(connection, query_set_id, queries)
    return request
}

@(private)
remember :: proc(connection: ^Connection, query_set_id: u32, queries: []string) {
    if len(queries) > CONNECTION_QUERIES { return }
    at: int = connection.subscription_count
    for i in 0 ..< connection.subscription_count {
        if connection.subscriptions[i].query_set_id == query_set_id { at = i }
    }
    if at >= CONNECTION_SUBSCRIPTIONS { return }
    entry: ^ConnectionSubscription = &connection.subscriptions[at]
    entry^ = {query_set_id = query_set_id, count = len(queries)}
    copy(entry.queries[:], queries)
    if at == connection.subscription_count { connection.subscription_count += 1 }
}

ConnectionUnsubscribe :: proc(connection: ^Connection, query_set_id: u32) -> u32 {
    request: u32 = nextRequest(connection)
    writer: Writer = WriterMake(connection.send[:])
    EncodeUnsubscribe(&writer, request, query_set_id)
    if !sendFrame(connection, &writer) { return 0 }
    for i in 0 ..< connection.subscription_count {
        if connection.subscriptions[i].query_set_id == query_set_id {
            connection.subscriptions[i] = connection.subscriptions[connection.subscription_count - 1]
            connection.subscription_count -= 1
            break
        }
    }
    return request
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

// Calls a procedure (a function of the module that may return a value and use HTTP, unlike a reducer, and is not a transaction): the `ProcedureResult` that answers has the request id and the
// returned value as BSATN.
ConnectionCallProcedure :: proc(connection: ^Connection, procedure: string, arguments: []u8) -> u32 {
    request: u32 = nextRequest(connection)
    writer: Writer = WriterMake(connection.send[:])
    EncodeCallProcedure(&writer, request, procedure, arguments)
    return request if sendFrame(connection, &writer) else 0
}

// Several subscriptions applied at the same moment of the database: one `SubscribeBatchApplied` answers (the cache applies it whole). `query_set_ids[i]` goes with `queries[i]`.
ConnectionSubscribeBatch :: proc(connection: ^Connection, query_set_ids: []u32, queries: [][]string) -> u32 {
    assert(len(query_set_ids) == len(queries))
    request: u32 = nextRequest(connection)
    writer: Writer = WriterMake(connection.send[:])
    EncodeSubscribeBatch(&writer, request, query_set_ids, queries)
    if !sendFrame(connection, &writer) { return 0 }
    for id, i in query_set_ids { remember(connection, id, queries[i]) }
    return request
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
            if connection.connected { connection.dropped = true }
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
ConnectionWait :: proc(connection: ^Connection, wanted: proc(message: ServerMessage, user: rawptr) -> bool, user: rawptr, allocator: runtime.Allocator, timeout: time.Duration = 0) -> (message: ServerMessage, got: bool) {         // 0: five seconds, scaled
    start: time.Tick = time.tick_now()
    limit: time.Duration = timeout if timeout > 0 else Scaled(5 * time.Second)
    for time.tick_since(start) < limit {
        candidate, ok := ConnectionPoll(connection, allocator)
        if ok && wanted(candidate, user) { return candidate, true }
        if !ok {
            if !connection.socket.open { return nil, false }
            time.sleep(2 * time.Millisecond)
        }
    }
    return nil, false
}

// Opens the socket again with the same token (the same identity) and subscribes again to everything that was subscribed to. The new `InitialConnection` and the `SubscribeApplied` of every
// subscription come through ConnectionPoll again: clear the cache first (`CacheClear`), the answers fill it. False when the server could not be reached.
ConnectionReconnect :: proc(connection: ^Connection) -> bool {
    WebSocketClose(&connection.socket)
    connection.connected = false
    if !connectSocket(connection) { return false }
    connection.dropped = false
    for i in 0 ..< connection.subscription_count {
        entry: ConnectionSubscription = connection.subscriptions[i]
        request: u32 = nextRequest(connection)
        writer: Writer = WriterMake(connection.send[:])
        EncodeSubscribe(&writer, request, entry.query_set_id, entry.queries[:entry.count])
        if !sendFrame(connection, &writer) { return false }
    }
    return true
}

// For a game loop: when the socket was lost, tries to reconnect, no more often than the backoff allows (1 s, doubling to 30 s) so a server that is down is not hammered. Returns true in the
// frame in which the connection came back (clear the cache then). Call it once a frame, after the poll loop.
ConnectionMaintain :: proc(connection: ^Connection) -> bool {
    if !connection.dropped { return false }
    if time.tick_since(connection.next_attempt) < 0 { return false }
    if ConnectionReconnect(connection) {
        connection.attempts = 0
        return true
    }
    connection.attempts += 1
    delay: time.Duration = time.Second << uint(min(connection.attempts - 1, 5))
    connection.next_attempt = time.tick_add(time.tick_now(), delay)
    return false
}
