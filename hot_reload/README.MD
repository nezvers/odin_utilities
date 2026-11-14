# Hot reload

Reload a game DLL while the host executable keeps running. Framework agnostic: the host owns the window and the loop, the DLL owns the game.
The game memory is kept across reloads when its layout is the same, and rebuilt when it changed (a reordered or retyped field keeps the
size, so the layout is compared with `LayoutHash`, not only the size).

## DLL side
Export these with the prefix `game_` (see `demo_game/game.odin`): `init(host, allocator)`, `destroy`, `update`, `memory`, `memory_size`,
`memory_layout` (return `hot_reload.LayoutHash(Memory)`), `release`, `reloaded(memory, host)`.
Pass a table of host procs (drawing, input, time) through `host`, then the DLL never shares the state of raylib or karl2d.
Everything that has to survive a reload goes in the memory, globals of the DLL are lost. `release` frees what lives in those globals.

## Host side
```odin
reload: hot_reload.HotReload
loaded: [64]hot_reload.Api            // DLLs that were left behind stay loaded, the length limits the reloads of one run
hot_reload.HotReloadInit(&reload, {dll_path = "game.dll", copy_directory = "copies", host = &host, allocator = context.allocator}, loaded[:])
for hot_reload.HotReloadUpdate(&reload) { ... }      // one game frame, then a pending reload
hot_reload.HotReloadShutdown(&reload)
```
- `HotReloadRequest` starts a reload at the end of the next update, call it from a button after the DLL was rebuilt.
- `config.poll = true` also reloads when the DLL file is rewritten.
- `HotReloadNow` reloads at once and returns `KEPT`, `REBUILT` or `FAILED`. A half written or incomplete DLL fails and the old code keeps running.
- `HotReloadRestart` creates the game memory again with the running code.

## Demo
`odin run demo_raylib` or `odin run demo_karl2d` (from this directory). The Reload button builds `demo_game` as a DLL and requests a reload.
Change `BOX_COLOR` or `BOX_SPEED` in `demo_game/game.odin` and press it: the box keeps its place and the frame counter keeps counting.

## Tests
`odin test hot_reload -strict-style -vet`. The reload test builds the demo game three times with `odin build`, so `odin` has to be in PATH.
