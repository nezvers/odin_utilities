# spacetimedb

SpacetimeDB (https://github.com/clockworklabs/SpacetimeDB) from Odin: set it up, run a server of your own, publish modules, connect clients, in a form a game or an application can adopt. SpacetimeDB is a
database that is also the server of an application: a *module* (a WebAssembly program) holds the tables and the *reducers* (the transactions) and runs inside of the database; a *client* connects by
websocket, *subscribes* to queries and receives the changes of the rows it asked for, and *calls reducers* to change them. This library is the Odin side of that, step by step:

| Step | State | Where |
|---|---|---|
| Setup: the references and the server, untracked | done | `setup.odin`, `tool/setup` |
| A server of your own, started and stopped from a program | done | `server.odin` |
| REST: identities, publish, delete, SQL, call, logs, schema | done | `rest.odin`, `http.odin` |
| BSATN and the websocket protocol v2 | done | `bsatn.odin`, `protocol.odin` |
| A client connection a game polls once a frame | done | `connection.odin`, `websocket.odin` |
| A session that is tested: server, module (Rust and Odin), two clients, rows, updates, an error, the log | done | `spacetimedb_test.odin`, `tool/session` |
| A client cache (the rows that are subscribed to, by table and key) and typed rows | next | TODO.md |
| Modules written in Odin (WebAssembly, the module ABI) | done (tables of primitive columns, reducers, lifecycle, log) | `module/`, `tool/build_module` |
| Code generation from a schema (row types, reducer calls) | next | TODO.md |
| The Godot GDExtension (a separate library: `godot_spacetimedb`) | planned | TODO.md |

## Quick start
```
odin run spacetimedb/tool/setup        # clones the references (untracked), downloads the server of the release, builds the test module (needs Rust for that step)
odin run spacetimedb/tool/session      # starts a server, publishes a module, two clients subscribe and call a reducer, prints what they see
odin test spacetimedb                  # the same checked by assertions (a few seconds; the session is skipped when the server or the module is not set up)
```
A library that builds on this one calls `spacetimedb.SetupRun(options)` from its own setup: the sources and the server are fetched once for all of them. The main repository of SpacetimeDB is vendored into this
library (`spacetimedb/SpacetimeDB/`, untracked: it is the source the protocol and the module ABI are written against, and what a build of the server for a platform without a release uses); the other references
are in `odin_utilities/references/` (ignored by a `.gitignore` of its own in the folder); `spacetimedb/bin/` (the server, the built modules) is ignored too.

## What a program does
```odin
server: spacetimedb.Server
spacetimedb.ServerStart(&server, {root = "run/server", port = 3100, in_memory = true})   // waits until it answers
defer spacetimedb.ServerStop(&server)

response: [8192]u8
_, token, _ := spacetimedb.IdentityCreate(server.endpoint, response[:])                 // an identity: keep the token, it is you next time
spacetimedb.DatabasePublish(server.endpoint, "chat", module_bytes, token, response[:])    // the .wasm of a module

connection: spacetimedb.Connection
spacetimedb.ConnectionOpen(&connection, {endpoint = server.endpoint, database = "chat"}, receive[:], message[:])
spacetimedb.ConnectionSubscribe(&connection, 1, {"SELECT * FROM message"})
// every frame of the game:
for {
    message, got := spacetimedb.ConnectionPoll(&connection, context.temp_allocator)
    if !got { break }
    // a SubscribeApplied has the rows now, a TransactionUpdate the inserts and deletes, a ReducerResult the answer to ConnectionCallReducer
}
```
A row is BSATN: `ReaderMake(RowListRow(list, i))` and the fields in the order of the table (`ReadString`, `ReadU32`, ...); the arguments of a reducer are written the same way with a `Writer`.

## A module in Odin
The server side is Odin too. `module/` (package `spacetimedb_module`) is the library of a module: you describe tables and reducers, the library exports what the database calls and imports what it offers (`module/abi.odin`).
```odin
people: module.Table

@(export)
__preinit__10_define :: proc "c" () { module.Define(define) }

define :: proc(m: ^module.Module) {
    people = module.TableAdd(m, "person", {{"name", .STRING}}, public = true)
    module.ReducerAdd(m, "add", {{"name", .STRING}}, add)
}

add :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    name: string = bsatn.ReadString(args)
    row: [256]u8
    writer: bsatn.Writer = bsatn.WriterMake(row[:])
    bsatn.WriteString(&writer, name)
    return module.TableInsert(people, bsatn.WriterBytes(&writer))        // "" is success, a text is an error: the call is rolled back
}
```
`odin run spacetimedb/tool/build_module -- path/to/package out.wasm` builds it with `web_build.WasmBuild` (`-target:freestanding_wasm32 -no-entry-point`: 25 KB for the example, `module/example/basic`) and checks the result: the exports `__describe_module__`, `__call_reducer__` and `memory` are there and only the namespaces of the ABI are imported, `DatabasePublish` or `spacetime publish --bin-path` publishes it. There is no heap in a module: the buffers are fixed arrays, a call gets an arena in `ctx.allocator`. A table of primitive columns, reducers with parameters, the lifecycle reducers (`.INIT`, `.ON_CONNECT`, `.ON_DISCONNECT`), `TableInsert`, `TableScan`, `TableCount`, `TableClear` and `Log` are there; the session test runs the same steps against the Rust module and the Odin one.

## What a module in Odin can do
Tables with a primary key, unique columns, an auto increment column and btree indexes; identity, timestamp, option and array columns; a reducer by name, lifecycle reducers and scheduled reducers; reads and deletes by an index, updates by a unique key, deletes by value (`module/example/rich`).

## Is Rust needed?
No. The server is a release binary that setup downloads, the client is Odin, a module can be Odin (`module/`), and a module is published over HTTP (the CLI is not needed for that). Rust is used for two optional things: the test module `fixtures/basic-rs` (without cargo setup skips it and the session test runs with the Odin module alone) and building the server from source on a platform that has no release. A module can also be written in C#, TypeScript or C++ with their own toolchains: any `.wasm` that follows the module ABI is published the same way.

## Code generation
`odin run spacetimedb/tool/generate -- --server 127.0.0.1:3000 --database chat --package game_data --library ../spacetimedb --out game/data.odin` (or `--schema file.json`) writes the row structs with `<Type>Read` / `<Type>Write`, a `Call<Reducer>(&connection, ...)` per reducer, `TablesAdd(&cache)` and `SubscribeAll(&connection, id)`. Then a game does `CacheCollect(&cache, tables.person, PersonRead, people[:])`.

## A game to try it with
`arena/` is a small multiplayer game whose world lives in a SpacetimeDB database, with a window on raylib and Karl2D; players find each other with p2p (an invite code, or one code through a free relay) and reach the host's database through `tunnel/`. See `arena/README.md`.

## TLS
Give the endpoint `secure = true` (port 443) to reach a database on maincloud or behind a proxy: `ConnectionOpen(&c, {endpoint = {host = "maincloud.spacetimedb.com", port = 443, secure = true}, database = "mygame"}, ...)`. The certificate is checked against the host (p2p `P2P_CA_FILE`, `P2P_TLS_VERIFY` apply).

## The cache
`Cache` keeps the rows of your subscriptions by table (`CacheApply` every message of `ConnectionPoll`), so a game reads rows and not messages: `CacheCollect(&cache, table, PersonRead, people[:])`, `CacheFind` by key, `CacheEvents` for what changed this frame (INSERT, UPDATE with the old row, DELETE). All storage is yours (slots, buckets, bytes, events); a full cache sets `failed` instead of growing.

## Design
- **No threads, no callbacks from other threads.** The socket is non blocking and `ConnectionPoll` is called when the program wants (a game frame, a Godot `_process`, a loop of a tool). Nothing in it runs when
  it is not called, so it fits an engine that owns its threads.
- **No hidden allocations.** The buffers of the socket, the send buffer and the writers are the caller's (or fixed arrays of the struct); decoding a message takes an allocator for its arrays (an arena that is
  cleared after each message), strings and byte slices point into the received frame. `-define` and the sizes of the buffers are the application's decision.
