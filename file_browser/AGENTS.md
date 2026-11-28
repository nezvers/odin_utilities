# file_browser

Open/save dialog on `ui` plus IO backends. See README for the API.

- `io.odin` is the `Io` vtable (list/read/write/stat/start, optional native chooser: pick_start/poll/name/take, download). Backends: `io_os.odin` (`#+build !js`), `io_web.odin` + `file_browser.js` (`#+build js`, polled each frame, no callbacks), `io_memory.odin` (tests, scripted demos). `io_default.odin` picks.
- `browser.odin` is the state machine; results are delivered once, by `FileBrowserUpdate`. Directory memory is saved on a successful open/save only, and falls back to the nearest existing parent, then `io.start`.
- `ui_browser.odin` is the modal; no image widget exists in `ui`, the demo draws its picture with a `.CUSTOM` element.
- A browser chooser needs a user gesture: the request is made in the frame after the click.
- Tests never touch outside a temp root (`chooseInside` guard); keep it so.
- Demo scripts use `IoMemory` (headless or `DEMO_TEST`), so paths are `/demo/...`.
- `WebBuild` and `ExtensionBuild` pass `-target-features:simd128` so `simd` runs its vector text kernels in the browser; a build without it still links (scalar kernels).
- Commands: `odin test file_browser -strict-style -vet`, `odin test file_browser/demo_common`, `odin run demo_kit/tool/captures -- --karl2d file_browser`.
