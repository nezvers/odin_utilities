# demo_kit: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

## Backend
- `Backend` (table of procs: shapes, text, textures, sound, camera, clip, mouse capture) is implemented by `glue_raylib`, `glue_karl2d` and `HeadlessInit` (no window, drawing counted). `Input` is plain data per frame; `Context` is what a demo proc gets. `gui.odin`: Button/Toggle/Slider/Spinner.
- The raylib backend draws text from glyphs made at the drawn size with the exact advances of the font file (`sizedFace`, `drawText`, `measureText` in `glue_raylib`), as Karl2D dynamic fonts do. Do not go back to `DrawTextEx` on a scaled atlas (blurred letters, pictures differing from Karl2D). `FontLoad` bytes must outlive the font. `ui/glue_raylib` does the same for `Fonts` (cache in the struct).

## Scripted runtime tests
- A demo's `script` is a `[]kit.Step` (Wait, Tap, Hold, Click, Drag, MoveTo, Scroll, LookBy, Type, Check(proc, message)); a Player turns it into input. Constructors are contextless so a script can be a global.
- `odin test <lib>/demo_common` runs it headless; `odin run <lib>/demo_raylib -define:DEMO_TEST=true` plays it in the window (exit 1 on a failed check). No script = 60 frame smoke test.

## Screen capture tests
- Step `kit.Capture("name")` compares the frame with `captures/<backend>/<name>.png` next to the script; only in a window with `-define:DEMO_CAPTURE=true` (missing goldens are written, `DEMO_CAPTURE_UPDATE=true` replaces them). Headless skips it.
- `odin run demo_kit/tool/captures` (from odin_utilities; `-- ui reports`, `-- --karl2d`, `-- --update ui`, `-- --allow-new`, `-- --monitor <name>`) runs every library with Capture steps; exit 1 = changed picture, 2 = new one. Run it before committing a change to drawing, text layout or a style and look at every `.actual.png` it leaves.
- Windows go to the display named by `--monitor`, `DEMO_MONITOR` or the git ignored `demo_kit/monitor.txt`, sized independent of display scaling (Karl2D `disable_auto_scale_hint`, raylib resized after move): goldens are 1280 x 720 on every display.

## Log of a scripted run
- `log.odin`: `DEMO_LOG=stdout|stderr|<file>`, `DEMO_LOG_KINDS=input,reaction,frame` dump steps, input, checks, captures with timing; `kit.LogNote(ctx, ...)` adds a line from a demo; time in a line is simulated (two runs diff equal).

## Gotcha
- Strings with apostrophes break multi file bash heredocs: write demo files with the Write tool.
