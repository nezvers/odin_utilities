# odin_utilities

My Odin libraries (git repo nezvers/odin_utilities, branch main). Parent: `../CLAUDE.md` (master rules for everything under O:\Projects\Odin).
One library per directory, all with the same structure so any of them is a reference and a template (`templates/library`).
Shared assets: `assets/` (textures, fonts, sounds, gltf). `references/` is for reference material (git ignored: `references/clay` is the
Clay checkout the `ui` layout is ported from, `references/imgui` the Dear ImGui demo the `ui` demo follows, `references/raddebugger` the RAD Debugger: its `src/ui`
and its thread layer `src/base/base_threads*`, `base_thread_context*`, `artifact_cache/` were studied for ui and threading ideas). `karl2d/` is a directory junction to `../odin_plug/karl2d` (see Repository map).
Stale build outputs in a library folder (`demo.exe`, `*.pdb`, `log.txt`) are git ignored.

## Library structure (every odin_utilities library, template in odin_utilities/templates/library)
```
<lib>/  README.md  <lib>.odin (+ more files)  <lib>_test.odin (#+build !js when the lib builds for web, else tests at the bottom of the tested file)
        glue_raylib/<lib>_raylib.odin  glue_karl2d/<lib>_karl2d.odin   (glue, only what needs the framework)
        demo_common/   demos written ONCE against odin_utilities/demo_kit: one file per demo (`kit.Demo` with init/finit/update/draw/script), demos.odin lists them,
                       demo_common_test.odin plays the scripts headless
        demo_raylib/main.odin   one call: kit_raylib.Run("<lib>", demo_common.demos[:])
        demo_karl2d/main.odin   one call: kit_karl2d.Run("<lib>", demo_common.demos[:])
```
- Every library keeps its raylib demo in `demo_raylib/` (package `demo_raylib`) and its karl2d demo in `demo_karl2d/`, both thin. VS Code tasks build with `-out:${config:project_name}.exe` (`project_name` = `demo`).
- A demo that needs something the kit does not have (3D, a framework specific draw proc) puts the framework part in an extra file of `demo_raylib/` / `demo_karl2d/` and hooks it into demo_common (see fps_controller: `SceneDrawer`). The Karl2D 3D demo needs the custom fork, said in that README.
- A library that draws (tilemap, box2d_odin debug draw) also gets a `kit/` glue package (`tilemap/kit`, `box2d_odin/kit`: package `<lib>_kit`) that draws through `kit.Context`, so its demos stay in demo_common. Glue that is only for one framework (input, scene loaders, mic_meter) is reached from demo_common through an adapter table or the demo lives in `demo_<framework>/`.
- Non visual libraries (serial, task, web_serve) have no demos.

## demo_kit (odin_utilities/demo_kit)
- `Backend` (table of procs: shapes, text, textures, sound, camera, clip, mouse capture) implemented by `demo_kit/glue_raylib`, `demo_kit/glue_karl2d` and `HeadlessInit` (no window, drawing is counted). `Input` is plain data per frame, `Context` is what a demo proc gets. `gui.odin` has Button/Toggle/Slider/Spinner.
- Runtime tests: a demo's `script` is a `[]kit.Step` (Wait, Tap, Hold, Click, Drag, MoveTo, Scroll, LookBy, Type, Check(proc, message)); a Player turns it into input. Constructors are contextless so a script can be a global. `odin test <lib>/demo_common` runs it headless, `odin run <lib>/demo_raylib -define:DEMO_TEST=true` plays it in the window (exit code 1 on a failed check). A demo without script is a 60 frame smoke test.
- Screen capture tests: script step `kit.Capture("name")` compares the drawn frame with `captures/<backend>/<name>.png` next to the script file; only in a window with `-define:DEMO_CAPTURE=true` (new goldens are written when missing, `-define:DEMO_CAPTURE_UPDATE=true` replaces them). Headless skips it. See demo_kit/README.md.
- Strings with apostrophes break multi file bash heredocs here: write demo files with the Write tool.

