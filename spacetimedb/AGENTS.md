# spacetimedb: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md. Next steps: `TODO.md`.

## Setup and server
- `setup.odin` `SetupRun(options)`: clones SpacetimeDB into `spacetimedb/SpacetimeDB` (vendored, untracked via `spacetimedb/.gitignore`), the other references into `odin_utilities/references/` (own `.gitignore *`), downloads the server release (`SPACETIMEDB_VERSION`) into `spacetimedb/bin`, builds `fixtures/basic-rs` with cargo (skipped without cargo). Other libraries call it from their setup. Run: `odin run spacetimedb/tool/setup`.
- `server.odin` `ServerStart/ServerStop`: start through the CLI with `--root-dir` (it makes the jwt keys and starts the standalone server as a child), so stop kills the whole tree. Output is discarded unless `show_output` (an `os.create` handle is not inherited by children on Windows; an inherited test pipe hangs the runner).

## Client
- `http.odin` `HttpRequest` into a caller buffer; `rest.odin`: identity, publish, delete, schema, SQL, call, logs.
- `bsatn/` is its own package (no sockets, builds for wasm); `bsatn_alias.odin` re-exports it. `Writer/Reader` work over caller memory and remember the first error.
- `protocol.odin`: websocket protocol v2 (`Encode...` for client messages, `ServerMessageDecode` with an allocator for arrays; strings and bytes point into the frame).
- `cache.odin`: client cache over caller storage (`CacheInit`, `CacheTableAdd(name, key_size)`, `CacheApply(message)`, `CacheEvents`, `CacheFind`, `CacheNext`, `CacheCollect`). Rows keep an 8 byte header in `bytes` (compacted when full); a row points into the cache until the next apply; events point into the frame. Tests: `cache_test.odin` and the session test.
- `codegen.odin` (`GenerateSource(schema_json, options)`, `#+build !js`) + `tool/generate`: Odin source from the schema JSON; `wide.odin` has the 128/256 bit readers it uses. `fixtures/generated/{basic,rich}` are the committed outputs of `fixtures/*.schema.json`; `codegen_test.odin` regenerates and compares them, compiles and tests them (`rich_test.odin` is by hand). After changing the generator regenerate them: `odin run spacetimedb/tool/generate -- --schema spacetimedb/fixtures/rich.schema.json --package rich --library ../../.. --out spacetimedb/fixtures/generated/rich/rich.odin`.
- `websocket.odin`: RFC 6455 client, non blocking, `WebSocketPoll`. `connection.odin`: `ConnectionOpen/Poll/Subscribe/SubscribeBatch/CallReducer/CallProcedure/Reconnect/Maintain`, asks for `compression=None`; the connection remembers its subscriptions (query strings by reference) and the token for a reconnect.

## Modules in Odin
- `module/` (package `spacetimedb_module`): module for `freestanding_wasm32`, fixed buffers, `Define(define)` called from an `__preinit__...` export, `TableAdd/ReducerAdd`, exports `__describe_module__` and `__call_reducer__`. Example `module/example/basic`.
- Build with `tool/build_module` / `BuildModule` = `web_build.WasmBuild` + `WasmInspect` (checks exports, memory, import namespaces).

## Tests and tools
- `spacetimedb_test.odin`: the session test is skipped when the server or module is missing. `tool/session` runs a session by hand. `fixtures/basic-rs`: Rust module (table `person`, reducer `add`).

## Where the truth is (shallow clones)
- `SpacetimeDB/crates/client-api-messages/src/websocket/v2.rs` the protocol; `crates/bindings-sys` the module ABI; `crates/bindings-cpp` a non Rust module model; `docs/docs/00300-resources` HTTP, BSATN, ABI docs.
- `references/`: BitCraftPublic, spacetimedb-python-sdk, spacetimedb-bindings-cpp, spacetimedb-cookbook, spacetime-studio.
- Not there yet: TLS socket, reconnect.
