# Web build

Make a web build (js_wasm32) of a program, and load resources so that the same code works on desktop and in the browser.
Referenced from `WIP/karl2d_jam_2026` (`main_web`, `game/assets/assets.odin`) and from `karl2d/build_web`.

## Why resources are special
A browser has no files to read. The bytes have to be compiled into the program with `#load`. On desktop the same resource is read from a folder.
`ResourceLoad(set, "textures/player.png")` does the right one: a web build (`RESOURCE_EMBED`, on by default for js) uses the embedded bytes, other builds read
`RESOURCE_PATH/name` and fall back to the embedded bytes when the file is missing. Reading allocates with the given allocator, `ResourceFree` gives it back.

```odin
RESOURCE_PATH   // -define:RESOURCE_PATH=../assets   folder next to the executable, default "assets"
RESOURCE_EMBED  // -define:RESOURCE_EMBED=true       use only embedded bytes, default true on js
```
List the embedded resources once, only when they are needed, so desktop builds stay small (`demo_karl2d/game/embedded.odin`):
```odin
when web_build.RESOURCE_EMBED {
    embedded_resources: [1]web_build.Resource = {{"textures/a.png", #load("../../assets/textures/a.png")}}
} else {
    embedded_resources: [0]web_build.Resource
}
```
`resource.odin` has no `core:os` and no `core:testing` because it builds for js. Its tests are in `resource_test.odin` and the disk part in `resource_file.odin`.

## The web build
The source directory is a package with `init`, `step` (returns false to stop) and `shutdown`, the same contract as `karl2d/build_web`.
```odin
web_build.WebBuild({source_directory = "game", title = "My game", odin_arguments = {"-o:size"}})
```
It writes `<source>/build/web` (generated entry) and `<source>/bin/web` (index.html, odin.js, main.wasm, copied files). Serve `bin/web`, a browser refuses wasm from file://:
`python -m http.server` inside of it. Needs `odin` in PATH.
For JavaScript that the program needs (karl2d audio) use `copy_files`, `scripts`, `imports_js` and `start_js`, see `demo_karl2d/build_web/main.odin`.

## Demo
Both show the same: textures, a font and a text file loaded by name.
- `odin run demo_raylib` (desktop only, raylib in a browser needs emscripten)
- `odin run demo_karl2d` (desktop, files from `../assets`)
- `odin run demo_karl2d/build_web -- -o:size`, then serve `demo_karl2d/game/bin/web` (resources are embedded)

## Tests
`odin test web_build -strict-style -vet`. The build test runs `odin build -target:js_wasm32`, no browser is needed.
