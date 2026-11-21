# spacetimedb: what is left

A task starts with `(high)`, `(medium)` (the default) or `(low)`; `(later)` is parked. `odin run tool/todo -- spacetimedb` prints the open ones.

- [x] Setup: references (SpacetimeDB, BitCraftPublic, python SDK, C++ bindings, cookbook, spacetime-studio) cloned untracked, the release of the server downloaded, the test module built; `SetupRun` for other libraries
- [x] A server of our own: start, wait for the ping, stop the tree; in memory for tests
- [x] REST: identity, publish, delete, schema, SQL, reducer call, logs
- [x] BSATN, websocket protocol v2 (client and server messages), websocket client, connection a game polls
- [x] A tested session: server, module, two clients, subscription, reducer, update, SQL (`odin test spacetimedb`, `odin run spacetimedb/tool/session`)

## Next, in the order of value
- [ ] (high) Modules in Odin: a SpacetimeDB module is WebAssembly that exports `__describe_module__` and `__call_reducer__` and imports the host functions of `spacetime_10.x` (references/SpacetimeDB/crates/bindings-sys, crates/bindings-cpp is the model of a non Rust module). Odin builds `freestanding_wasm32`: write the module ABI (`module/`), a table and reducer registration that needs no reflection, the description of the module (RawModuleDef as BSATN), and a test module in Odin that the session test publishes instead of the Rust one. That makes the whole workflow Odin: server code and client code in one language, with shared types.
- [ ] (high) A client cache: the rows of the subscriptions kept by table and primary key (insert, update as a delete and an insert of the same key, delete), with callbacks or an event list per frame, typed rows (a `proc` that reads a row into a struct of the program) so that a game reads `players[]` and not BSATN. Fixed capacities, no allocation per frame.
- [ ] (high) Code generation from the schema (`GET /v1/database/<name>/schema?version=9`, or the module itself): an Odin file with the row structs, the readers and writers, the reducer calls (`CallAdd(&connection, "Ada")`) and the subscription helpers, like `spacetime generate` does for the other languages (references/SpacetimeDB/crates/codegen). The generator is a tool in this library.
- [ ] (high) `godot_spacetimedb` (a separate library): a GDExtension in Odin (godot-odin bindings or the C API of GDExtension directly) that exposes Connection, subscriptions and reducer calls as Godot nodes and signals, polled from `_process`. First needs the cache and the generator above. Setup calls `spacetimedb.SetupRun` and fetches the Godot headers (`extension_api.json`, `gdextension_interface.h`) the same way.
- [ ] (medium) TLS (`wss://`, `https://`) for databases on maincloud or behind a proxy: p2p/tls13.odin is a TLS 1.3 client with verification, put the socket under it.
- [ ] (medium) Reconnect with the token and the subscriptions again; the session id parameter of the connect URL; `confirmed` reads.
- [ ] (medium) Websocket protocol v3 (several messages in one frame) and compressed frames (Gzip is in core:compress, Brotli is not).
- [ ] (medium) Procedures (`CallProcedure`), views, event tables and the one off queries as helpers, the `SubscribeBatch`.
- [ ] (medium) Authentication: the OIDC side (identities from an issuer, `POST /v1/identity/websocket-token`, SpacetimeAuth).
- [ ] (low) The test module of the library in more shapes (a table with a primary key and an index, a scheduled reducer, an event table, a view): the references have them under modules/ (sdk-test).
- [ ] (low) A sample game: players that move (BitCraftPublic and the Blackholio demo of clockworklabs are the models), with demo_kit, two windows against one server.
- [ ] (low) Windows: a log file for the server (a pipe that a thread drains), and `show_output` on every system.
- [ ] (later) Run the server of the library for a LAN session from a game: start with a listen address other than loopback, announce through the p2p discovery of odin_utilities.
