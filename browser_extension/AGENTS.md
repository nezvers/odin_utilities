# browser_extension: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md (per browser install steps and verified browsers are there).

Browser extensions written in Odin (`js_wasm32`) for Chrome/Opera/Edge (`chromium` build, MV3 service worker) and Firefox (MV3 event page). The service worker needs `window` aliased for odin.js.

## Files
- `browser_extension.odin`: `ExtensionConfig`, `ExtensionManifest`, `ExtensionBuild` (generated entry, main.wasm, unpacked folders, zip/xpi); build side, `#+build !js`, tests at the bottom.
- `install.odin` `ExtensionInstall`: Chromium `--load-extension` in a profile of its own; writes a per user registry value on Windows. `firefox_remote.odin`: installTemporaryAddon over the remote debugging protocol.
- `release.odin` `ExtensionRelease` (`--release`): main profile; Chromium family from a stable copy in `%LOCALAPPDATA%/<name>` that the user loads unpacked once; Firefox signed unlisted via `web-ext sign` (needs WEB_EXT_API_KEY/SECRET).
- `runtime/runtime.odin` (Odin side: `Log`, `SetBadge`, `ReplyPrint`), `templates/` (background.js, extension.js, popup, content script, entry template), `native_host.odin` (registers the native messaging helper).
- `demo/` + `demo/tool`: run from the library folder `odin run demo/tool -- all [--install]`. `.vscode/` has build, install tasks and launch configs.

## Source package contract
- `init`, `on_load(state)`, `on_message(message, reply: []u8) -> int`; messages go through fixed buffers owned by the generated entry; `runtime.SaveState` keeps state in browser storage.
- `ExtensionConfig.options` makes a web_build package (Karl2D or a demo_kit demo) the options page; `content_script_file` sets the content script.

## youtube_shorts (full example)
- Logic in `shorts.odin` (background, page, tests); options page on raylib and Karl2D; `youtube_content.js`. Verified with mock pages, not live YouTube (its README).
- Download button: yt-dlp/youtube-dl through a native messaging helper (`youtube_shorts/native` logic + `native_host` program); a background reply `native:<text>` goes to the helper.
- `youtube_shorts/options_drive` opens the built options page as an extension page in Edge with `browser_drive` (`DriverConfig.extension`, `DriverExtensionId`), clicks the toggles and reads what the background keeps with the same `get` message: `odin run youtube_shorts/tool -- edge --drive edge [--no-build] [--screenshots <folder>]` from this folder (`tool/test --browser` runs it). The branded Chrome 158 ignores `--load-extension` (the check says so and exits 3); a Firefox extension page has a random moz-extension address, so it is not driven yet.
- `templates/options_run.js` sets `window.odinStarted` like web_build's index.html (after the first frame), so drivers wait for it instead of a fixed time.
