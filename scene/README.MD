# Scene system

Scenes and prefabs as data, with loading that stays out of the way. Framework agnostic core (`asset.odin`, `prefab.odin`, `scene.odin`), karl2d glue in `karl2d/`.
Builds for js_wasm32 too, so a game with a web build can use it as it is. The tests are in `*_test.odin` files with `#+build !js` because `core:testing` doesn't compile for wasm.

## Fast loading
Assets are rows of a constant table (`AssetDef`), loaded a few per frame on the main thread (GPU and audio resources need it), in two kinds of requests:

| request | for | how it loads |
|---|---|---|
| **background** | prefetch: the likely next scene, optional assets | one item per frame when frames are slow, as many as the 2 ms budget allows when they are good |
| **blocking** | what a scene needs before it can start | first in the queue, up to 12 ms per frame, the transition covers it |

- **Predictable**: when a scene starts, the scenes in its `next` are prefetched in the background. Code that knows more calls `SceneExpect` (the player is at the door, the mouse is over the Play button).
- **Not predictable**: `SceneGoto` to a scene that is not ready makes what is missing blocking (it jumps the queue even when it was queued as a guess) and starts a transition. The scene starts when everything it requires is settled and the cover has been up for the hold time. A scene that is ready starts at once, with no transition.
- **Never stalls**: `AssetGet` gives the placeholder (or a null value for the null id) until the real value is there. A failed asset counts as settled, nothing waits for it forever.
- `LoaderConfig`: `target_frame_seconds`, `slack`, `background_budget_seconds`, `blocking_budget_seconds`, `max_per_frame`.

## Threads
A loader can be split in two: `decode` (the CPU work: unpacking an image, parsing a file) and `finish` (creating the GPU texture or audio buffer). `decode` only touches the bytes it is given and the memory it is given, so it can run on a worker thread. `finish` always runs on the main thread because frameworks are not thread safe. A loader that only has `load` stays on the main thread.
- The platform decides: with `thread.IS_SUPPORTED` and `decode_memory` provided, workers are created once at init (`workers = 0`: cores - 1, at most 4; negative: none). The web, or no memory, means no workers and the same loaders run on the main thread, a few per frame, with the same results (`LoaderThreadsAvailable`).
- Each worker has its own job slot and decodes into its own part of `decode_memory`, an arena that is reset after every item. No queue, no locks: a slot is owned by whoever its atomic state says, a semaphore wakes the worker. Size the memory for the biggest decoded asset per worker, a decode that does not fit fails cleanly (the asset is FAILED).
- The same rule as before decides how much runs at once: blocking work or good frames keep every worker busy, slow frames one. The frame budget is for the main thread (finish steps, loaders without decode), that is what can make a frame slower.
- The karl2d glue decodes textures on workers (`TextureDecode`, `TextureFinish`). Sounds and fonts still load on the main thread.
- `AssetStoreShutdown` (called by `SceneShutdown`) joins the threads. A hot reload `SceneRebind` waits for running decodes first.

## Memory
- Fixed size, nothing allocates per frame (threads are created once at init). The state of the assets is your `AssetStorage(N)` (for example inside the game memory), listeners and scene instances are static handle maps (`core:container/handle_map`), a stale handle is refused.
- Assets, prefabs and scenes are ids that index constant tables. Handles (`ListenerId`, `SceneInstanceId`) are for what is made and removed while running.
- Each scene has an arena (`SceneAllocator`): what its `init` allocates goes there and `free_all` runs when it exits. A decode scratch arena is reset after every loaded item.
- When a scene starts, the assets that it, its `next` scenes, `SceneExpect` hints and `persistent` assets don't need are unloaded.
- `SceneGetStats`: arena use and peak, assets ready and queued, loader totals.

## Prefabs
A prefab is a value of your struct plus patches, and can be based on another one (an abstract base with no assets works well):
```odin
zombie: scene.PrefabDef(Actor) = {base = &character, patches = {scene.PatchField(Actor, "max_speed", f32(20))}, assets = {TEXTURE_ZOMBIE}}
scene.PrefabResolve(&zombie, &prefab_zombie)    // once, when the scene starts: root value + patches
unit = prefab_zombie                            // spawning is a struct copy
scene.PrefabApply(&unit, overrides)             // per instance: a few memcpy calls
```
A patch is the offset and bytes of one field, found once (also through `using` and nested fields: `"health.value"`). No reflection at runtime, no allocation.
`PrefabRegister` tells the system what a prefab needs so scenes can list it in `prefabs` and listeners can follow it.

## Listeners
`Listen(system, kind, id, callback, user, once, scope)`: `ASSET_READY`, `PREFAB_READY`, `SCENE_READY`, `SCENE_ENTERED`, `SCENE_EXITED`, `SCENE_CANCELLED`.
- Already true (the prefab is loaded, the scene is running): the callback comes at once, so the order of listening and loading does not matter.
- `SceneGoto` and `SceneStart` return a `SceneInstanceId`, one run of a scene. `scope` follows that run: the listener is removed when the run is gone, and a replaced request says `SCENE_CANCELLED`.
- `ANY_ID` hears every id of a kind.

## Scenes
```odin
scenes: [Screens]scene.SceneDef = {
    .Gameplay = {name = "Gameplay", init = init, finit = finit, update = update, draw = draw, gui = gui,
        required = {TEXTURE_SHOTGUN}, prefabs = {PREFAB_PLUMBER}, optional = {MUSIC}, next = {.Gameplay}},
}
scene.SceneSystemInit(&system, {scene_memory = memory[:]}, scene_table, asset_table, glue.loaders[:], &storage)
scene.SceneStart(&system, first)          // each frame: SceneUpdate, SceneDraw, SceneGui, glue.DrawTransition
```

## Levels
`level.odin`: what a level editor saves and a game loads. A `Level` is entities (instances of prefabs with a position, rotation, scale, an optional parent and overrides), asset names, and the chunks of other libraries in the same file. See `../serial/README.MD`.
- Prefabs and assets by name, overrides by field path, resolved once (`LevelResolve`, `LevelResolvePatches`) into the plain `FieldPatch` values that spawning applies. Prefabs are registered with `PrefabRegisterNamed`.
- `LevelOpen(bytes, storage)` fills storage you provide and refuses an inconsistent file as a whole. Names are views into the file data, it has to stay alive.
- `LevelAttach(system, scene, &level)` makes the level's assets and prefab assets part of the scene, so predicted scenes prefetch them and unpredicted ones wait for them behind the transition.

## Hot reload
All state is plain data and scenes are ids. `SceneRelease` before the old code is left, `SceneRebind` with the tables of the new code, `SceneResume` to start the current scene on what is loaded. The system must not move after init.

## Demo and tests
`odin run demo_karl2d` (from this directory): hover to prefetch, click a button with no hint to see the transition, the placeholder checker, the event log. `odin test scene -strict-style -vet` and `odin test scene/karl2d`.
The jam game (`WIP/karl2d_jam_2026`) is a full use of it: asset table in `assets/ids.odin`, prefabs in `actor/prefabs.odin`, scene table in `game_screens/`.

## Demos and tests
`odin run demo_karl2d`: three scenes with different textures (hover to prefetch, click to go, an unpredicted scene is covered by a transition). Karl2D only: the asset loaders of the scene system are Karl2D glue (`karl2d/`), there is no raylib glue, so there is no `demo_common` or `demo_raylib`.
The demo runs on the demo kit and its script hovers, clicks and waits for the loading: `odin run demo_karl2d -define:DEMO_TEST=true`. Library tests: `odin test scene -strict-style -vet`.
