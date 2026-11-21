# gdextension template

A testing ground for a GDExtension in Odin: copy this folder, change the class, press play in Godot. It has one class, `Counter`, with a method for every kind of argument and result that `odin_utilities/gdextension` supports (int, bool, String, PackedByteArray, several arguments, no result).

```
template/
  extension.odin            the class table and the entry symbol (`template_entry`)
  godot_project/            a Godot project: template.gdextension, main.tscn + main.gd (the testing ground), test.gd (the checks)
  template_test/            `odin test`: builds the extension, runs test.gd and the scene in a headless Godot
  .vscode/                  tasks: Build Extension, Open In Godot, Test; a debugger configuration for the test
```

## Use it
1. `odin build gdextension/template -build-mode:dll -out:gdextension/template/godot_project/bin/gdextension_template.dll` (task **Build Extension**; `.so` on Linux, `.dylib` on macOS, see the names in `template.gdextension`).
2. `godot --path gdextension/template/godot_project` (task **Open In Godot**) and press play: `main.gd` calls the class and prints. Edit `extension.odin`, rebuild, play again (close the Godot editor window before a rebuild on Windows: it keeps the DLL open).
3. `odin test gdextension/template/template_test -strict-style -vet` checks it without a window (Godot 4.4 or newer in PATH; skipped without it).

## Make your own
Copy the folder, then rename in four places: the package (`gdextension_template`), the class (`Counter`), the entry symbol (`template_entry` in `extension.odin` and `entry_symbol` in the `.gdextension` file) and the library file name (`gdextension_template` in the test, the tasks and the `.gdextension` file). Replace the method rows; each row is a name, the kinds of the arguments, the kind of the result and an Odin procedure on `ge.Value`s.

What a method can use is described in `../README.md`; what is not supported yet (signals, floats, vectors, objects, properties) is in `../TODO.md`.
