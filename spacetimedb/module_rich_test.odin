#+build !js
package spacetimedb

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:testing"
import "core:time"

// A session with the module `module/example/rich`: what a module in Odin can do besides primitive columns, seen from a client that keeps a cache.

@(private = "file")
Pump :: struct {
    connection: ^Connection,
    cache: ^Cache,
    allocator: runtime.Allocator,
}

// Polls (and feeds the cache) until `done` says so or the time is out. True when it was done.
@(private = "file")
pumpUntil :: proc(pump: ^Pump, done: proc(pump: ^Pump, user: rawptr) -> bool, user: rawptr, timeout: time.Duration = 5 * time.Second) -> bool {
    start: time.Tick = time.tick_now()
    for time.tick_since(start) < timeout {
        message, got := ConnectionPoll(pump.connection, pump.allocator)
        if got {
            CacheApply(pump.cache, message)
            continue
        }
        if done(pump, user) { return true }
        time.sleep(2 * time.Millisecond)
    }
    return done(pump, user)
}

// Calls a reducer and waits for its result; every message that comes meanwhile goes to the cache
@(private = "file")
callReducer :: proc(pump: ^Pump, name: string, arguments: []u8) -> (outcome: ReducerOutcomeKind, text: string) {
    request: u32 = ConnectionCallReducer(pump.connection, name, arguments)
    start: time.Tick = time.tick_now()
    for time.tick_since(start) < 5 * time.Second {
        message, got := ConnectionPoll(pump.connection, pump.allocator)
        if !got {
            time.sleep(2 * time.Millisecond)
            continue
        }
        CacheApply(pump.cache, message)
        if result, is_result := message.(ReducerResult); is_result && result.request_id == request {
            if result.outcome == .ERROR {
                reader: Reader = ReaderMake(result.value)
                return result.outcome, fmt.tprintf("%s", ReadString(&reader))
            }
            return result.outcome, fmt.tprintf("%s", result.message)
        }
    }
    return .INTERNAL_ERROR, "no answer"
}

@(private = "file")
countAtLeast :: proc(pump: ^Pump, user: rawptr) -> bool {
    return CacheCount(pump.cache, (cast(^int)user)^) >= 2
}

