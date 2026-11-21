# box2d_odin: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- Library (`package box2d_odin`): `helpers.odin` (Add* shape wrappers, Create* body/joint helpers), `camera.odin`, `input.odin`, `ui.odin` (immediate mode UI over a `Backend`), `sample.odin` (`Sample` + `SampleHost`), glue in `glue_raylib/` and `glue_karl2d/` (`InitDebugDraw`).
- `samples/` ports `box2d/samples/sample_*.cpp` (one file each, registered with `@(init)`, file private globals as state). `odin test samples` smoke tests every sample headless. Demos only supply input, `Backend` and debug draw. Vendor `vendor:box2d` matches the C repo in `box2d/` (v3.2+ API: `motionLocks`, `base` joint defs, `DrawLineFcn`).
