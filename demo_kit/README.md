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
    if kit.MousePressed(&ctx.input) && !ctx.ui_hover { ... }     // ui_hover: the mouse is on the kit's demo dropdown (the box at the top right, and its list while it is open)
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
- `-define:DEMO_CAPTURE_UPDATE=true` replaces the golden images with the current frames (all of them: restore the files that did not change before committing).
- **`odin run demo_kit/tool/captures`** (from odin_utilities) runs the screenshot tests of every library that has `Capture` steps, in a window, and prints one line per library
  (`ui  raylib  12 compared, 0 new, 0 failed`, then a line per changed picture with the pixel count and the path of the `.actual.png`). `-- ui reports` limits it to those libraries, `-- --karl2d` runs the
  Karl2D demos too (their pictures are separate), `-- --update ui` replaces the stored pictures of a library. Exit code 0: every picture is as stored. 1: a picture changed or a demo failed. 2: pictures that
  did not exist were stored (a missing golden passes by itself, so it is reported until someone has looked at it: `-- --allow-new` says that is fine). Nothing runs it automatically: run it before committing a
  change to drawing, text layout or a style.
- The raylib backend draws text like Karl2D does: raylib scales one bitmap per font (blurred small text, whole pixel advances that crowd the letters), so the glue makes the glyphs of a font at the size they are drawn at (a cache of 12 sizes per font, from the file the caller gave `FontLoad`: it has to outlive the font), draws each glyph on a whole pixel and moves the pen by the exact advance of the file; the measure is the same sum, so the two frameworks lay out alike (no kerning pairs on either path). `ui_raylib` (the standalone glue of the ui library) does the same for the faces of `ui_raylib.Fonts` (`FontsLoad` keeps the embedded files; the cache of sizes is part of `Fonts`, `FontsUnload` frees it).
- Both backends draw text in Fira Code (`assets/fonts`, loaded by `kit_raylib.Init` / `kit_karl2d.Init`: `FONT_DEFAULT` is that font), so the only difference left is how each framework renders it. One folder per backend (the rendering differs). The pictures do **not** depend on the display or its scaling: a test window has exactly the size the demo asked for (1280 x 720), whatever Windows scales the display by
  (a Karl2D window on a 150 % display used to be 1920 x 1080). Karl2D is started with `disable_auto_scale_hint` in a test run, raylib's window is set to its size after it settled on its display; a window that
  cannot get its size stops the run with a message that says the display, its size and its scale instead of failing every picture.
- **Which display.** The environment variable `DEMO_MONITOR` (a part of the name of the display, without regard to case) moves the test window to that display (`kit.DisplayRequest`, `glue_raylib`, `glue_karl2d`); the tool sets it from
  `-- --monitor <name>`, else the variable, else the first line of the local file `demo_kit/monitor.txt` (git ignored: write the name of your test display there once). The tool looks the name up with Karl2D (raylib only knows
  "Generic PnP Monitor") and tells raylib where the display is (`DEMO_MONITOR_RECT`); a name nobody has stops the tool with the list of the connected displays. Each line of its report says where the run was
  (`on BenQ DL2215, scale 1.00, window 1280 x 720`). Without a request the window opens where the operating system puts it.
- Karl2D reads the screen back through the 3D layer of the fork, so `DEMO_CAPTURE` makes `Run` start Karl2D with `depth_test`.
- `CaptureFrame` (pixels of the frame), `PngWrite`/`PngRead` (the writer compresses flat areas, a ui frame is about 50 KB) and `ImageDifference` are plain procs for your own checks.

