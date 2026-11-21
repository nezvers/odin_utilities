#+build !js
package spacetimedb

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_bsatn_writes_and_reads_the_same_values_back :: proc(t: ^testing.T) {
    buffer: [256]u8
    writer: Writer = WriterMake(buffer[:])
    WriteBool(&writer, true)
    WriteU8(&writer, 200)
    WriteU16(&writer, 0xBEEF)
    WriteU32(&writer, 0xDEADBEEF)
    WriteU64(&writer, 0x0123456789ABCDEF)
    WriteI32(&writer, -5)
    WriteI64(&writer, -1)
    WriteF32(&writer, 1.5)
    WriteF64(&writer, -2.25)
    WriteString(&writer, "héllo")
    WriteBytes(&writer, {1, 2, 3})
    WriteTag(&writer, 1)
    identity: Identity
    for i in 0 ..< 32 { identity[i] = u8(i) }
    WriteIdentity(&writer, identity)
    testing.expect(t, !WriterFailed(&writer))
    bytes: []u8 = WriterBytes(&writer)
    // the numbers are little endian: u16 0xBEEF is EF BE
    testing.expect_value(t, bytes[2], 0xEF)
    testing.expect_value(t, bytes[3], 0xBE)
    reader: Reader = ReaderMake(bytes)
    testing.expect(t, ReadBool(&reader))
    testing.expect_value(t, ReadU8(&reader), 200)
    testing.expect_value(t, ReadU16(&reader), 0xBEEF)
    testing.expect_value(t, ReadU32(&reader), 0xDEADBEEF)
    testing.expect_value(t, ReadU64(&reader), 0x0123456789ABCDEF)
    testing.expect_value(t, ReadI32(&reader), -5)
    testing.expect_value(t, ReadI64(&reader), -1)
    testing.expect_value(t, ReadF32(&reader), 1.5)
    testing.expect_value(t, ReadF64(&reader), -2.25)
    testing.expect_value(t, ReadString(&reader), "héllo")
    testing.expect_value(t, len(ReadBytes(&reader)), 3)
    testing.expect_value(t, ReadTag(&reader), 1)
    testing.expect(t, ReadIdentity(&reader) == identity)
    testing.expect(t, !ReaderFailed(&reader) && ReaderLeft(&reader) == 0)
    // too little room to write, too few bytes to read: remembered, and what is read after that is zero
    small: [3]u8
    tight: Writer = WriterMake(small[:])
    WriteU32(&tight, 1)
    testing.expect(t, WriterFailed(&tight))
    short_bytes: [2]u8 = {1, 2}
    short: Reader = ReaderMake(short_bytes[:])
    testing.expect_value(t, ReadU32(&short), 0)
    testing.expect(t, ReaderFailed(&short))
    // a length that cannot be true does not become an allocation
    absurd_bytes: [5]u8 = {0xff, 0xff, 0xff, 0x7f, 1}
    absurd: Reader = ReaderMake(absurd_bytes[:])
    testing.expect_value(t, ReadLength(&absurd), 0)
    testing.expect(t, ReaderFailed(&absurd))
}

@(test)
test_an_identity_is_shown_as_the_server_shows_it :: proc(t: ^testing.T) {
    text: string = "c200abcdef0123456789abcdef0123456789abcdef0123456789abcdef012345"
    identity, ok := IdentityFromHex(text)
    testing.expect(t, ok)
    testing.expect_value(t, identity[31], 0xc2)             // the text is the big end first: the BSATN has the little end first
    testing.expect_value(t, identity[0], 0x45)
    out: [64]u8
    testing.expect_value(t, IdentityHex(identity, out[:]), text)
    _, bad := IdentityFromHex("xyz")
    testing.expect(t, !bad)
}