## Repository map
- `<lib>/` - one library per directory (tilemap, input, tween, timer, ui, sprite, ...).
- karl2d - a directory junction to ../odin_plug/karl2d, so both use one copy: my fork of Karl2D (upstream + odin_plug embed commits + the 3D layer, branch render3d). Not my library otherwise. Its AGENTS.md rules (no comments, short replies) apply only to that repo, not to my libraries.
- Libraries import karl2d by relative path, e.g. `import "../../karl2d"` from tilemap/glue_karl2d.

## Other places that use these libraries
- `../WIP/karl2d_jam_2026` keeps its own copies of some libraries (`game/sprite`, `game/sound_effects`, `game/scene`, ...) with the old directory names, not synced with changes made here.
- `../odin_plug` uses the Karl2D fork (submodule) and follows this style; its rules are in `../odin_plug/CLAUDE.md`.

## My library style (see odin_utilities/tilemap as reference)
- Libraries are framework agnostic. Framework specific drawing lives in sub packages (`glue_raylib/`, `glue_karl2d/`) named `<lib>_<framework>.odin`.
- No hidden allocations: user provides buffers/slices (`TilemapInit(position, size, tile_size, buffer)`).
- Procedures are PascalCase prefixed by the abstraction: `TilemapGetTile`, `TileAtlasInit`, `AutotileRuleUpdateCell`, `DualGridUpdateTilemap`. Constants are UPPER_CASE (`TILE_EMPTY`). Types are PascalCase.
- Typed locals: `name:Type = value`. `assert` for preconditions. Comments describe each proc and non-obvious steps.
- Demo code uses snake_case procs.
- A feature that uses data + derived output takes input and output tilemaps (see `rule_tile.odin`, `dual_grid.odin`).
- Keep comments in code I write; explain why, not what.

## tilemap library layout
- Core: `common.odin` (types), `tilemap.odin`, `tileset.odin`, `tile.odin`, `tile_atlas.odin`, `rule_tile.odin`, `dual_grid.odin`, `editing.odin` (input helpers + paint/drag/select), `rand.odin`.
- TileID 0 is TILE_EMPTY, 255 is TILE_INVALID. Chain: Tilemap (grid of TileID) -> Tileset -> Tile (alternatives) -> TileAtlas (texture positions).
- `glue_raylib/tilemap_raylib.odin`, `glue_karl2d/tilemap_karl2d.odin` - Draw* procs.
- `demo_raylib/` - raylib demo (`odin run demo_raylib`, Odin package `demo_raylib`). Each demo file is `#+private file` with `@(private="package") state_xxx:State = {enter, exit, update, draw}`; register in `demo_raylib/demo.odin` (`state_list`, `Example` enum, `example_names`).
- `demo_karl2d/` - same demos for karl2d (`odin run demo_karl2d`); files in `demo_karl2d/game/`, states are `GameState{init, finit, update, draw}`, register in `game_state.odin` (`state_list`, `StateIndex`).
- Shared demo data (atlas/tile/tilemap buffers, textures) is in each `demo_common.odin`; demo executables set working dir to exe dir, raylib demo loads `../assets/textures/...`, karl2d demo embeds with `#load`.
- To port an example: put reusable logic in the library package, keep only input/drawing in the two demos.

## tween library layout
- `tween.odin` (Tween + Step builder + `TweenUpdate`), `tween_value.odin` (property types), `tween_system.odin` (static pool `TweenSystem($N)`, `System*` procs), `tween_test.odin` (`odin test .`).
- Zero allocations: fixed step array per Tween, handle-map pool. Demos in `demo_raylib/` (raylib) and `demo_karl2d/game/` follow the same state pattern as tilemap.

## grid_collision_map library layout
- `grid_collision_map.odin` (`GridMap($X,$Y,$N,$C)`: colliders in `hm.Static_Handle_Map`, per cell fixed `Slot` of Handles; `GridMap*` procs, `Rect*` narrow phase helpers), `grid_collision_map_test.odin` (`odin test .`). Demos in `demo_raylib/` and `demo_karl2d/game/` (`demo_collision.odin`).
- Same "fixed buffers, fail instead of grow" rule as tilemap/tween.

## microui library layout
- `microui.odin` (package `microui_utils`: `MuiLog`, `U8Slider`, `AtlasToRGBA`), glue `glue_raylib/microui_raylib.odin` and `glue_karl2d/microui_karl2d.odin` (`Init/Update/Render/Cleanup` on a user owned `MuiState`), demos `demo_raylib/` and `demo_karl2d/game/` (`demo_microui.odin`).

