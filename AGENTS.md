# odin_utilities: agent guide

A collection of Odin libraries.
One library per directory, all with the same structure so any of them is a reference and a template (`templates/library`).
Shared assets: `assets/` (textures, fonts, sounds, gltf). `references/` is git ignored space for local checkouts of projects a library was ported from or follows (Clay, Dear ImGui). `karl2d/` is the Karl2D checkout that the `glue_karl2d` packages import by relative path (a directory junction or a clone, see Repository map).
Stale build outputs in a library folder (`demo.exe`, `*.pdb`, `log.txt`) are git ignored.

## Agent protocol (token economy)
- Start from this file, then only the `AGENTS.md` of the library in work; the library `README.md` is for users, read it only for its public API.
- Search before reading: `grep` a name, read the lines around it. Read a source file whole only when editing most of it.
- Facts live in one place: a library fact in its `AGENTS.md`, a cross library fact here. Keep a note short (what is not obvious from code, why), no history, no copies of code.
- When structure, a command or a rule changes, update the matching `AGENTS.md` in the same commit.
- Finish with the commands of "Commands" below; report outcome in a few lines.

## Per library notes (read only the one you touch)
Every library below has its own `AGENTS.md` (`CLAUDE.md` there only imports it) with what is not obvious from the code: file roles, decisions, limits, commands. Open `<lib>/AGENTS.md` before working in `<lib>`; do not read the others. Big inventories live in `<lib>/docs/` (grep them by name, do not read whole).

`ui`, `file_browser`, `font`, `tilemap`, `tween`, `grid_collision_map`, `quadtree`, `microui`, `atlas_packer`, `box2d_odin`, `3d_models`, `hot_reload`, `web_build`, `web_serve`, `scene`, `serial`, `signal`, `ai_messaging`, `reports`, `p2p`, `browser_extension`, `icons`, `unicode_data`, `simd`, `spacetimedb`, `oidc`, `gdextension` (with `gdextension/godot_spacetimedb`), `scratch`, `thread_lanes`, `wait_for`, `blake3`, `demo_kit`

## Library structure (every odin_utilities library, template in odin_utilities/templates/library)
```
<lib>/  README.md  <lib>.odin (+ more files)  <lib>_test.odin (#+build !js when the lib builds for web, else tests at the bottom of the tested file)
        glue_raylib/<lib>_raylib.odin  glue_karl2d/<lib>_karl2d.odin   (glue, only what needs the framework)
        demo_common/   demos written ONCE against odin_utilities/demo_kit: one file per demo (`kit.Demo` with init/finit/update/draw/script), demos.odin lists them,
                       demo_common_test.odin plays the scripts headless
        demo_raylib/main.odin   one call: kit_raylib.Run("<lib>", demo_common.demos[:])
        demo_karl2d/main.odin   one call: kit_karl2d.Run("<lib>", demo_common.demos[:])
        .vscode/       launch.json, tasks.json, settings.json: REQUIRED, see below
```
- **Every library has a `.vscode/` folder** (`launch.json`, `tasks.json`, `settings.json` with `"project_name": "demo"`; the executables are git ignored), so that opening the library folder in VS Code runs and debugs what it has. Copy
  `templates/library/.vscode` and keep what applies: `Run Debug` / `Run Release` for `demo_raylib`, `Run Debug Karl2D` / `Run Release Karl2D` for `demo_karl2d` (a library with only one of them keeps only those),
  one `Build <Tool>` task and `Run <tool> (...)` configurations with the usual arguments for every program in `tool/<name>` (see `reports`, `ai_messaging`, `p2p`), and `Debug Tests` (a task that builds the tests with
  `odin build . -build-mode:test -debug -out:${config:project_name}_test.exe` and a configuration that runs that executable under the debugger, so breakpoints work inside tests) plus the tasks `Test` and `Check`:
  all libraries without demos have at least `Debug Tests`. Tasks run in the library folder (`cwd` = `${workspaceFolder}`), build with `-strict-style -vet`, and have the `.bin` variants for Linux and macOS like the others.
  A new library, a new demo or a new tool is not finished until its `.vscode` runs it (try the task once).
