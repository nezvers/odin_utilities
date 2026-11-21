# gdextension: what is left

A task starts with `(high)`, `(medium)` (the default) or `(low)`; `(later)` is parked. `odin run tool/todo -- gdextension` prints the open ones.

- [x] Classes as tables: methods with bool, int, String and PackedByteArray, both call paths; one sub library (`godot_spacetimedb`) tested in headless Godot
- [ ] (high) Signals: `classdb_register_extension_class_signal` and emitting through `object_method_bind_call` (`emit_signal`), so a class can tell GDScript instead of being polled
- [ ] (high) More value kinds: float, Vector2/3, Array, Dictionary, StringName, objects (a Node as an argument or a result)
- [ ] (high) A `Node` parent with virtual `_process`/`_ready` (`get_virtual_func`), so a class works without a script that calls it every frame
- [ ] (medium) Properties (registered properties with getters and setters) and exported enums
- [ ] (medium) Build tool: `odin run gdextension/tool/build -- <package> <project dir>` that builds for the host platform and writes the `.gdextension` file; Linux and macOS checks
- [ ] (medium) Call engine methods from Odin (`classdb_get_method_bind` with the hashes of `extension_api.json`)
- [ ] (low) Hot reload of the extension (`recreate_instance_func`)
