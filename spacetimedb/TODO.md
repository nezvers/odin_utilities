# spacetimedb: what is left

A task starts with `(high)`, `(medium)` (the default) or `(low)`; `(later)` is parked. `odin run tool/todo -- spacetimedb` prints the open ones.

- [x] Setup: references (SpacetimeDB, BitCraftPublic, python SDK, C++ bindings, cookbook, spacetime-studio) cloned untracked, the release of the server downloaded, the test module built; `SetupRun` for other libraries
- [x] A server of our own: start, wait for the ping, stop the tree; in memory for tests
- [x] REST: identity, publish, delete, schema, SQL, reducer call, logs
- [x] BSATN, websocket protocol v2 (client and server messages), websocket client, connection a game polls
- [x] A tested session: server, module, two clients, subscription, reducer, update, SQL (`odin test spacetimedb`, `odin run spacetimedb/tool/session`)

## Next, in the order of value
- [x] Modules in Odin: `module/` (the ABI imports, `__describe_module__` with the V9 description, `__call_reducer__`, tables of primitive columns, insert, scan, count, clear, log), `tool/build_module`, the example `module/example/basic`; the session test runs against it and against the Rust module
- [x] Modules in Odin, more: primary key + unique + auto increment (`TableInsertRow` returns the stored row), btree indexes, `TableFind`/`TableDeleteBy`/`TableUpdate`/`TableDelete`, identity/timestamp/option/array columns, scheduled reducers (`ReducerAddScheduled`); `module/example/rich` and its session test. Open: structs and enums as column types, views and procedures (V10 description), range scans, a table description from a struct by reflection
- [x] A client cache (`cache.odin`): rows by table and key prefix, reference counted for overlapping subscriptions, UPDATE events, an event list per frame, `CacheCollect` into typed rows with a reader proc; fixed capacities, no allocation
- [x] Code generation from the schema (`codegen.odin`, `tool/generate`): structs, readers and writers (options, arrays, enums, unions, identity, timestamps, wide integers), `Call<Reducer>`, `TablesAdd` for the cache (key size from the primary key), `SubscribeAll`; golden output in `fixtures/generated`. Open: indexes (`Find<Table>By<Index>` over the cache), event tables, views, procedures
- [x] `gdextension/godot_spacetimedb` (a sub library of the generic `gdextension` library): a GDExtension in Odin, class `SpacetimeDBClient` polled from GDScript, tested in headless Godot against a real server. What comes next is in its TODO.md (typed API from the generator, PackedByteArray, signals, cache)
- [x] TLS (`Endpoint.secure`: https and wss through `stream.odin` over p2p/tls13.odin, certificate checked against the host; live checks with `SPACETIMEDB_LIVE=1`)
- [x] Reconnect (`ConnectionReconnect`, `ConnectionMaintain` with backoff): same token, subscriptions again; `confirmed` reads (`ConnectionConfig.confirmed`). Open: the session id parameter
- [x] Websocket protocol v3 (several messages in one frame): offered first, the server's choice is `WebSocketProtocol`, `ConnectionPoll` hands out every message of a frame (`ServerMessageDecodeNext`); tested with a burst of 60 calls against a real server
- [x] Compressed frames: Gzip done (`ConnectionConfig.inflate`); Brotli is not in core:compress and is never asked for
- [x] `ConnectionCallProcedure`, `ConnectionSubscribeBatch` (the cache applies `SubscribeBatchApplied`), event tables in the cache. Open: views and procedures in the generator (schema v10)
- [x] Authentication with OIDC: `oidc` library, `auth.odin`, module claims (`module/jwt.odin`), tested against a real server; open: a real provider (SpacetimeAuth), the identity from `iss|sub` is done (`blake3`)
- [ ] (low) The test module of the library in more shapes (a table with a primary key and an index, a scheduled reducer, an event table, a view): the references have them under modules/ (sdk-test).
- [x] A sample game: `arena/` (a multiplayer game in the database, a window on raylib and Karl2D, p2p host and join through `tunnel/`); its own TODO.md has what is next
- [x] Server log file on every system (`ServerOptions.log_file`; on Windows through a batch file with a redirection)
- [x] (part) A server for a LAN session: `ServerOptions.lan` listens on 0.0.0.0, `LanEndpoint`. Open (later): announce it through the p2p discovery of odin_utilities, and the invite that carries the address
