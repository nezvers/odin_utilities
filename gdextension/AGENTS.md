# gdextension: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

## Files
- `interface.odin`: the used part of `gdextension_interface.h` (structs as the header lays them out, the functions looked up once from `get_proc_address` into `gd`, Variant and PackedByteArray helpers). Godot 4.7.2 was the reference; the class is registered with `classdb_register_extension_class4` (kept since 4.4).
- `class.odin`: the public API: `Class`, `Method`, `Value`, `Entry`. `registerClass` builds the property infos and method infos (heap, once), `callMethod` and `ptrCallMethod` are the two ways Godot calls a method.
- `tool/build`: the build tool (package main with tests): it calls `odin build -build-mode:dll` and writes the `.gdextension`; the entry symbol is the first line with `:: proc "c"` and `GetProcAddress` in the package's `.odin` files. Godot copies the loaded DLL as `~name.dll` into `bin/` (git ignore `bin/`).
- `template/`: the template and testing ground (see its AGENTS.md): every new feature of the library appears there first.
- `godot_spacetimedb/`: the example and first user (own AGENTS.md). `godot_api/`: dumps of the interface of Godot (git ignored).

## Gotchas learned
- Every `GDExtensionPropertyInfo` needs real `name`, `class_name` and `hint_string` (a valid empty String/StringName): a nil `hint_string` crashes Godot at load (signal 11 inside registration).
- Sizes: String and StringName are 8 bytes, a PackedByteArray 16, a Variant 24. A String made for Godot must be destroyed after the Variant copy is made (`variantString`).
- A builtin method called through `variant_get_ptr_builtin_method` needs a real result pointer even when ignored (`resize` writes an error code: nil crashes). The hashes of `size` and `resize` are from `extension_api.json`.
- Every `proc "c"` callback sets `context = runtime.default_context()` first; temp memory is freed at the end of each call.
- A DLL that Godot loads is copied as `~name.dll` next to it: git ignore `bin/`.
- A test folder must not be called `test`: `odin run tool/test` writes `test.exe` and the package exe would clash.
- Signals: registered with `classdb_register_extension_class_signal` (argument infos as for methods); `Emit` calls `Object.emit_signal` (vararg, hash 4047867050 from extension_api.json) through `object_method_bind_call` with the signal name as a StringName Variant first. All Variants it builds are destroyed with `variant_destroy`. A signal must not share a name with a method of the class (GDScript then sees the method: `connect` not found on Callable).
- Virtuals use `get_virtual_call_data_func` + `call_virtual_with_data_func` (the plain `get_virtual_func` callback has no userdata, so it cannot tell which proc to call): the data is the `Virtual` row, found by comparing the interned StringName pointers. The engine asks for every virtual of the parent; nil means not overridden. One table of methods can serve two classes (RefCounted and Node), but not by copying one global into another (not constant): use named procs and arrays.
- Array and Dictionary: read and written element by element through `array_operator_index*`, `dictionary_operator_index*` and the builtin methods `size`, `resize`, `keys` (hashes from extension_api.json). Strings are measured first (`string_to_utf8` with a nil buffer gives the length) so a big array does not allocate the 128 KB text buffer per element. An Array that arrives as a Variant is copied out with `to_array` and must be destroyed; a ptrcall argument is the engine's own and is not.
- Properties are registered after the methods; the engine looks the getter and setter up by name when they are used, so a name that is not a registered method fails only then. The setter StringName of a read only property is empty.
- Vectors are 32 bit floats in the engine (the usual build; a double precision build would break the native ptrcall layout). Adding an argument kind: a `ValueKind`, a `variantTypeOf` row, a row in both adapters and the helpers in interface.odin.
