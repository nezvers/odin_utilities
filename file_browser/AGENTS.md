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
- The web page was driven in a headless Chrome (DevTools protocol, 2026-11-28): the chooser opens after the click, a picture and a sound open, Play counts, the download is byte identical. The names of `file_browser.js` must be the foreign proc names (`file_browser_pick_start`, ...): a test compares them.
- Firefox 161 (headless, WebDriver BiDi, 2026-11-28): the same flow works (open picture and sound, play, download of 747 bytes). A headless Firefox has no dialog to wait in and fires `cancel` at once, so a driver has to answer `input.fileDialogOpened` immediately (`input.setFiles` with the element of the event, a Windows path with backslashes); a person with a real dialog is not affected.
- `demo_web/drive` clicks through the web demo with `browser_drive` (open picture and sound through the browser file chooser, play, save both, invert, save again; reads the downloads and the console): `odin run file_browser/demo_web/build_web -- --drive chrome|edge|firefox [--no-build] [--screenshots <folder>]`, exit code 3 when the browser is missing. `tool/test --browser` runs it for Chrome and Firefox. It found that the generated page asked for `/favicon.ico` (a console 404 in Chrome): the web_build template has an inline icon now.
- `file_browser.js` counts the files the program took in `window.fileBrowserPicksTaken`; the click-through waits for it instead of a fixed time. Play and Invert are waited for with `browser_drive.DriverWaitChanged` (the canvas changed and is quiet), the picks with `DriverWaitStable`. A headless Firefox cancels the chooser at once and a driver answers a moment later, so `file_browser.js` handles `cancel` 250 ms late and only when no file arrived: without it about one run in six was CANCELLED.
