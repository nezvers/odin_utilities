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
- [ ] (high) `godot_spacetimedb` (a separate library): a GDExtension in Odin (godot-odin bindings or the C API of GDExtension directly) that exposes Connection, subscriptions and reducer calls as Godot nodes and signals, polled from `_process`. First needs the cache and the generator above. Setup calls `spacetimedb.SetupRun` and fetches the Godot headers (`extension_api.json`, `gdextension_interface.h`) the same way.
- [ ] (medium) TLS (`wss://`, `https://`) for databases on maincloud or behind a proxy: p2p/tls13.odin is a TLS 1.3 client with verification, put the socket under it.
- [x] Reconnect (`ConnectionReconnect`, `ConnectionMaintain` with backoff): same token, subscriptions again; `confirmed` reads (`ConnectionConfig.confirmed`). Open: the session id parameter
- [ ] (medium) Websocket protocol v3 (several messages in one frame) and compressed frames (Gzip is in core:compress, Brotli is not).
- [x] `ConnectionCallProcedure`, `ConnectionSubscribeBatch` (the cache applies `SubscribeBatchApplied`), event tables in the cache. Open: views and procedures in the generator (schema v10)
- [ ] (medium) Authentication: the OIDC side (identities from an issuer, `POST /v1/identity/websocket-token`, SpacetimeAuth).
- [ ] (low) The test module of the library in more shapes (a table with a primary key and an index, a scheduled reducer, an event table, a view): the references have them under modules/ (sdk-test).
- [ ] (low) A sample game: players that move (BitCraftPublic and the Blackholio demo of clockworklabs are the models), with demo_kit, two windows against one server.
- [ ] (low) Windows: a log file for the server (a pipe that a thread drains), and `show_output` on every system.
- [ ] (later) Run the server of the library for a LAN session from a game: start with a listen address other than loopback, announce through the p2p discovery of odin_utilities.
