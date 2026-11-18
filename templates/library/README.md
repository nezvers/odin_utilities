# Example library (template)

Copy this folder to `odin_utilities/<lib>`, rename `example` (package names, the files, the imports), delete what the library does not need.
The structure is the same for every library of odin_utilities, so any of them is a reference for the others.

```
<lib>/
├── README.md                 what it is, the API in a few lines, how to run the demos and the tests
├── <lib>.odin                the core: framework agnostic, caller owned memory (more files when it grows, one concept each)
├── <lib>_test.odin           tests, `#+build !js` when the library builds for the web (else at the bottom of the tested file)
├── glue_raylib/<lib>_raylib.odin  glue that needs raylib (package <lib>_raylib)              optional
├── glue_karl2d/<lib>_karl2d.odin  glue that needs Karl2D (package <lib>_karl2d)              optional
├── demo_common/              the demos, written once against demo_kit: one file per demo, demos.odin lists them,
│                             demo_common_test.odin plays their scripts headless
├── demo_raylib/main.odin     one call: kit_raylib.Run("<lib>", demo_common.demos[:])
├── demo_karl2d/main.odin     one call: kit_karl2d.Run("<lib>", demo_common.demos[:])
└── .vscode/                  launch.json, tasks.json, settings.json: run and debug the demos (raylib, Karl2D), the tools (tool/<name>) and the tests (Debug Tests)
```

## Rules
- Core: no raylib, no Karl2D, no hidden allocations (`Init(thing, buffer)`), PascalCase procs prefixed by the abstraction, `UPPER_CASE` constants,
  typed locals, `assert` for preconditions, comments that say why.
- Demos: written against `kit.Context` (shapes, text, textures, sound, input, a camera) so the same code runs on raylib, on Karl2D and headless.
  What needs a framework (a glue draw proc, 3D) lives in `demo_raylib/` / `demo_karl2d/` as an extra file, never in `demo_common`.
- Every demo has a `script`: the input a person would give (`kit.Tap`, `kit.Hold`, `kit.Click`, `kit.Drag`, `kit.Type`...) and `kit.Check`s that say
  what has to come out. It is the runtime test: `odin test <lib>/demo_common` runs it headless, `odin run <lib>/demo_raylib -define:DEMO_TEST=true`
  plays it in a window and exits with 1 when a check fails.
- A demo menu is on the right when a library has more than one demo (mouse, or page up / page down).
- A framework specific demo (the fps controller in 3D with the Karl2D fork) is a normal `demo_<framework>/` with its own files, and says so in its README.

## Commands (from odin_utilities)
```
odin test <lib> -strict-style -vet                 # the library tests
odin test <lib>/demo_common -strict-style -vet     # the scripts of the demos, headless
odin run <lib>/demo_raylib                         # the demos
odin run <lib>/demo_karl2d
odin run <lib>/demo_raylib -define:DEMO_TEST=true  # the scripts, in a window
```
