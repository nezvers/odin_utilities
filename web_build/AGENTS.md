# web_build: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `wasm_build.odin` (`WasmBuild`: freestanding_wasm32 (or js without an entry) for a module that a host loads, not a page; `require_exports`, `require_memory`, `allowed_import_modules`) and `wasm_inspect.odin` (`WasmInspect`: the imports and exports of a binary, builds for every target; used by spacetimedb's `BuildModule`).
- `resource.odin` (`ResourceLoad` with `RESOURCE_PATH` / `RESOURCE_EMBED` configs, builds for js so no os/testing there; tests in `resource_test.odin`, disk read in `resource_file.odin`), `web_build.odin` (`WebBuild`, js_wasm32 build of a package with init/step/shutdown, tests at the bottom run a real build), `templates/`. Demos: `demo_raylib/` (desktop), `demo_karl2d/` (`game/` is the web package, `build_web/` calls `WebBuild`).
