# gdextension: what is left

A task starts with `(high)`, `(medium)` (the default) or `(low)`; `(later)` is parked. `odin run tool/todo -- gdextension` prints the open ones.

- [x] Classes as tables: methods with bool, int, String and PackedByteArray, both call paths; one sub library (`godot_spacetimedb`) tested in headless Godot
- [x] Signals (`Class.signals`, `Class.bind`, `Emit`)
- [x] Value kinds float, Vector2, Vector3 (arguments, results, signal arguments)
- [x] Array and Dictionary values (flat: bool, int, float, String elements; String keys)
- [ ] (medium) More value kinds: nested Arrays and Dictionaries, typed packed arrays (PackedInt64Array, PackedStringArray, PackedFloat64Array), Variant, StringName, objects (a Node as an argument or a result)
- [x] Virtual methods `_ready`, `_enter_tree`, `_exit_tree`, `_process`, `_physics_process` (`Class.virtuals`, a Node parent)
- [x] Properties over getter and setter methods (`Class.properties`)
- [ ] (low) Exported enums and property hints (ranges, file paths) for the inspector
- [x] Build tool `odin run gdextension/tool/build -- <package> <project dir>` (builds for this computer, writes the `.gdextension`, `--import`)
- [ ] (medium) Build tool: try it on Linux and macOS (the file names are written for all three, only Windows was run); cross builds
- [ ] (medium) Call engine methods from Odin (`classdb_get_method_bind` with the hashes of `extension_api.json`)
- [ ] (low) Hot reload of the extension (`recreate_instance_func`)