@(test)
test_a_module_in_odin_with_keys_indexes_and_a_schedule :: proc(t: ^testing.T) {
    module_path: string = FixturePath("rich-odin")
    if module_path == "" || !os.exists(ServerCliPath()) {
        fmt.println("[spacetimedb] no server or no rich module: run `odin run spacetimedb/tool/setup`")
        return
    }
    module, read_error := os.read_entire_file(module_path, context.temp_allocator)
    testing.expect(t, read_error == nil)
    root: string = "spacetimedb_test_server_rich"
    defer ServerRemove(root)
    server: Server
    testing.expect(t, ServerStart(&server, {root = root, port = 3197, in_memory = true}), "the server starts")
    defer ServerStop(&server)

    response: [8192]u8
    _, token_view, made := IdentityCreate(server.endpoint, response[:])
    testing.expect(t, made)
    token: string = fmt.tprintf("%s", token_view)
    published: HttpResult = DatabasePublish(server.endpoint, "rich", module, token, response[:])
    testing.expectf(t, published.ok && published.status == 200, "the module is published: %d %s", published.status, string(published.body))

    arena: runtime.Arena
    allocator: runtime.Allocator = runtime.arena_allocator(&arena)
    defer runtime.arena_destroy(&arena)
    receive, message_buffer: [1 << 16]u8
    connection: Connection
    testing.expect(t, ConnectionOpen(&connection, {endpoint = server.endpoint, database = "rich", token = token}, receive[:], message_buffer[:]))
    defer ConnectionClose(&connection)

    slots: [64]CacheSlot
    buckets: [64]i32
    bytes: [8192]u8
    events: [32]CacheEvent
    tables: [4]CacheTable
    cache: Cache
    CacheInit(&cache, {slots = slots[:], buckets = buckets[:], bytes = bytes[:], events = events[:], tables = tables[:]})
    player: int = CacheTableAdd(&cache, "player", 8)
    board: int = CacheTableAdd(&cache, "board", 8)
    tick_log: int = CacheTableAdd(&cache, "tick_log", 8)
    pump: Pump = {&connection, &cache, allocator}

    _, greeted := ConnectionWait(&connection, isInitial, nil, allocator)
    testing.expect(t, greeted)
    queries: [3]string = {"SELECT * FROM player", "SELECT * FROM board", "SELECT * FROM tick_log"}
    ConnectionSubscribe(&connection, 1, queries[:])
    applied, got_applied := ConnectionWait(&connection, isApplied, nil, allocator)
    testing.expect(t, got_applied)
    CacheApply(&cache, applied)

    // a player with an automatic id, an identity, an option and an array
    buffer: [256]u8
    args: Writer = WriterMake(buffer[:])
    WriteString(&args, "Ada")
    WriteU32(&args, 3)
    WriteLength(&args, 2)
    WriteString(&args, "a")
    WriteString(&args, "bc")
    outcome, text := callReducer(&pump, "create_player", WriterBytes(&args))
    testing.expectf(t, outcome == .OK, "create_player: %v %s", outcome, text)
    testing.expect_value(t, CacheCount(&cache, player), 1)
    it: CacheIterator = {table = player}
    row, has_row := CacheNext(&cache, &it)
    testing.expect(t, has_row)
    reader: Reader = ReaderMake(row)
    testing.expect_value(t, ReadU64(&reader), 1)                       // the number that the database gave
    testing.expect_value(t, ReadString(&reader), "Ada")
    testing.expect_value(t, ReadU32(&reader), 3)
    identity: Identity = ReadIdentity(&reader)
    testing.expect(t, identity == connection.identity, "the owner is the caller")
    testing.expect_value(t, ReadTag(&reader), 1)                       // score: none
    testing.expect_value(t, ReadLength(&reader), 2)
    testing.expect_value(t, ReadString(&reader), "a")
    testing.expect_value(t, ReadString(&reader), "bc")
    testing.expect(t, ReadI64(&reader) > 0 && !ReaderFailed(&reader), "the timestamp of the call")

    // the name is unique: the second one is refused and nothing changes
    WriterReset(&args)
    WriteString(&args, "Ada")
    WriteU32(&args, 9)
    WriteLength(&args, 0)
    outcome, text = callReducer(&pump, "create_player", WriterBytes(&args))
    testing.expect_value(t, outcome, ReducerOutcomeKind.ERROR)
    testing.expect_value(t, CacheCount(&cache, player), 1)

    // an update by the primary key: the first call inserts, the second replaces the row (one UPDATE event)
    for points in ([2]u32{10, 20}) {
        WriterReset(&args)
        WriteU64(&args, 7)
        WriteString(&args, "Ada")
        WriteU32(&args, points)
        CacheClearEvents(&cache)
        outcome, text = callReducer(&pump, "set_points", WriterBytes(&args))
        testing.expectf(t, outcome == .OK, "set_points: %v %s", outcome, text)
    }
    testing.expect_value(t, CacheCount(&cache, board), 1)
    events_seen: []CacheEvent = CacheEvents(&cache)
    testing.expect(t, len(events_seen) == 1 && events_seen[0].kind == .UPDATE, "the second call is an update of the same key")

    // a delete by the unique index
    WriterReset(&args)
    WriteString(&args, "Ada")
    outcome, text = callReducer(&pump, "remove_player", WriterBytes(&args))
    testing.expectf(t, outcome == .OK, "remove_player: %v %s", outcome, text)
    testing.expect_value(t, CacheCount(&cache, player), 0)
    outcome, text = callReducer(&pump, "remove_player", WriterBytes(&args))
    testing.expect_value(t, outcome, ReducerOutcomeKind.ERROR)
    testing.expect_value(t, text, "no such player")

    // a scheduled reducer: it runs on its own, every 50 ms, until the schedule is cleared
    WriterReset(&args)
    WriteU64(&args, 50)
    outcome, text = callReducer(&pump, "start_ticks", WriterBytes(&args))
    testing.expectf(t, outcome == .OK, "start_ticks: %v %s", outcome, text)
    ticks: int = tick_log
    testing.expect(t, pumpUntil(&pump, countAtLeast, &ticks), "the scheduled reducer ran at least twice")
    callReducer(&pump, "stop_ticks", nil)
}
