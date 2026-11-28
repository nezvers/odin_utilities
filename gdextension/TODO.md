# gdextension: what is left

A task starts with `(high)`, `(medium)` (the default) or `(low)`; `(later)` is parked. `odin run tool/todo -- gdextension` prints the open ones.

- [x] Classes as tables: methods with bool, int, String and PackedByteArray, both call paths; one sub library (`godot_spacetimedb`) tested in headless Godot
- [x] Signals (`Class.signals`, `Class.bind`, `Emit`)
- [x] Value kinds float, Vector2, Vector3 (arguments, results, signal arguments)
- [x] Array and Dictionary values (flat: bool, int, float, String elements; String keys)
- [x] PackedInt64Array, PackedFloat64Array, PackedStringArray (`PACKED_INTS`, `PACKED_FLOATS`, `PACKED_STRINGS`)
- [x] The other numeric packed arrays: `PACKED_INT32S` (`ints32`), `PACKED_FLOAT32S`, `PACKED_VECTOR2S`, `PACKED_VECTOR3S`, `PACKED_COLORS` (`floats32`), both call paths, in the template
- [x] Nested Arrays and Dictionaries (read down to `MAX_NESTING` = 8 levels, an Array that holds itself stops there), packed arrays inside them, and the `VARIANT` kind: an argument or result of any type (`echo`, `kind_of` in the template); a StringName or NodePath inside a Variant arrives as its text (`STRING`)
- [x] The plain structs as kinds (Vector2i, Vector3i, Vector4, Vector4i, Rect2, Rect2i, Color, Quaternion, Plane in `real`; AABB, Transform2D, Basis, Transform3D, Projection in `floats32`) and StringName and NodePath (`text`), both call paths, inside Arrays and Dictionaries; the template checks each
- [ ] (low) Kinds for RID, Callable, Signal and PackedVector4Array (they come as NONE, nil as a result)
- [x] Virtual methods `_ready`, `_enter_tree`, `_exit_tree`, `_process`, `_physics_process` (`Class.virtuals`, a Node parent)
- [x] Properties over getter and setter methods (`Class.properties`)
- [ ] (low) Exported enums and property hints (ranges, file paths) for the inspector
- [x] Build tool `odin run gdextension/tool/build -- <package> <project dir>` (builds for this computer, writes the `.gdextension`, `--import`)
- [ ] (medium) Build tool: try it on Linux and macOS (the file names are written for all three, only Windows was run); cross builds
- [x] Objects as values (`OBJECT`) and engine calls from Odin (`ge.Call(object, class, method, hash, args)`, binds cached)
- [x] Typed wrappers for engine classes generated from `extension_api.json` (`tool/bindings`, package `engine`: Object, Node, Node2D, Node3D, CanvasItem, Control, Label, Timer)
- [x] Wrappers for methods with Array, Dictionary, Variant, Vector2i, Color, Rect2 and the other structs and packed arrays as arguments or results (tool/bindings; typed Arrays only as results); 495 wrappers became 583 for the same classes
- [ ] (low) Wrappers for methods with Callable, Signal or RID; more classes in `engine/` on demand
- [x] Hot reload of the extension: every class gives `recreate_instance_func`, the `.gdextension` says `reloadable = true` (the build tool writes it); tested in a headless editor (a second build replaces the loaded library, an object made before keeps working and gets its properties back)
