package godot_spacetimedb

// The object that GDScript holds: one connection to a SpacetimeDB database and the events that came from it. Everything is polled: the script calls `poll()` from `_process`, then reads the
// events one after the other with `next_event()` and the `event_*` getters. No thread, no callback from the network into Godot, so nothing here runs when the game is not asking.
//
// Rows travel as hex text: the BSATN bytes of a row (or of the arguments of a reducer) written in hexadecimal. In GDScript `hex.hex_decode()` gives a PackedByteArray and
// `bytes.hex_encode()` goes back. (A PackedByteArray in both directions is on the list in TODO.md.)

import "base:runtime"
import "core:fmt"
import "core:strings"
import spacetimedb "../../spacetimedb"

EventKind :: enum i64 {
    NONE = 0,
    CONNECTED = 1,              // the server greeted us: `event_text` is our identity
    INSERT = 2,                 // `event_table`, `event_row`
    DELETE = 3,                 // `event_table`, `event_row` (an update is a DELETE and an INSERT of the same key in one transaction: they come one after the other)
    SUBSCRIBED = 4,             // a subscription is applied (its rows came as INSERT events before this one): `event_request`
    REDUCER = 5,                // the result of a reducer call: `event_request`, `event_ok`, `event_text` (the error)
    SUBSCRIPTION_ERROR = 6,     // `event_text`
    DISCONNECTED = 7,           // the socket was lost; poll() reconnects with the same token
    RECONNECTED = 8,            // it came back: the subscriptions are applied again (their rows come as INSERT events again: clear what you keep)
}

Span :: struct {
    offset, length: int,
}

Event :: struct {
    kind: EventKind,
    request: u32,
    ok: bool,
    table, row, text: Span,
}

CLIENT_BUFFER :: 1 << 20        // the biggest message the connection can take (the first answer of a subscription is the largest)

Client :: struct {
    connection: spacetimedb.Connection,
    open: bool,
    receive, message: []u8,
    host, database: string,     // owned: the connection keeps them for a reconnect
    queries: [dynamic]string,   // owned, same reason
    next_set: u32,
    events: [dynamic]Event,
    current: int,               // the event that the getters describe: -1 before the first next_event()
    storage: [dynamic]u8,       // the bytes that the events point to, until the next poll()
    error: string,
}

clientFree :: proc(client: ^Client) {
    if client.open { spacetimedb.ConnectionClose(&client.connection) }
    delete(client.receive)
    delete(client.message)
    delete(client.host)
    delete(client.database)
    for query in client.queries { delete(query) }
    delete(client.queries)
    delete(client.events)
    delete(client.storage)
    free(client)
}

// Copies bytes into the event storage; the span says where they are
@(private)
keep :: proc(client: ^Client, bytes: []u8) -> Span {
    at: int = len(client.storage)
    append(&client.storage, ..bytes)
    return {at, len(bytes)}
}

@(private)
keepHex :: proc(client: ^Client, bytes: []u8) -> Span {
    at: int = len(client.storage)
    digits: string = "0123456789abcdef"
    for b in bytes { append(&client.storage, digits[b >> 4], digits[b & 15]) }
    return {at, len(bytes) * 2}
}

spanBytes :: proc(client: ^Client, span: Span) -> []u8 {
    return client.storage[span.offset:span.offset + span.length]
}

hexDecode :: proc(text: []u8, out: []u8) -> (count: int, ok: bool) {
    if len(text) % 2 != 0 || len(text) / 2 > len(out) { return 0, false }
    nibble :: proc(c: u8) -> (value: u8, ok: bool) {
        switch c {
        case '0' ..= '9': return c - '0', true
        case 'a' ..= 'f': return c - 'a' + 10, true
        case 'A' ..= 'F': return c - 'A' + 10, true
        }
        return 0, false
    }
    for i in 0 ..< len(text) / 2 {
        high, high_ok := nibble(text[i * 2])
        low, low_ok := nibble(text[i * 2 + 1])
        if !high_ok || !low_ok { return 0, false }
        out[i] = high << 4 | low
    }
    return len(text) / 2, true
}

clientOpen :: proc(client: ^Client, host: string, port: int, database: string, token: string) -> bool {
    if client.open {
        spacetimedb.ConnectionClose(&client.connection)
        client.open = false
    }
    if client.receive == nil {
        client.receive = make([]u8, CLIENT_BUFFER)
        client.message = make([]u8, CLIENT_BUFFER)
    }
    delete(client.host)
    delete(client.database)
    client.host, client.database = strings.clone(host), strings.clone(database)
    config: spacetimedb.ConnectionConfig = {endpoint = {host = client.host, port = port, secure = port == 443}, database = client.database, token = token}
    client.open = spacetimedb.ConnectionOpen(&client.connection, config, client.receive, client.message)
    client.error = client.connection.error
    client.next_set = 0
    clear(&client.events)
    client.current = -1
    return client.open
}

clientClose :: proc(client: ^Client) {
    if client.open {
        spacetimedb.ConnectionClose(&client.connection)
        client.open = false
    }
}

