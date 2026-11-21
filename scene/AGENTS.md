# scene: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `asset.odin` (`AssetStore` over a user `AssetStorage(N)`, `LoaderUpdate`: background and blocking requests with a time budget, loaders split in `decode` (may run on a worker thread) and `finish` (main thread)), `asset_workers.odin` (worker pool, `#+build !js`, `asset_workers_js.odin` is the no-thread stub), `prefab.odin` (`PrefabDef` with base and `PatchField` overrides, resolved once), `scene.odin` (`SceneSystem`: scene table, transition, prefetch hints, listeners and scene instances in `core:container/handle_map`, per-scene arena), `glue_karl2d/` glue (loaders, placeholders, `DrawTransition`), `demo_karl2d/`. Builds for js_wasm32, so tests are in `*_test.odin` (`#+build !js`) and not at the bottom.