## atlas_packer library layout
- `atlas_packer.odin` (`AtlasPacker` of slices, `Init(packer, atlas_size, rect_capacity, allocator)`), `font.odin` (stbtt `FontInit/GetFontRects/RenderGlyph`), glue `glue_raylib/` and `glue_karl2d/` (`BakeImageRects`, `CreateImage`, `BakeFontGlyphs`, `RegisterFont`), `atlas_packer_test.odin` (`odin test .`).
- Allocator agnostic: demos use `mem.Arena` over a static buffer, persistent allocations first, then `begin_arena_temp_memory` section for source images, `arena_free_all` in finit.

## box2d_odin library layout
- Library (`package box2d_odin`): `helpers.odin` (Add* shape wrappers, Create* body/joint helpers), `camera.odin`, `input.odin`, `ui.odin` (immediate mode UI over a `Backend`), `sample.odin` (`Sample` + `SampleHost`), glue in `glue_raylib/` and `glue_karl2d/` (`InitDebugDraw`).
- `samples/` ports `box2d/samples/sample_*.cpp` (one file each, registered with `@(init)`, file private globals as state). `odin test samples` smoke tests every sample headless. Demos only supply input, `Backend` and debug draw. Vendor `vendor:box2d` matches the C repo in `box2d/` (v3.2+ API: `motionLocks`, `base` joint defs, `DrawLineFcn`).

## 3d_models library layout
- `gltf.odin` (package `models3d`: `Model` structs, `ModelLoadGltf`, `ModelAnimate`, skinning helpers), `glTF2/` (copy of the glTF2 parser from third_party/gltf, MIT, patched for current Odin; don't use vendor:cgltf, it clashes with raylib's symbols), `glue_raylib/` glue (`DrawModel` CPU skinning), `gltf_test.odin` (`odin test .`). Assets in `odin_utilities/assets/gltf`.
- Allocator agnostic like atlas_packer: pass an arena to `ModelLoadGltf`, nothing allocates per frame.

## hot_reload library layout
- `hot_reload.odin` (`HotReload*` procs, `Api` that the DLL exports with the `game_` prefix, `LayoutHash`; tests at the bottom build `demo_game` as a DLL), `demo_game/` (framework free demo game DLL, `demo_game/api` is the host proc table), demos in `demo_raylib/` and `demo_karl2d/` (a Reload button rebuilds the DLL and calls `HotReloadRequest`).

## web_build library layout
- `resource.odin` (`ResourceLoad` with `RESOURCE_PATH` / `RESOURCE_EMBED` configs, builds for js so no os/testing there; tests in `resource_test.odin`, disk read in `resource_file.odin`), `web_build.odin` (`WebBuild`, js_wasm32 build of a package with init/step/shutdown, tests at the bottom run a real build), `templates/`. Demos: `demo_raylib/` (desktop), `demo_karl2d/` (`game/` is the web package, `build_web/` calls `WebBuild`).

## web_serve library layout
- `web_serve.odin` (`Server*` procs: static GET/HEAD file server over `core:net`, fixed buffers, polled connections, `ResolvePath` refuses traversal; tests at the bottom use real loopback sockets), `tool/` (`odin run web_serve/tool -- <dir> --open`). No raylib/karl2d demo: nothing is drawn, the tool serves the web_build demo.

## scene library layout
- `asset.odin` (`AssetStore` over a user `AssetStorage(N)`, `LoaderUpdate`: background and blocking requests with a time budget, loaders split in `decode` (may run on a worker thread) and `finish` (main thread)), `asset_workers.odin` (worker pool, `#+build !js`, `asset_workers_js.odin` is the no-thread stub), `prefab.odin` (`PrefabDef` with base and `PatchField` overrides, resolved once), `scene.odin` (`SceneSystem`: scene table, transition, prefetch hints, listeners and scene instances in `core:container/handle_map`, per-scene arena), `glue_karl2d/` glue (loaders, placeholders, `DrawTransition`), `demo_karl2d/`. Builds for js_wasm32, so tests are in `*_test.odin` (`#+build !js`) and not at the bottom. The jam game uses a copy in `game/scene` (the library files without the tests).