// Subscribes to one query; returns the request id (0: it could not be sent). The query text is kept for a reconnect.
clientSubscribe :: proc(client: ^Client, query: string) -> u32 {
    if !client.open { return 0 }
    append(&client.queries, strings.clone(query))
    client.next_set += 1
    one: [1]string = {client.queries[len(client.queries) - 1]}
    return spacetimedb.ConnectionSubscribe(&client.connection, client.next_set, one[:])
}

clientCallReducer :: proc(client: ^Client, name: string, arguments_hex: string) -> u32 {
    if !client.open { return 0 }
    bytes: [spacetimedb.CONNECTION_SEND_BUFFER]u8
    count, ok := hexDecode(transmute([]u8)arguments_hex, bytes[:])
    if !ok { return 0 }
    return spacetimedb.ConnectionCallReducer(&client.connection, name, bytes[:count])
}

// The same with the arguments as bytes (a PackedByteArray of GDScript)
clientCallReducerBytes :: proc(client: ^Client, name: string, arguments: []u8) -> u32 {
    if !client.open { return 0 }
    return spacetimedb.ConnectionCallReducer(&client.connection, name, arguments)
}

// Reads what the network has into the event list (the previous events are dropped); returns how many events there are. Reconnects when the socket was lost.
clientPoll :: proc(client: ^Client) -> int {
    clear(&client.events)
    clear(&client.storage)
    client.current = -1
    if !client.open { return 0 }
    arena: runtime.Arena
    allocator: runtime.Allocator = runtime.arena_allocator(&arena)
    defer runtime.arena_destroy(&arena)
    for {
        message, got := spacetimedb.ConnectionPoll(&client.connection, allocator)
        if !got { break }
        eventsOfMessage(client, message)
    }
    if client.connection.dropped {
        append(&client.events, Event{kind = .DISCONNECTED, text = keep(client, transmute([]u8)client.connection.error)})
        if spacetimedb.ConnectionMaintain(&client.connection) { append(&client.events, Event{kind = .RECONNECTED}) }
    }
    return len(client.events)
}

@(private)
eventsOfMessage :: proc(client: ^Client, message: spacetimedb.ServerMessage) {
    switch value in message {
    case spacetimedb.InitialConnection:
        hex: [64]u8
        append(&client.events, Event{kind = .CONNECTED, text = keep(client, transmute([]u8)spacetimedb.IdentityHex(value.identity, hex[:]))})
    case spacetimedb.SubscribeApplied:
        for table in value.rows.tables { rowEvents(client, .INSERT, table.table, table.rows) }
        append(&client.events, Event{kind = .SUBSCRIBED, request = value.request_id})
    case spacetimedb.SubscribeBatchApplied:
        for result in value.results {
            for table in result.rows.tables { rowEvents(client, .INSERT, table.table, table.rows) }
        }
        append(&client.events, Event{kind = .SUBSCRIBED, request = value.request_id})
    case spacetimedb.TransactionUpdate:
        updateEvents(client, value)
    case spacetimedb.ReducerResult:
        event: Event = {kind = .REDUCER, request = value.request_id, ok = value.outcome == .OK || value.outcome == .OK_EMPTY}
        switch value.outcome {
        case .ERROR:
            reader: spacetimedb.Reader = spacetimedb.ReaderMake(value.value)
            event.text = keep(client, transmute([]u8)spacetimedb.ReadString(&reader))
        case .INTERNAL_ERROR:
            event.text = keep(client, transmute([]u8)value.message)
        case .OK, .OK_EMPTY:
        }
        append(&client.events, event)
        if value.outcome == .OK { updateEvents(client, value.update) }
    case spacetimedb.SubscriptionError:
        append(&client.events, Event{kind = .SUBSCRIPTION_ERROR, request = value.request_id, text = keep(client, transmute([]u8)value.error)})
    case spacetimedb.UnsubscribeApplied, spacetimedb.OneOffQueryResult, spacetimedb.ProcedureResult:
    }
}

@(private)
updateEvents :: proc(client: ^Client, update: spacetimedb.TransactionUpdate) {
    for set in update.query_sets {
        for table in set.tables {
            rowEvents(client, .DELETE, table.table, table.deletes)
            rowEvents(client, .INSERT, table.table, table.inserts)
        }
    }
}

@(private)
rowEvents :: proc(client: ^Client, kind: EventKind, table: string, rows: spacetimedb.RowList) {
    for i in 0 ..< spacetimedb.RowListCount(rows) {
        append(&client.events, Event{kind = kind, table = keep(client, transmute([]u8)table), row = keepHex(client, spacetimedb.RowListRow(rows, i))})
    }
}

clientNextEvent :: proc(client: ^Client) -> bool {
    if client.current + 1 >= len(client.events) { return false }
    client.current += 1
    return true
}

clientEvent :: proc(client: ^Client) -> Event {
    if client.current < 0 || client.current >= len(client.events) { return {} }
    return client.events[client.current]
}

// For the errors of this library that GDScript can read
clientMessage :: proc(client: ^Client) -> string {
    return fmt.tprintf("%s", client.error)
}
