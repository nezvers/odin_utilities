# Demo kit

What every library demo is built on. A demo is written once (in the `demo_common/` of its library) against a small backend, and runs on raylib, on Karl2D
and headless. The kit also plays simulated user input into a demo and checks what it did, so a demo is a runtime test as well.

```
demo_kit/
├── input.odin       Input (keys, mouse, text) of one frame as plain data, Key, MouseButton, helpers (KeyPressed, AxisKeys...)
├── backend.odin     Backend: the table of procs a framework implements, Context: what a demo gets, Draw* / Texture* / Sound* / Camera* procs
├── sim.odin         Step, Player: simulated input and Checks as data
├── runner.odin      Demo, Runner (menu, switching), TestDemo / TestAll / RunTests, Report
├── headless.odin    a backend without a window or device, drawing is only counted
├── glue_raylib/          the raylib backend:  kit_raylib.Run("name", demos)
├── glue_karl2d/          the Karl2D backend:  kit_karl2d.Run("name", demos)
└── demo_kit_test.odin
```

## A demo
```odin
demo: kit.Demo = {name = "loop", init = init, update = update, draw = draw, script = script}

update :: proc(ctx: ^kit.Context) {
    if kit.KeyPressed(&ctx.input, .SPACE) { ... }
    if kit.MousePressed(&ctx.input) && !ctx.ui_hover { ... }     // ui_hover: the mouse is on the kit's demo menu
}
draw :: proc(ctx: ^kit.Context) {
    kit.DrawRect(ctx, {10, 10, 100, 20}, kit.GREEN)
    kit.DrawText(ctx, "hello", {10, 40}, 20, kit.BLACK)
}
```
Shapes, text, textures (`kit.TextureLoad(ctx, #load("file.png"))`, embedded, so no working directory matters), sound, a 2D camera and clipping are in the
backend. A demo that needs something else of a framework (3D, a framework specific draw proc) has an extra file in `demo_raylib/` or `demo_karl2d/`.

## Simulated input and runtime tests
```odin
script: []kit.Step = {
    kit.Wait(5),                                     // frames
    kit.Tap(.SPACE),                                 // pressed for one frame, let go the next
    kit.Hold(.D, 30),
    kit.Click({400, 300}),                           // move the mouse and press the left button
    kit.Drag({100, 100}, {300, 100}, 20),            // hold the button and move
    kit.Scroll(1), kit.Type("hello"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return value == 3 }, "what was expected"),
}
```
A step that takes time holds the steps behind it, the others happen in the same frame. A `Check` runs at the start of a frame, so it sees what the last update did.
The constructors are `contextless`, so a script can be a global.
Keep the positions a script clicks fixed numbers (not relative to the window size or to the width of a text): the same script runs on a headless 1280 x 720 screen and in real windows. A widget that has a label is found by the rectangle you gave it, aim at the inner part of its bar.

- `odin test <lib>/demo_common` : the scripts run headless (`kit.TestDemo`), a failed check fails the test with its message and frame.
- `odin run <lib>/demo_raylib -define:DEMO_TEST=true` : the same scripts in the window, you see the simulated input, the exit code is 1 on a failure.
- A demo without a script is a smoke test: it runs 60 frames (init, update, draw, finit).
- The `Report` says how many checks ran and failed, the frames and the draw calls.

## Backends
| | window | input | use |
|---|---|---|---|
| `kit_raylib.Run` | raylib | keyboard and mouse | `odin run demo_raylib` |
| `kit_karl2d.Run` | Karl2D | keyboard and mouse | `odin run demo_karl2d` |
| `kit.HeadlessInit` | none | a `Player` (the script) | tests |

## Screen capture tests
`kit.Capture("name")` is a script step: the pixels of the frame just drawn are compared with the golden image
`captures/<backend>/<name>.png` next to the script file (`#caller_location`). It runs only in a window and only with `-define:DEMO_CAPTURE=true`
(`odin run <lib>/demo_raylib -define:DEMO_TEST=true -define:DEMO_CAPTURE=true`), so `odin test` and normal runs ignore it.
- No golden image yet: the frame is written as the golden (look at it, commit it). Otherwise a pixel differs above `-define:DEMO_CAPTURE_TOLERANCE=8`
  per channel, and the step fails when more than 0.2 percent of the pixels differ; the frame is saved as `<name>.actual.png` (git ignored) next to the golden.
- `-define:DEMO_CAPTURE_UPDATE=true` replaces the golden images with the current frames.
- One folder per backend (fonts differ), and goldens depend on the window size and scale of the machine that made them.
- Karl2D reads the screen back through the 3D layer of the fork, so `DEMO_CAPTURE` makes `Run` start Karl2D with `depth_test`.
- `CaptureFrame` (pixels of the frame), `PngWrite`/`PngRead` (the writer compresses flat areas, a ui frame is about 50 KB) and `ImageDifference` are plain procs for your own checks.

The kit and `glue_karl2d` build for `js_wasm32` too (`capture_js.odin` and `exit_js.odin` are the stubs: no golden images, no process exit), so a demo can be a web page: `kit.RunnerInit` + `kit.RunnerStep` per frame from a web_build `init/step/shutdown` (see `browser_extension/youtube_shorts/host_karl2d`).

A new framework is one more backend: fill the `Backend` table (see `glue_raylib/raylib.odin`; `capture` may stay nil).

`odin test demo_kit -strict-style -vet`
