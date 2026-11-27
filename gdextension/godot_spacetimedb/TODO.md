# godot_spacetimedb: what is left

A task starts with `(high)`, `(medium)` (the default) or `(low)`; `(later)` is parked. `odin run tool/todo -- godot_spacetimedb` prints the open ones.

- [x] A class `SpacetimeDBClient` (RefCounted) with open, subscribe, call_reducer, poll and the event getters; tested in headless Godot against a real server
- [ ] (high) Typed API from the schema: the generator of `spacetimedb` (`tool/generate`) writes a GDScript or Odin class per table and reducer so a script reads `player.name` and calls `move_to(x, y)` instead of decoding hex
- [x] `PackedByteArray` in both directions (`call_reducer_bytes`, `event_row_bytes`; the hex versions stay)
- [ ] (high) Signals (`connected`, `row_inserted`, `row_deleted`, `reducer_result`) and a `Node` flavour that polls in `_process` by itself: needs signals and virtual methods in `gdextension` first
- [ ] (medium) The cache of `spacetimedb` inside the client: UPDATE events with the old row, `get_rows(table)` that a script reads without keeping its own copy
- [ ] (medium) Builds for Linux and macOS and a `tool/build` that makes the binaries and the `.gdextension` file for a project; an export check
- [x] A sample Godot project that uses the extension: `arena_project/` is the arena game (host, join, play) on the class `ArenaClient`, tested headless with a host and a guest in one process (`godot_test`)
- [x] Host and join are generic: `SpacetimeDBLobby` + `SpacetimeDBClient` work with any module and database name (`spacetimedb/session` `Lobby`), the arena is an example on top
- [ ] (medium) Signals (`ready`, `failed`, `guest_joined`) and a `Node` flavour that updates itself for `SpacetimeDBLobby` (and `ArenaClient`), with the same `gdextension` work as the signals of `SpacetimeDBClient`
- [ ] (medium) Try the Godot arena between two real windows and two computers (a host window and a join window on the clipboard code), and export a build with the module next to the project (`arena-odin.wasm` as a resource)
- [ ] (low) Run the SpacetimeDB server of a LAN game from the extension (`ServerStart` with `lan`)
- [ ] (low) Web export (`wasm32` GDExtension) once the websocket goes through the browser instead of a socket
