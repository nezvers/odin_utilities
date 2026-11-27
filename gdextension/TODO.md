# gdextension: what is left

A task starts with `(high)`, `(medium)` (the default) or `(low)`; `(later)` is parked. `odin run tool/todo -- gdextension` prints the open ones.

- [x] Classes as tables: methods with bool, int, String and PackedByteArray, both call paths; one sub library (`godot_spacetimedb`) tested in headless Godot
- [x] Signals (`Class.signals`, `Class.bind`, `Emit`)
- [x] Value kinds float, Vector2, Vector3 (arguments, results, signal arguments)
- [ ] (high) More value kinds: Array, Dictionary, StringName, objects (a Node as an argument or a result)
- [x] Virtual methods `_ready`, `_enter_tree`, `_exit_tree`, `_process`, `_physics_process` (`Class.virtuals`, a Node parent)
- [ ] (medium) Properties (registered properties with getters and setters) and exported enums
- [ ] (medium) Build tool: `odin run gdextension/tool/build -- <package> <project dir>` that builds for the host platform and writes the `.gdextension` file; Linux and macOS checks
- [ ] (medium) Call engine methods from Odin (`classdb_get_method_bind` with the hashes of `extension_api.json`)
- [ ] (low) Hot reload of the extension (`recreate_instance_func`)
