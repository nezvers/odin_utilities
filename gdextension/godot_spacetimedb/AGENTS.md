# godot_spacetimedb: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../../AGENTS.md](../../AGENTS.md); the user facing description is in README.md.

## Files
- This is the example and first user of `../` (odin_utilities/gdextension: interface, classes, adapters; read its AGENTS.md for the Godot side).
- `client.odin`: `Client` (one `spacetimedb.Connection`, an event list, the bytes of the events copied per poll). No Godot types here, so it can be tested and reused.
- `entry.odin`: `spacetimedb_entry` (the `entry_symbol`) and the class `SpacetimeDBClient : RefCounted` as a table of methods (name, argument kinds, result kind, an Odin proc on `ge.Value`s). To add a method add a row.
- `SpacetimeDBClientNode` (in `entry.odin`): the Node flavour of the client, one `client_methods` table for both. Its `_process` polls and emits the events as signals (`clientEmitEvents`); `poll`/`next_event` on it would steal events. `test_project/test_node.gd` runs against the server of the first integration test.
- `lobby.odin`: the GENERIC class `SpacetimeDBLobby`: a thin table over the `Lobby` of `spacetimedb/session` (host and join for any module and database name; the game connects with `SpacetimeDBClient` to `endpoint_host/port`). The logic is in `spacetimedb/session/lobby.odin`, engine free: it clones the strings the session keeps by reference, copies the text of an error (the session keeps `tprintf` text that is freed after the call), opens the guest tunnel and sets `SetIdle`, and `LobbyLeave` steps the tunnel a few times after the game closed so the host hears the websocket close at once (without it the host keeps the player until the p2p timeout, more than 15 s). A module-level `active_host` there lets a guest in the same process step that host while it waits in a blocking call (the tests play both sides in one process).
- `arena_example/`: package `arena_example`, the arena as an EXAMPLE on top of a `Lobby` (class `ArenaClient`: database and module of the arena, the game client of `spacetimedb/arena/game`, `snapshot`). Nothing generic lives there: game independent features go to the lobby. `entry.odin` lists the classes (`classes`): delete the example entry to build without it.
- `arena_project/`: the Godot project of the arena (`main.gd` builds its windows in code); `test_arena.gd` (ArenaClient) and `test_lobby.gd` (the generic classes with the `basic` module) and `test_lobby_node.gd` (the Node flavour, signals only) are the headless tests; `bin/` and `.godot/` are git ignored.
- `godot_test/godot_test.odin`: the integration test (builds the DLL into `test_project/bin`, starts a server, runs `test_project/test.gd` in headless Godot). `test_project/` is a minimal project with the `.gdextension` file.

## Gotchas learned
- GDScript cannot infer the type of `var x := arena.method()` before the DLL that registers the class has been built (it says "Cannot infer the type" for every method): build the library first.
- Never kill all `spacetimedb-standalone` processes to clean up a test (a broad kill is not allowed here); a host stops its own server in `leave()`.
- Strings that the connection keeps by reference (host, database, queries) are cloned into the client, because a reconnect uses them later.
- The Godot side gotchas (property infos, sizes, contexts) are in `../AGENTS.md`.
