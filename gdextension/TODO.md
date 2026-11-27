# gdextension: what is left

A task starts with `(high)`, `(medium)` (the default) or `(low)`; `(later)` is parked. `odin run tool/todo -- gdextension` prints the open ones.

- [x] Classes as tables: methods with bool, int, String and PackedByteArray, both call paths; one sub library (`godot_spacetimedb`) tested in headless Godot
- [x] Signals (`Class.signals`, `Class.bind`, `Emit`)
- [x] Value kinds float, Vector2, Vector3 (arguments, results, signal arguments)
- [x] Array and Dictionary values (flat: bool, int, float, String elements; String keys)
- [x] PackedInt64Array, PackedFloat64Array, PackedStringArray (`PACKED_INTS`, `PACKED_FLOATS`, `PACKED_STRINGS`)
- [x] The other numeric packed arrays: `PACKED_INT32S` (`ints32`), `PACKED_FLOAT32S`, `PACKED_VECTOR2S`, `PACKED_VECTOR3S`, `PACKED_COLORS` (`floats32`), both call paths, in the template
- [x] Nested Arrays and Dictionaries (read down to `MAX_NESTING` = 8 levels, an Array that holds itself stops there), packed arrays inside them, and the `VARIANT` kind: an argument or result of any type (`echo`, `kind_of` in the template); a StringName or NodePath inside a Variant arrives as its text (`STRING`)
- [ ] (low) A StringName as its own argument and result kind (today a STRING argument refuses a StringName Variant); Rect2, Color, Vector2i and the other scalars as kinds
- [x] Virtual methods `_ready`, `_enter_tree`, `_exit_tree`, `_process`, `_physics_process` (`Class.virtuals`, a Node parent)
- [x] Properties over getter and setter methods (`Class.properties`)
- [ ] (low) Exported enums and property hints (ranges, file paths) for the inspector
- [x] Build tool `odin run gdextension/tool/build -- <package> <project dir>` (builds for this computer, writes the `.gdextension`, `--import`)
- [ ] (medium) Build tool: try it on Linux and macOS (the file names are written for all three, only Windows was run); cross builds
- [x] Objects as values (`OBJECT`) and engine calls from Odin (`ge.Call(object, class, method, hash, args)`, binds cached)
- [x] Typed wrappers for engine classes generated from `extension_api.json` (`tool/bindings`, package `engine`: Object, Node, Node2D, Node3D, CanvasItem, Control, Label, Timer)
- [ ] (low) Wrappers for methods with Array, Dictionary, Callable, Vector2i, Color, Rect2 ... arguments (needs those value kinds); more classes in `engine/` on demand
- [ ] (low) Hot reload of the extension (`recreate_instance_func`)
