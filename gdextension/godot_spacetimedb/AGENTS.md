# godot_spacetimedb: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../../AGENTS.md](../../AGENTS.md); the user facing description is in README.md.

## Files
- This is the example and first user of `../` (odin_utilities/gdextension: interface, classes, adapters; read its AGENTS.md for the Godot side).
- `client.odin`: `Client` (one `spacetimedb.Connection`, an event list, the bytes of the events copied per poll). No Godot types here, so it can be tested and reused.
- `entry.odin`: `spacetimedb_entry` (the `entry_symbol`) and the class `SpacetimeDBClient : RefCounted` as a table of methods (name, argument kinds, result kind, an Odin proc on `ge.Value`s). To add a method add a row.
- `godot_test/godot_test.odin`: the integration test (builds the DLL into `test_project/bin`, starts a server, runs `test_project/test.gd` in headless Godot). `test_project/` is a minimal project with the `.gdextension` file.

## Gotchas learned
- Strings that the connection keeps by reference (host, database, queries) are cloned into the client, because a reconnect uses them later.
- The Godot side gotchas (property infos, sizes, contexts) are in `../AGENTS.md`.
