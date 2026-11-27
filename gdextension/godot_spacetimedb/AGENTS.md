# godot_spacetimedb: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../../AGENTS.md](../../AGENTS.md); the user facing description is in README.md.

## Files
- This is the example and first user of `../` (odin_utilities/gdextension: interface, classes, adapters; read its AGENTS.md for the Godot side).
- `client.odin`: `Client` (one `spacetimedb.Connection`, an event list, the bytes of the events copied per poll). No Godot types here, so it can be tested and reused.
- `entry.odin`: `spacetimedb_entry` (the `entry_symbol`) and the class `SpacetimeDBClient : RefCounted` as a table of methods (name, argument kinds, result kind, an Odin proc on `ge.Value`s). To add a method add a row.
- `arena.odin`: the class `ArenaClient` (the arena game with host and join, see README): an `Arena` per instance holds heap copies of the strings the session keeps by reference (`name`, `root`, `module`), the `Game`, and a `Host` or a `Guest` of `spacetimedb/arena/session`. `update` steps the session (a guest opens the game as soon as its stage is CONNECTED and the tunnel is up, with `SetIdle`), polls the game and smooths it; `snapshot` packs players and coins into bytes (layout at the top of the file, read with a StreamPeerBuffer). A module-level `active_host` lets a guest in the same process step that host while it waits in a blocking call (the test plays both sides in one process); `arenaLeave` steps the tunnel a few times after closing the game so the host hears the websocket close at once (without it the host keeps the player until the p2p timeout, more than 15 s). Error strings are copied into the instance: the session keeps `tprintf` text that is freed after the call.
- `arena_project/`: the Godot project of the arena (`main.gd` builds its windows in code, `test_arena.gd` is the headless test), `bin/` and `.godot/` are git ignored.
- `godot_test/godot_test.odin`: the integration test (builds the DLL into `test_project/bin`, starts a server, runs `test_project/test.gd` in headless Godot). `test_project/` is a minimal project with the `.gdextension` file.

## Gotchas learned
- GDScript cannot infer the type of `var x := arena.method()` before the DLL that registers the class has been built (it says "Cannot infer the type" for every method): build the library first.
- Never kill all `spacetimedb-standalone` processes to clean up a test (a broad kill is not allowed here); a host stops its own server in `leave()`.
- Strings that the connection keeps by reference (host, database, queries) are cloned into the client, because a reconnect uses them later.
- The Godot side gotchas (property infos, sizes, contexts) are in `../AGENTS.md`.