@(test)
test_client_messages_are_encoded_as_the_protocol_has_them :: proc(t: ^testing.T) {
    buffer: [128]u8
    writer: Writer = WriterMake(buffer[:])
    queries: [1]string = {"SELECT * FROM person"}
    EncodeSubscribe(&writer, 7, 1, queries[:])
    bytes: []u8 = WriterBytes(&writer)
    testing.expect_value(t, bytes[0], 0)                       // the tag of Subscribe
    reader: Reader = ReaderMake(bytes[1:])
    testing.expect_value(t, ReadU32(&reader), 7)
    testing.expect_value(t, ReadU32(&reader), 1)
    testing.expect_value(t, ReadLength(&reader), 1)
    testing.expect_value(t, ReadString(&reader), "SELECT * FROM person")
    WriterReset(&writer)
    arguments: [32]u8
    args: Writer = WriterMake(arguments[:])
    WriteString(&args, "Ada")
    EncodeCallReducer(&writer, 9, "add", WriterBytes(&args))
    reader = ReaderMake(WriterBytes(&writer))
    testing.expect_value(t, ReadTag(&reader), 3)
    testing.expect_value(t, ReadU32(&reader), 9)
    testing.expect_value(t, ReadU8(&reader), 0)                // flags
    testing.expect_value(t, ReadString(&reader), "add")
    testing.expect_value(t, len(ReadBytes(&reader)), 4 + 3)
}

@(test)
test_server_messages_are_decoded_from_frames :: proc(t: ^testing.T) {
    arena: runtime.Arena
    allocator: runtime.Allocator = runtime.arena_allocator(&arena)
    defer runtime.arena_destroy(&arena)
    buffer: [512]u8
    // an InitialConnection
    writer: Writer = WriterMake(buffer[:])
    WriteU8(&writer, COMPRESSION_NONE)
    WriteTag(&writer, 0)
    identity: Identity
    identity[0], identity[1], identity[2] = 1, 2, 3
    WriteIdentity(&writer, identity)
    connection: ConnectionId
    connection[0], connection[1], connection[2] = 9, 8, 7
    WriteConnectionId(&writer, connection)
    WriteString(&writer, "token-text")
    body, framed := ServerFrame(WriterBytes(&writer))
    testing.expect(t, framed)
    message, ok := ServerMessageDecode(body, allocator)
    testing.expect(t, ok)
    initial, is_initial := message.(InitialConnection)
    testing.expect(t, is_initial && initial.identity == identity && initial.connection_id == connection && initial.token == "token-text")
    // a compressed frame is refused, a truncated message is not a message
    compressed_frame: [2]u8 = {COMPRESSION_BROTLI, 0}
    _, compressed := ServerFrame(compressed_frame[:])
    testing.expect(t, !compressed)
    _, truncated := ServerMessageDecode(body[:10], allocator)
    testing.expect(t, !truncated)
    // a TransactionUpdate: one query set, the table person with an insert (two rows of fixed size 4) and a delete
    WriterReset(&writer)
    WriteTag(&writer, 4)
    WriteLength(&writer, 1)
    WriteU32(&writer, 1)                    // query set id
    WriteLength(&writer, 1)                 // tables
    WriteString(&writer, "person")
    WriteLength(&writer, 1)                 // row updates of the table
    WriteTag(&writer, 0)                    // persistent
    WriteTag(&writer, 0)                    // inserts: FixedSize
    WriteU16(&writer, 4)
    WriteBytes(&writer, {1, 0, 0, 0, 2, 0, 0, 0})
    WriteTag(&writer, 1)                    // deletes: RowOffsets
    WriteLength(&writer, 1)
    WriteU64(&writer, 0)
    WriteBytes(&writer, {9, 9})
    message, ok = ServerMessageDecode(WriterBytes(&writer), allocator)
    testing.expect(t, ok)
    update, is_update := message.(TransactionUpdate)
    testing.expect(t, is_update && len(update.query_sets) == 1 && len(update.query_sets[0].tables) == 1)
    table: TableUpdate = update.query_sets[0].tables[0]
    testing.expect_value(t, table.table, "person")
    testing.expect_value(t, RowListCount(table.inserts), 2)
    testing.expect_value(t, RowListRow(table.inserts, 1)[0], 2)
    testing.expect_value(t, RowListCount(table.deletes), 1)
    testing.expect_value(t, len(RowListRow(table.deletes, 0)), 2)
    testing.expect(t, RowListRow(table.inserts, 2) == nil)
    // a reducer result that failed
    WriterReset(&writer)
    WriteTag(&writer, 6)
    WriteU32(&writer, 5)
    WriteI64(&writer, 123456)
    WriteTag(&writer, 3)
    WriteString(&writer, "no such reducer")
    message, ok = ServerMessageDecode(WriterBytes(&writer), allocator)
    result, is_result := message.(ReducerResult)
    testing.expect(t, ok && is_result && result.request_id == 5 && result.outcome == .INTERNAL_ERROR && result.message == "no such reducer" && result.timestamp == 123456)
    // a tag that is not a message
    unknown_bytes: [1]u8 = {200}
    _, unknown := ServerMessageDecode(unknown_bytes[:], allocator)
    testing.expect(t, !unknown)
}

