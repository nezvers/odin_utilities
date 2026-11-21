# godot_spacetimedb: what is left

A task starts with `(high)`, `(medium)` (the default) or `(low)`; `(later)` is parked. `odin run tool/todo -- godot_spacetimedb` prints the open ones.

- [x] A class `SpacetimeDBClient` (RefCounted) with open, subscribe, call_reducer, poll and the event getters; tested in headless Godot against a real server
- [ ] (high) Typed API from the schema: the generator of `spacetimedb` (`tool/generate`) writes a GDScript or Odin class per table and reducer so a script reads `player.name` and calls `move_to(x, y)` instead of decoding hex
- [x] `PackedByteArray` in both directions (`call_reducer_bytes`, `event_row_bytes`; the hex versions stay)
- [ ] (high) Signals (`connected`, `row_inserted`, `row_deleted`, `reducer_result`) and a `Node` flavour that polls in `_process` by itself: `emit_signal` through `object_method_bind_call`, the virtual `_process`
- [ ] (medium) The cache of `spacetimedb` inside the client: UPDATE events with the old row, `get_rows(table)` that a script reads without keeping its own copy
- [ ] (medium) Builds for Linux and macOS and a `tool/build` that makes the binaries and the `.gdextension` file for a project; an export check
- [ ] (medium) A sample Godot project (two windows against one server) that uses the extension
- [ ] (low) Run the SpacetimeDB server of a LAN game from the extension (`ServerStart` with `lan`)
- [ ] (low) Web export (`wasm32` GDExtension) once the websocket goes through the browser instead of a socket
