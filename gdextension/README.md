# gdextension

Godot 4 GDExtensions in Odin without a C++ wrapper: the C interface of Godot (`gdextension_interface.h`) is used directly, and a class is a small table. A library of the repository that wants to be usable from Godot is a sub library here (`godot_spacetimedb`: SpacetimeDB from GDScript).

```odin
my_class: gdextension.Class = {
    name = "Counter", parent = "RefCounted",
    create = proc() -> rawptr { return new(int) },
    destroy = proc(instance: rawptr) { free(instance) },
    methods = {
        {"add", {.INT}, .INT, proc(instance: rawptr, a: []gdextension.Value) -> gdextension.Value {
            counter: ^int = cast(^int)instance
            counter^ += int(a[0].number)
            return {kind = .INT, number = i64(counter^)}
        }},
    },
}

classes: [1]^gdextension.Class = {&my_class}

@(export)
my_entry :: proc "c" (get: gdextension.GetProcAddress, library: gdextension.Library, initialization: ^gdextension.Initialization) -> gdextension.GdBool {
    return gdextension.Entry(get, library, initialization, classes[:])
}
```
Build the package as a DLL (`odin build <pkg> -build-mode:dll -out:<project>/bin/x.dll`), name `my_entry` as `entry_symbol` in the `.gdextension` file (see `godot_spacetimedb/test_project/`), and GDScript calls `Counter.new().add(3)`.

- Argument and result kinds: bool, int, String (UTF-8 bytes), PackedByteArray (bytes). Both the Variant call (untyped GDScript) and the native call (typed code) are made from the same method row.
- Callbacks run with a default context whose temp allocator is freed after every call.
- Build: `odin run gdextension/tool/build -- <package> <godot project> [--name N] [--entry symbol] [--release] [--force] [--import]` builds the dynamic library for this computer into `<project>/bin` and writes `<project>/<name>.gdextension` (all three platforms, the entry symbol found in the sources; an existing file is kept unless `--force`); `--import` lets Godot list the extension.
- Signals: a class lists `signals` (name, argument kinds), keeps the engine object that `bind` gives it, and calls `Emit(object, "name", {values})`; GDScript connects as usual (the template's `Counter.changed` and `noted`). Emit runs the connected callables at once on the calling thread.
- Virtual methods: `virtuals = {{"_process", proc(instance, delta)}}` with `parent = "Node"`: the class updates itself, no script polls it (`_ready`, `_enter_tree`, `_exit_tree`, `_process`, `_physics_process` only).
- Objects and the engine: an `OBJECT` value is the engine's pointer (a Node, a Resource ...); `ge.Call(object, "Node", "get_child_count", 894402480, {})` calls an engine method (the hash of the method is in `godot_api/extension_api.json`), arguments and result are Values (the template's `child_count`, `parent_of`, `place`). The extension must not keep an object pointer longer than the engine keeps the object.
- Engine classes: `gdextension/engine` has generated wrappers (`NodeGetChildCount(node)`, `Node2DSetPosition(node, {3, 4})`, `NodeGetName(node)`) for Object, Node, Node2D, Node3D, CanvasItem, Control, Label and Timer, so no hash is written by hand. More classes: `odin run gdextension/tool/bindings -- --classes Node,Sprite2D --out <file.odin> [--package engine] [--import ..]` (reads `godot_api/extension_api.json`, the dump of `godot --headless --dump-extension-api`). A wrapper returns `(result, ok)`; methods whose types `ge.Call` cannot carry are left out.
- Kinds: object, bool, int, float, String, PackedByteArray, PackedInt64Array (`ints`), PackedFloat64Array (`floats`), PackedStringArray (`items`), PackedInt32Array (`ints32`), PackedFloat32Array, PackedVector2Array, PackedVector3Array and PackedColorArray (`floats32`: the components one after the other), Vector2, Vector3, Array, Dictionary (`Value.real`, 32 bit floats in the engine).
- Properties: `properties = {{"total", .INT, "get", "set_total"}}` names a getter and a setter method; GDScript and the inspector then use `counter.total`.
- Array and Dictionary: `Value.items` (and `keys` for a Dictionary, String keys): flat, the elements are bool, int, float or String (anything else comes in as NONE and is left out of a Dictionary); nesting is not supported.
- Not here yet: property hints, enums, nested collections and object values. See TODO.md.

## Template and testing ground
`template/` is a copyable project (an extension with a `Counter` class, a Godot project, a headless test): start a new extension from it, and try a new feature of this library there first.

## Sub libraries
- `godot_spacetimedb/`: `SpacetimeDBClient` for GDScript (connect to a SpacetimeDB database, subscribe, call reducers, read events). Its README says how to use it; its test runs a headless Godot against a real server.

## Interface dump
`cd godot_api && godot --headless --dump-extension-api --dump-gdextension-interface` writes `extension_api.json` and `gdextension_interface.h` (git ignored): the reference for the structs of `interface.odin` and for the hashes of builtin methods.