- Every library keeps its raylib demo in `demo_raylib/` (package `demo_raylib`) and its karl2d demo in `demo_karl2d/`, both thin. VS Code tasks build with `-out:${config:project_name}.exe` (`project_name` = `demo`).
- A demo that needs something the kit does not have (3D, a framework specific draw proc) puts the framework part in an extra file of `demo_raylib/` / `demo_karl2d/` and hooks it into demo_common (see fps_controller: `SceneDrawer`). The Karl2D 3D demo needs the custom fork, said in that README.
- A library that draws (tilemap, box2d_odin debug draw) also gets a `kit/` glue package (`tilemap/kit`, `box2d_odin/kit`: package `<lib>_kit`) that draws through `kit.Context`, so its demos stay in demo_common. Glue that is only for one framework (input, scene loaders, mic_meter) is reached from demo_common through an adapter table or the demo lives in `demo_<framework>/`.
- Non visual libraries (serial, task, web_serve) have no demos.

## Repository map
- `<lib>/` - one library per directory (tilemap, input, tween, timer, ui, sprite, ...).
- karl2d - a checkout of a Karl2D fork (upstream plus the embed commits and the 3D layer, branch render3d), not part of these libraries; it has its own rules.
- Libraries import karl2d by relative path, e.g. `import "../../karl2d"` from tilemap/glue_karl2d.

## Library style (see tilemap as reference)
- Libraries are framework agnostic. Framework specific drawing lives in sub packages (`glue_raylib/`, `glue_karl2d/`) named `<lib>_<framework>.odin`.
- No hidden allocations: user provides buffers/slices (`TilemapInit(position, size, tile_size, buffer)`).
- Procedures are PascalCase prefixed by the abstraction: `TilemapGetTile`, `TileAtlasInit`, `AutotileRuleUpdateCell`, `DualGridUpdateTilemap`. Constants are UPPER_CASE (`TILE_EMPTY`). Types are PascalCase.
- Typed locals: `name:Type = value`. `assert` for preconditions. Comments describe each proc and non-obvious steps.
- Demo code uses snake_case procs.
- A feature that uses data + derived output takes input and output tilemaps (see `rule_tile.odin`, `dual_grid.odin`).
- Keep comments in the code; explain why, not what.

## Commands (run in odin_utilities, tilemap shown)
- `odin check demo_raylib -strict-style -vet` and `odin check demo_karl2d -strict-style -vet`
- `odin run demo_raylib`, `odin run demo_karl2d`
- Tests live at the bottom of the library or glue source file they test (`@(test)` procs, no separate test files for new code, none for demos): `odin test <lib> -strict-style -vet` from odin_utilities (3d_models: `odin test .` inside it, it loads an asset by relative path). Glue packages that call raylib can't run under `odin test` on this machine (static raylib breaks `os.args` in the runner), only their raylib-free logic is tested. karl2d glue tests cover the CPU side only (no window).
- What is left to do: `odin run tool/todo` prints the report of the category being worked on (open tasks by value, the neighbouring categories when it is clear, the limits of its widgets, the last commits, git state); `-- next|limits|log|state|categories [category]`. A task in a `TODO.md` starts with `(high)`, `(medium)` (the default) or `(low)`; `(later)`, `(low priority)`, "out of scope" or a heading about waiting defer it, and a report leaves deferred tasks out while others are open. The user skill `todo-report` says how it is used.
- Selective testing: `odin run tool/test` (from odin_utilities) runs only the packages of the uncommitted changes and the packages that import them, one line per package and the failures only (saves output; `-- --since main`, `-- ui reports`, `-- --all`, `-- --list`, `-- --verbose`, `-- --browser`: also the checks that need a browser (the SIMD128 kernels of `simd` and the page of each web demo, loaded in a headless Chrome or Edge to report console errors; skipped without a browser)). `-- --all` is every package and has to end with "all N packages passed": the tool runs `3d_models` inside of its folder and leaves `templates/` out (a template does not build where it is). Use it while working; run the full `odin test <lib>` of what you touched before committing.
- Cross check: `odin run tool/test -- --cross [--all | packages]` runs `odin check` of the selected packages (tests or not) for `linux_amd64` and `darwin_arm64`; it finds what only Windows compiles (an import used only in a `when ODIN_OS == .Windows` branch). A package that stops at a vendor library that is not compiled here, or builds only for the web, is counted as unchecked. Known failure not fixed here: `ui/demo_common` does not build for macOS (`demo_windows` undeclared).
- `os.process_exec` on Windows: `Process_State.success` is ALWAYS true (Odin cannot tell a crash there). A failed command shows only in `exit_code`: test `state.exit_code == 0`, never `state.success`.
- `box2d_odin` tests take `test_box2d_lock`: Box2D world creation is not thread safe and the test runner is multi threaded.