## serial library layout
- `serial.odin` (binary `Writer`/`Reader` over user buffers with a counting pass, versioned length-prefixed chunks, file frame with crc32, `RleWrite`/`RleRead`; safe on untrusted data, builds for js so tests are in `serial_test.odin`). Used by `tilemap/tilemap_serial.odin` (tilemap layers by name, atlas, tileset), `box2d_odin/physics_serial.odin` (`PhysicsDesc` of bodies, shapes, hinges: write, read with validation, `PhysicsCreate`), `scene/level.odin` (entities as prefab instances with overrides by field path, asset names, `LevelAttach`). `scene/level_integration_test.odin` is the whole level file pipeline.

## signal library layout
- `signal.odin` (`Signal($T,$N,$Q)`: payload, connection capacity, deferred queue size; connections in `core:container/handle_map`, order list kept apart because slots are reused; `Signal*` procs: Connect with `.ONE_SHOT`/`.DEFERRED`, Emit, Flush, Disconnect*, Block; safe to change connections while emitting; builds for js so tests are in `signal_test.odin`), `demo_common/` (framework free model of the demos), `demo_raylib/`, `demo_karl2d/game/`.

## ui library layout
- Immediate mode ui, layout ported from Clay (`references/clay`, MIT, credited in README). Core files: `context.odin` (Storage, UiInit/Begin/End, widget state in a `Static_Handle_Map` of `UI_STATES`), `layout.odin` (Clay port: sizing, floating, clip, text wrap), `widgets.odin` (`Ui*` widgets, containers are `if UiPanel(...) {}` blocks through `@(deferred_in)`), `widgets_more.odin` (collapsing/tree, radio, selectable, tabs, drag, inputs, plots, color, menus, modal, titled window), `style.odin` (`StyleKind`, `DrawInfo` with rect + value 0..1 + name + actual, `Style` table of user procs), `render.odin` (`UiRender` only calls the style procs, so the ui shares the batch of the frame), `nav.odin` (focus by direction and the default actions of Godot: `ui.Action` ACCEPT/CANCEL/FOCUS_NEXT/UP../HOME/END/PAGE_*, set in `Input.actions` by the glue and applied in `UiBegin`; `UiNavigate`, `UiActivate`, `UiCancelled`, `UiNavLink/UiNavBlock` overrides, scroll into view, input agnostic), `rounded.odin` (radius as part of the shortest side, polygon into a caller buffer).
- `default_style/` (package `ui_default`: `Painter` + default style), `kit/` (Painter + input over demo_kit, used by the demos), `glue_raylib/`, `glue_karl2d/` (Painter + `InputPoll`), `demo_common/` (widgets, layout, styles, navigation demos and `demo_imgui`, the layout of Dear ImGui's demo window, with scripts; `references/imgui` is the git ignored checkout it follows). Scripts click at fixed coordinates computed from the layout (window at (40,40), padding 10, controls 28 high): widths must be `Fixed` so fonts do not move them.
- Pointer is tested against the hit boxes of the last frame; a click needs a frame of layout first (scripts `Wait(3)` at the start). Ids are hashes of the name inside the container (`"Save##2"`), `UiIdPath("Window", "Widget")` finds one from outside a frame.
- `odin test ui`, `odin test ui/demo_common`.

## Commands (run in odin_utilities, tilemap shown)
- `odin check demo_raylib -strict-style -vet` and `odin check demo_karl2d -strict-style -vet`
- `odin run demo_raylib`, `odin run demo_karl2d`
- Tests live at the bottom of the library or glue source file they test (`@(test)` procs, no separate test files for new code, none for demos): `odin test <lib> -strict-style -vet` from odin_utilities (3d_models: `odin test .` inside it, it loads an asset by relative path). Glue packages that call raylib can't run under `odin test` on this machine (static raylib breaks `os.args` in the runner), only their raylib-free logic is tested. karl2d glue tests cover the CPU side only (no window).
- `box2d_odin` tests take `test_box2d_lock`: Box2D world creation is not thread safe and the test runner is multi threaded.
