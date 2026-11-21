# godot_spacetimedb: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

## Files
- `gdextension.odin`: the used part of `gdextension_interface.h` (structs as the header lays them out, the functions looked up once from `get_proc_address`). Godot 4.7.2 was the reference; the class is registered with `classdb_register_extension_class4` (kept since 4.4).
- `client.odin`: `Client` (one `spacetimedb.Connection`, an event list, the bytes of the events copied per poll). No Godot types here, so it can be tested and reused.
- `entry.odin`: `spacetimedb_entry` (the `entry_symbol`), the class `SpacetimeDBClient : RefCounted`, the method table `methods` (name, argument kinds, result kind, an Odin proc on plain `Value`s) and two adapters: `callMethod` (Variants, untyped GDScript) and `ptrCallMethod` (native types, typed GDScript). To add a method add a row and raise `METHOD_COUNT` (the static arrays hold 32).
- `godot_test/godot_test.odin`: the integration test (builds the DLL into `test_project/bin`, starts a server, runs `test_project/test.gd` in headless Godot). `test_project/` is a minimal project with the `.gdextension` file.

## Gotchas learned
- Every `GDExtensionPropertyInfo` needs real `name`, `class_name` and `hint_string` (a valid empty String/StringName): a nil `hint_string` crashes Godot at load (signal 11 inside registration).
- Sizes: String and StringName are 8 bytes, a Variant 24. A String made for Godot must be destroyed with the String destructor after the Variant copy is made (`variantString`).
- Every `proc "c"` callback sets `context = runtime.default_context()` first; temp memory is freed at the end of each call.
- A DLL that Godot loads is copied as `~name.dll` next to it: git ignore `bin/`.
- Strings that the connection keeps by reference (host, database, queries) are cloned into the client, because a reconnect uses them later.
