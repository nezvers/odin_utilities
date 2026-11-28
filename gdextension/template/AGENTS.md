# gdextension/template: notes for agents

What is not obvious from the code. The rules for every library are in [../../AGENTS.md](../../AGENTS.md), the Godot side in [../AGENTS.md](../AGENTS.md), the use in README.md.

- This is a template and a testing ground, not a library: keep it small and make every new `gdextension` feature appear here first (a method row in `extension.odin`, a check in `godot_project/test.gd`, a line in `main.gd`), then in the real sub libraries.
- A result string has to outlive the call: `Counter.greeting` is the instance buffer; `context.temp_allocator` memory also lives until the end of the call and is the simple choice for results that are built per call (`reverse`).
- The test is in `template_test/` (not `test/`: see `../AGENTS.md`). It builds the DLL into `godot_project/bin` (git ignored) and runs Godot headless twice: `--script test.gd` and the main scene with `--quit-after`.
- `godot_project/.godot/` is made by the first `--import`; it is git ignored.
- The hot reload test (end of `template_test.odin`) builds the library a second time with `-define:TEMPLATE_VERSION=2` into `godot_project/bin_next/` (git ignored) and lets the plugin `addons/reload_test` copy it over `bin/`: after the test the library in `bin/` is the second build until the test (or the Build Extension task) builds the first again. `Counter.version` tells which one answers.