**The log of a run.** A failed check says one line; with the log on the whole run is written, one line for each event: the steps of the script as they start, the input that came of them (a position, a button, a key, a character, the wheel), the checks and the captures with their result and how many frames and seconds after the last input they were made (the reaction time), the notes a demo writes with `kit.LogNote(ctx, "selected node %d", i)`, and optionally a line for every frame. `[frame 15  t= 0.2500s  + 35.80 ms]`: the frame and the time are the simulated ones (a log of the same run is the same text, so two runs can be compared with a diff), the `+ ms` is the wall clock (what the run really took). Without a change of code: `DEMO_LOG=stdout|stderr|run.log` and `DEMO_LOG_KINDS=input,reaction,frame|all` in the environment (`DEMO_LOG=run.log odin test ui/demo_common`, or a demo executable with `-define:DEMO_TEST=true`), the same names as `-define:DEMO_LOG=...` / `-define:DEMO_LOG_KINDS=...`; the default kinds are input and reaction, `input` alone is the trace of the input simulator. In code: `kit.LogOpen(&log, "run.log", {.INPUT})` + `kit.TestDemo(demo, backend, log = &log)`, `kit.LogToBuffer` for a log in memory (a browser build, a test). See `log.odin`.

**Masking frames.** A whole picture is allowed to differ in 0.2 percent of its pixels (`CAPTURE_MAX_BAD`), which hides a change that is small: the corner of a node, the outline of a window, a line a pixel wide (the title band that covered the outline of a graph node differed in 452 pixels, 0.05 percent, and every picture passed). `kit.CaptureIn("name", {{x, y, w, h}, ...})` (up to `CAPTURE_FRAMES`, 4, frames) and `kit.CaptureAt("name", &frame)` (one frame that a `Check` set from the last frame, like `ClickAt`) mask the picture: only the pixels inside of the frames are stored and compared, and not one of them may differ by more than the tolerance. Anything else on the screen (a clock, a log that scrolls) is out of it. The golden image is the frames' pixels on a clear picture, the `.actual.png` is the whole frame. Used by the `graph` demo (`graph_node_selected_top`).

The kit and `glue_karl2d` build for `js_wasm32` too (`capture_js.odin` and `exit_js.odin` are the stubs: no golden images, no process exit), so a demo can be a web page: `kit.RunnerInit` + `kit.RunnerStep` per frame from a web_build `init/step/shutdown` (see `browser_extension/youtube_shorts/host_karl2d`).

A new framework is one more backend: fill the `Backend` table (see `glue_raylib/raylib.odin`; `capture` may stay nil).

`odin test demo_kit -strict-style -vet`

- In a scripted test (`-define:DEMO_TEST=true`) Escape does not close the window (`Runner.escape_exits` is off): a script can press Escape as input for the demo, like a dialog that closes with it. Outside of a test Escape ends the demo as before.

- `-define:DEMO_VECTOR_TEXT=slug` (or `scanline`) on a demo program: the text of the kit is drawn from the outlines of Fira Code by the font library (`odin_utilities/font`) instead of by the framework (the glues set `kit.DrawText` and `MeasureText` to a `TextSystem`). The pictures of such a run go to `captures/<backend>_<method>` (`raylib_slug`, `karl2d_scanline`...); `odin run demo_kit/tool/captures -- --vector-text slug [--karl2d] [library...]` runs them.

**Held keys repeat**: `Input.keys_repeat` is `keys_pressed` plus the keys that repeat while held (after `KEY_REPEAT_DELAY` 0.4 s, every `KEY_REPEAT_INTERVAL` 0.04 s), made by `InputRepeat` in the runner after the scripted input, for every backend and for scripts (`kit.Hold`). A text field or a list reads it (`KeyRepeated`); a game reads `keys_down` / `keys_pressed`, which never repeat.

**Waiting for something that is not on the clock of the script**: `kit.WaitUntil(check, "what is waited for", frames)` looks at `check` in every frame and goes on in that very frame when it is true (a condition that is true already costs no frame); when it is still false after `seconds` of REAL time (60 by default, multiplied by `TimeScale`: the environment variable `ODIN_SLOW`, see `wait_for`) the report says the message, like a failed `Check`, and the script goes on. Use it for a server that starts, a network that answers, a login that ends, a player that has to move: a fixed `Wait` or `Hold` is right on a quiet computer and short on a busy one (the arena's solo test failed now and then when the whole test suite ran at once, and passes with every core busy since it waits for the movement). `Wait` is for the layout of a screen (a click needs a frame of layout first). A `WaitUntil` is polled: its check must not have side effects; do those in a `Check` after it.
