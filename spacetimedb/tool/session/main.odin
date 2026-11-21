package main

// A session of your own: `odin run spacetimedb/tool/session [-- --keep] [--port 3100] [--name chat] [--module path.wasm]`. Starts a SpacetimeDB server (the release that setup downloaded, in a
// folder of its own), publishes a module (the test module basic-rs, or yours), connects two clients with identities of their own, subscribes both to the table `person`, lets the first call the
// reducer `add` three times and prints what each client sees. The same path a game or an application walks, and what the test of the library checks. `--keep` leaves the server running for
// you to connect to (press Enter to stop it).

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:time"
import spacetimedb "../.."

main :: proc() {
    port: int = 3100
    name: string = "odin-session"
    module_path: string = spacetimedb.FixturePath("basic-rs")
    keep: bool
    for i := 1; i < len(os.args); i += 1 {
        switch os.args[i] {
        case "--keep": keep = true
        case "--port":
            i += 1
            if i < len(os.args) { port = strconv.parse_int(os.args[i]) or_else port }
        case "--name":
            i += 1
            if i < len(os.args) { name = os.args[i] }
        case "--module":
            i += 1
            if i < len(os.args) { module_path = os.args[i] }
        }
    }
    if module_path == "" || !os.exists(spacetimedb.ServerCliPath()) {
        fmt.println("run `odin run spacetimedb/tool/setup` first (the server and the test module)")
        os.exit(1)
    }
    module, read_error := os.read_entire_file(module_path, context.allocator)
    if read_error != nil {
        fmt.println("cannot read", module_path)
        os.exit(1)
    }

    root: string = fmt.tprintf("session_server_%d", port)
    defer os.remove_all(root)
    server: spacetimedb.Server
    fmt.printfln("starting the server on 127.0.0.1:%d ...", port)
    if !spacetimedb.ServerStart(&server, {root = root, port = port, in_memory = true}) {
        fmt.println("the server did not start")
        os.exit(1)
    }
    defer spacetimedb.ServerStop(&server)

    response: [8192]u8
    identity, token_view, made := spacetimedb.IdentityCreate(server.endpoint, response[:])
    if !made {
        fmt.println("no identity")
        os.exit(1)
    }
    token: string = fmt.tprintf("%s", token_view)
    fmt.println("owner identity:", identity)
    published: spacetimedb.HttpResult = spacetimedb.DatabasePublish(server.endpoint, name, module, token, response[:])
    fmt.printfln("publish %s: %d %s", name, published.status, string(published.body))
    if published.status != 200 { os.exit(1) }

    arena: runtime.Arena
    allocator: runtime.Allocator = runtime.arena_allocator(&arena)
    defer runtime.arena_destroy(&arena)
    receive, message: [2][1 << 16]u8
    clients: [2]spacetimedb.Connection
    queries: [1]string = {"SELECT * FROM person"}
    for i in 0 ..< 2 {
        if !spacetimedb.ConnectionOpen(&clients[i], {endpoint = server.endpoint, database = name}, receive[i][:], message[i][:]) {
            fmt.println("client", i, "could not connect:", clients[i].error)
            os.exit(1)
        }
        spacetimedb.ConnectionSubscribe(&clients[i], 1, queries[:])
    }
    defer { for i in 0 ..< 2 { spacetimedb.ConnectionClose(&clients[i]) } }

    for person in ([3]string{"Ada", "Grace", "Linus"}) {
        arguments: [64]u8
        args: spacetimedb.Writer = spacetimedb.WriterMake(arguments[:])
        spacetimedb.WriteString(&args, person)
        spacetimedb.ConnectionCallReducer(&clients[0], "add", spacetimedb.WriterBytes(&args))
    }

    // both clients are polled for a second: what they receive is printed as it comes
    start: time.Tick = time.tick_now()
    for time.tick_since(start) < time.Second {
        for i in 0 ..< 2 {
            for {
                received, got := spacetimedb.ConnectionPoll(&clients[i], allocator)
                if !got { break }
                describe(i, received)
            }
        }
        free_all(allocator)
        time.sleep(5 * time.Millisecond)
    }
    sql: spacetimedb.HttpResult = spacetimedb.DatabaseSql(server.endpoint, name, "SELECT * FROM person", token, response[:])
    fmt.println("SQL:", string(sql.body))
    if keep {
        fmt.printfln("the server runs on %s:%d, database %q: press Enter to stop", server.endpoint.host, server.endpoint.port, name)
        buffer: [16]u8
        _, _ = os.read(os.stdin, buffer[:])
    }
}

describe :: proc(client: int, message: spacetimedb.ServerMessage) {
    switch value in message {
    case spacetimedb.InitialConnection:
        fmt.printfln("client %d: connected, token of %d characters", client, len(value.token))
    case spacetimedb.SubscribeApplied:
        count: int
        for table in value.rows.tables { count += spacetimedb.RowListCount(table.rows) }
        fmt.printfln("client %d: subscription %d applied, %d rows", client, value.query_set_id, count)
    case spacetimedb.TransactionUpdate:
        show(client, value)
    case spacetimedb.ReducerResult:
        fmt.printfln("client %d: reducer request %d: %v", client, value.request_id, value.outcome)
        show(client, value.update)
    case spacetimedb.UnsubscribeApplied, spacetimedb.SubscriptionError, spacetimedb.OneOffQueryResult, spacetimedb.ProcedureResult, spacetimedb.SubscribeBatchApplied:
        fmt.printfln("client %d: %v", client, value)
    }
}

show :: proc(client: int, update: spacetimedb.TransactionUpdate) {
    for set in update.query_sets {
        for table in set.tables {
            for i in 0 ..< spacetimedb.RowListCount(table.inserts) {
                row: spacetimedb.Reader = spacetimedb.ReaderMake(spacetimedb.RowListRow(table.inserts, i))
                fmt.printfln("client %d: + %s %q", client, table.table, spacetimedb.ReadString(&row))
            }
        }
    }
}