@(test)
test_a_json_string_is_found_by_its_key :: proc(t: ^testing.T) {
    json: string = `{"identity": "abc", "token":"x.y.z", "n": 3}`
    value, ok := JsonString(json, "token")
    testing.expect(t, ok && value == "x.y.z")
    value, ok = JsonString(json, "identity")
    testing.expect(t, ok && value == "abc")
    _, missing := JsonString(json, "n")
    testing.expect(t, !missing, "a number is not a string")
    _, absent := JsonString(json, "other")
    testing.expect(t, !absent)
    value, ok = JsonString(`{"Success":{"database_identity":"d1","op":"created"}}`, "op")
    testing.expect(t, ok && value == "created")
}

// ---- a session of our own: the server, a module, two clients ---------------------------------------------------------------------------------------------------------

@(private = "file")
isUpdateOrResult :: proc(message: ServerMessage, user: rawptr) -> bool {
    #partial switch value in message {
    case TransactionUpdate, ReducerResult: return true
    }
    return false
}

@(private = "file")
isApplied :: proc(message: ServerMessage, user: rawptr) -> bool {
    _, applied := message.(SubscribeApplied)
    return applied
}

@(private = "file")
isInitial :: proc(message: ServerMessage, user: rawptr) -> bool {
    _, initial := message.(InitialConnection)
    return initial
}

@(private = "file")
contains :: proc(text: string, part: string) -> bool {
    return indexOf(transmute([]u8)text, part) >= 0
}

@(test)
test_a_session_with_a_module_in_rust :: proc(t: ^testing.T) {
    runSession(t, FixturePath("basic-rs"), 3199)
}

@(test)
test_a_session_with_a_module_in_odin :: proc(t: ^testing.T) {
    runSession(t, FixturePath("basic-odin"), 3198)
}