- **The protocol is the server's own.** `bsatn.odin` and `protocol.odin` are written from `spacetimedb/SpacetimeDB/crates/client-api-messages/src/websocket/v2.rs` and the BSATN document of its docs, and
  tested against a real server of the release the library names (`SPACETIMEDB_VERSION` in setup.odin). Frames are not compressed (`compression=None` is asked for), Brotli and Gzip are not read.
- **A server is a process.** The CLI makes the keys and starts the standalone server as a child; the library stops the whole tree. Everything the server writes lives in the folder you give.
- **The sources are the manual.** Setup clones SpacetimeDB into the library (server, protocol, module ABI, the C#, Rust and TypeScript SDKs, docs) and, into references/, BitCraftPublic (the server of a real MMO), the Python SDK, the C++ module
  bindings, the cookbook of clockworklabs and spacetime-studio of ElegonCode (a desktop manager that uses the REST side). They are the first place to look for how something is meant to work.

## Limits
- `ws://` and `http://` only (a database behind TLS needs a proxy for now); no reconnect; one websocket protocol (v2); no Brotli or Gzip frames; the JSON helper reads strings only.
- Modules in Odin: primitive column types only (no structs, enums, options or arrays of them in a table yet), no indexes, constraints, scheduled reducers, views or procedures, no automatic increment, a reducer has no return value, only the V9 description is written (TODO.md).
- On Windows the output of the server is thrown away unless `show_output` is set (a child does not inherit a file handle made by `os.create`); the log of what a module writes is `DatabaseLogs`.
- The CLI, when run, writes a `cli.toml` to the user's SpacetimeDB folder the first time; the server of the library keeps its own files in the `root` you pass.