// The session: a server, a module published under a name, two clients subscribed to `person`, a reducer that adds a row (both clients get it), a reducer that refuses a call, the SQL answer
// and the log of the module. The same steps for a module in Rust and one in Odin: what the client sees does not depend on the language of the module.
@(private = "file")
runSession :: proc(t: ^testing.T, module_path: string, port: int) {
    if module_path == "" || !os.exists(ServerCliPath()) {
        fmt.println("[spacetimedb] no server or no test module: run `odin run spacetimedb/tool/setup` to test a session")
        return
    }
    module, read_error := os.read_entire_file(module_path, context.temp_allocator)
    testing.expect(t, read_error == nil)

    root: string = fmt.tprintf("spacetimedb_test_server_%d", port)
    defer os.remove_all(root)
    server: Server
    testing.expect(t, ServerStart(&server, {root = root, port = port, in_memory = true}), "the server starts and answers")
    defer ServerStop(&server)
    testing.expect(t, ServerPing(server.endpoint))

    // an identity, a module published under a name
    response: [8192]u8
    identity_hex, token_view, made := IdentityCreate(server.endpoint, response[:])
    testing.expect(t, made && len(identity_hex) == 64 && len(token_view) > 20, "the server makes an identity")
    token: string = fmt.tprintf("%s", token_view)               // the response buffer is used again below
    published: HttpResult = DatabasePublish(server.endpoint, "odin-session", module, token, response[:])
    testing.expectf(t, published.ok && published.status == 200, "the module is published: %d %s", published.status, string(published.body))
    op, has_op := JsonString(string(published.body), "op")
    testing.expect(t, has_op && op == "created")

    // two clients with identities of their own, both subscribed to the table
    arena: runtime.Arena
    allocator: runtime.Allocator = runtime.arena_allocator(&arena)
    defer runtime.arena_destroy(&arena)
    receive_a, message_a, receive_b, message_b: [1 << 16]u8
    first, second: Connection
    testing.expect(t, ConnectionOpen(&first, {endpoint = server.endpoint, database = "odin-session"}, receive_a[:], message_a[:]), "the first client connects")
    testing.expect(t, ConnectionOpen(&second, {endpoint = server.endpoint, database = "odin-session"}, receive_b[:], message_b[:]), "the second client connects")
    defer ConnectionClose(&first)
    defer ConnectionClose(&second)
    testing.expect(t, first.token_length > 0 && ConnectionToken(&first) != ConnectionToken(&second), "every client has an identity of its own")

    queries: [1]string = {"SELECT * FROM person"}
    // the second client keeps what it hears in a cache: the game side of the same session
    cache_slots: [16]CacheSlot
    cache_buckets: [16]i32
    cache_bytes: [1024]u8
    cache_events: [16]CacheEvent
    cache_tables: [2]CacheTable
    cache: Cache
    CacheInit(&cache, {slots = cache_slots[:], buckets = cache_buckets[:], bytes = cache_bytes[:], events = cache_events[:], tables = cache_tables[:]})
    person: int = CacheTableAdd(&cache, "person")
    for connection in ([2]^Connection{&first, &second}) {
        message, got := ConnectionWait(connection, isInitial, nil, allocator)
        testing.expect(t, got, "the server greets the client")
        _, is_initial := message.(InitialConnection)
        testing.expect(t, is_initial && connection.connected)
        testing.expect(t, ConnectionSubscribe(connection, 1, queries[:]) != 0)
        applied, applied_got := ConnectionWait(connection, isApplied, nil, allocator)
        testing.expect(t, applied_got, "the subscription is applied")
        rows, is_applied := applied.(SubscribeApplied)
        if connection == &second { CacheApply(&cache, applied) }
        total: int
        for table in rows.rows.tables { total += RowListCount(table.rows) }
        testing.expect(t, is_applied && total == 0, "the table starts empty (the server may leave an empty table out)")
    }
    free_all(allocator)

    // the first client calls the reducer add("Ada"): both clients get the new row
    arguments: [64]u8
    args: Writer = WriterMake(arguments[:])
    WriteString(&args, "Ada")
    request: u32 = ConnectionCallReducer(&first, "add", WriterBytes(&args))
    testing.expect(t, request != 0)
    seen_by: [2]bool
    for index in 0 ..< 2 {
        connection: ^Connection = &first if index == 0 else &second
        // the caller also gets the result of its reducer: the change comes in one of the two
        for !seen_by[index] {
            message, got := ConnectionWait(connection, isUpdateOrResult, nil, allocator)
            if !got { break }
            if index == 1 { CacheApply(&cache, message) }
            updates: [dynamic]TableUpdate
            updates.allocator = allocator
            #partial switch value in message {
            case TransactionUpdate:
                for set in value.query_sets { append(&updates, ..set.tables) }
            case ReducerResult:
                testing.expect(t, value.request_id == request && value.outcome != .ERROR && value.outcome != .INTERNAL_ERROR, "the reducer ran")
                for set in value.update.query_sets { append(&updates, ..set.tables) }
            }
            for table in updates {
                if table.table != "person" || RowListCount(table.inserts) != 1 { continue }
                row: Reader = ReaderMake(RowListRow(table.inserts, 0))
                testing.expect_value(t, ReadString(&row), "Ada")
                seen_by[index] = true
            }
        }
    }
    testing.expect(t, seen_by[0] && seen_by[1], "both clients saw the row")
    testing.expect_value(t, CacheCount(&cache, person), 1)
    testing.expect_value(t, len(CacheEvents(&cache)), 1)
    people_names: [4]string
    read_name :: proc(reader: ^Reader) -> string { return ReadString(reader) }
    testing.expect_value(t, CacheCollect(&cache, person, read_name, people_names[:])[0], "Ada")

    // a reducer that refuses: the call is rolled back and the caller is told (the Odin module refuses an empty name; the Rust one inserts it: only the first is checked for the error)
    nothing: [8]u8
    empty: Writer = WriterMake(nothing[:])
    WriteString(&empty, "")
    refused: u32 = ConnectionCallReducer(&first, "add", WriterBytes(&empty))
    testing.expect(t, refused != 0)
    for {
        message, got := ConnectionWait(&first, isUpdateOrResult, nil, allocator)
        if !got { break }
        if result, is_result := message.(ReducerResult); is_result && result.request_id == refused {
            if strings.has_suffix(module_path, "-odin.wasm") { testing.expect_value(t, result.outcome, ReducerOutcomeKind.ERROR) }
            break
        }
    }
    // a reducer without arguments that writes to the log of the database
    ConnectionCallReducer(&second, "say_hello", nil)
    for {
        message, got := ConnectionWait(&second, isUpdateOrResult, nil, allocator)
        if !got { break }
        if _, is_result := message.(ReducerResult); is_result { break }
    }
    logs: HttpResult = DatabaseLogs(server.endpoint, "odin-session", 20, token, response[:])
    testing.expect(t, logs.ok && contains(string(logs.body), "Hello, World!") && contains(string(logs.body), "Ada"), "the module wrote the names to the log")

    // a lost connection: the same client comes back with the same token and the subscription again, the cache is filled by the new answer
    token_before: string = strings.clone(ConnectionToken(&second), context.temp_allocator)
    identity_before: Identity = second.identity
    CacheClear(&cache)
    testing.expect(t, ConnectionReconnect(&second), "the client reconnects")
    _, greeted := ConnectionWait(&second, isInitial, nil, allocator)
    testing.expect(t, greeted && second.identity == identity_before && ConnectionToken(&second) == token_before, "the same identity")
    again, applied_again := ConnectionWait(&second, isApplied, nil, allocator)
    testing.expect(t, applied_again, "the subscription is applied again")
    CacheApply(&cache, again)
    testing.expect(t, CacheCount(&cache, person) >= 1, "the rows are back in the cache")

    // the same row by SQL over HTTP, then the database is deleted
    sql: HttpResult = DatabaseSql(server.endpoint, "odin-session", "SELECT * FROM person", token, response[:])
    testing.expect(t, sql.ok && sql.status == 200)
    testing.expect(t, contains(string(sql.body), "Ada"), "the row is in the database")
    deleted: HttpResult = DatabaseDelete(server.endpoint, "odin-session", token, response[:])
    testing.expect(t, deleted.ok && deleted.status == 200)
}

@(test)
test_procedure_and_batch_messages_are_encoded :: proc(t: ^testing.T) {
    buffer: [128]u8
    writer: Writer = WriterMake(buffer[:])
    EncodeCallProcedure(&writer, 4, "score", {1, 2})
    reader: Reader = ReaderMake(WriterBytes(&writer))
    testing.expect_value(t, ReadTag(&reader), 4)
    testing.expect_value(t, ReadU32(&reader), 4)
    testing.expect_value(t, ReadU8(&reader), 0)
    testing.expect_value(t, ReadString(&reader), "score")
    WriterReset(&writer)
    ids: [2]u32 = {5, 6}
    first, second: [1]string = {"SELECT * FROM a"}, {"SELECT * FROM b"}
    sets: [2][]string = {first[:], second[:]}
    EncodeSubscribeBatch(&writer, 3, ids[:], sets[:])
    reader = ReaderMake(WriterBytes(&writer))
    testing.expect_value(t, ReadTag(&reader), 5)
    testing.expect_value(t, ReadU32(&reader), 3)
    testing.expect_value(t, ReadLength(&reader, 1), 2)
    testing.expect_value(t, ReadU32(&reader), 5)
}
