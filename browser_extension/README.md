# browser_extension

Browser extensions whose logic is Odin, compiled to wasm (`js_wasm32`). One source package builds for **Chrome, Opera, Edge** (Chromium, Manifest V3, background service worker) and **Firefox** (Manifest V3, background event page). A build tool writes the unpacked extensions and the store packages, and can start a browser with the extension already loaded.

```
browser_extension/
├── browser_extension.odin     build side: ExtensionConfig, ExtensionManifest, ExtensionBuild (packages), tests
├── install.odin               start Chrome / Opera / Edge / Firefox with the extension loaded
├── firefox_remote.odin        Firefox: installTemporaryAddon over the remote debugging protocol (what web-ext does)
├── runtime/runtime.odin       the Odin side inside the extension: Log, SetBadge, OpenUrl, SaveState, ReplyPrint, and for pages SendMessage
├── templates/                 JavaScript glue and the generated entry: background.js, imports.js, extension.js, popup, content script, options page
├── demo/extension.odin        example extension: popup button -> Odin counts -> badge on the toolbar icon
├── demo/tool/main.odin        the build tool of the demo, copy it for your own extension
├── youtube_shorts/            a real example, most of the logic in Odin: Shorts as full videos, a Save button on desktop, an options page
│                              drawn by Karl2D (extension) and raylib (desktop preview). See youtube_shorts/README.md
└── .vscode/                   tasks and launch configurations
```

## Write an extension
The source directory is an Odin package with three procs (`runtime/runtime.odin`):

```odin
package my_extension
import runtime "<path to>/browser_extension/runtime"

init :: proc() {                                              // every time the background starts
    runtime.Log("started")
}

on_load :: proc(state: string) {}                             // what SaveState kept, "" the first time; before the first message

on_message :: proc(message: string, reply: []u8) -> int {     // popup or content script -> Odin
    if message == "ping" {
        return runtime.ReplyPrint(reply, "pong")
    }
    return 0
}
```

`runtime.SaveState(text)` keeps up to 16 KB in the browser storage (`storage` permission), `on_load` gets it back after the browser stopped and started the background. `runtime.OpenUrl` opens a tab.

### A program on the computer (native messaging)
`native_host` (a name like `com.example.helper`) adds the `nativeMessaging` permission, and `native_host_executable` is the program: `ExtensionInstall` writes its manifest and registers it for the browser (`native_host.odin`; Windows registry key of Chrome / Opera, Edge, Firefox, manifest folders on Linux and macOS, the last two untested). An on_message reply that starts with `native:` is sent to that program by `background.js`; its answer comes back to on_message as `native-reply:<text>` (`native-error:<why>` when the browser could not reach it) and the reply to that is the final one. So Odin decides what is asked and what the answer means, the JavaScript only carries it. `youtube_shorts/native_host` is a helper (stdin/stdout packets, a 4 byte length and JSON). The extension id of an unpacked Chromium extension comes from its folder, `ChromiumExtensionId` computes it for the manifest of the host.

### Content script
`content_matches` (match patterns) adds a content script, `content_script_file` is your own JavaScript file (default `templates/content.js`), `content_run_at` its `run_at`. It sends text with `runtime.sendMessage(text)` (a promise) and gets the reply of `on_message`: the script reads the page, Odin decides (see `youtube_shorts/youtube_content.js`).

### Options page drawn by Karl2D
`ExtensionConfig.options` takes a `web_build` package (`init`, `step`, `shutdown`, Karl2D in a canvas, the same as a web_build demo) and makes it the options page of the extension (`options_ui`, opened in a tab). The page talks to the background with `runtime.SendMessage(text)`; the answer comes to the handler of `runtime.SetReplyHandler` (the browser is asynchronous). Extension pages may not run inline scripts, so the page is built from files (`templates/options.html`, `options_run.js`) and Karl2D needs the element id `body`. If the page is written against `demo_kit` (`youtube_shorts/options`) the same code also runs in a raylib window and in headless tests: only the bridge differs.

Messages and replies are text (so are the state and the replies of the options page). They go through a fixed 16 KB input buffer and a fixed 16 KB output buffer owned by the generated entry, nothing allocates per message (`ReplyPrint` cuts text that does not fit). The popup and content script of `templates/` send strings with `runtime.sendMessage`, change them to what your `on_message` understands. Add more imports to `templates/extension.js` + `runtime/runtime.odin` (module `extension`) when Odin has to call more of the `browser.*` API; `set_badge` is the example.

The build is a call (see `demo/tool/main.odin`):

```odin
config: extension.ExtensionConfig = {source_directory = "my_extension", name = "My Extension", version = "1.0.0", id = "my-extension@example.com", popup = true}
extension.ExtensionBuild(config)                       // both targets
extension.ExtensionInstall(config, .FIREFOX)           // optional, starts the browser
```

## Build
Needs only `odin` in PATH. From `odin_utilities/browser_extension`:

```
odin run demo/tool -- all                 # everything, or: chrome | opera | edge | firefox
odin run demo/tool -- all -- -o:size      # arguments after the second -- go to `odin build`
```

Output in `demo/bin/extension/`:

| Path | For |
|---|---|
| `chromium/` | Chrome, Opera, Edge: load unpacked |
| `firefox/` | Firefox: load as temporary add-on |
| `Odin_Extension_Demo-chromium.zip` | Chrome Web Store, Opera add-ons, Edge add-ons |
| `Odin_Extension_Demo-firefox.xpi` | addons.mozilla.org (zip), signed install |

In VS Code open the `browser_extension` folder: **Ctrl+Shift+B** runs "Build Extensions", and F5 has the launch configurations "Build Extensions", "Build and Install Chrome / Opera / Edge / Firefox" (they build the tool with the debugger attached and run it with the arguments). The tasks "Build and Install ..." do the same without the debugger.

## Install automatically
```
odin run demo/tool -- chrome --install    # opera, edge, firefox, or all
```
The browser is started with a profile of its own in `demo/bin/extension/profile/<browser>`, your real profile is not touched, and keeps running after the tool exits. `--browser-path PATH` when the browser is not in the usual install folder, `--headless` for no window.

- **Chrome, Opera, Edge**: `--load-extension`. Chrome 137+ ignores it in the branded build unless `--disable-features=DisableLoadExtensionCommandLineSwitch`, which is passed. If a version still ignores it, load the folder by hand (below).
- **Firefox**: starts Firefox with the remote debugging server (port 6000, `--firefox-port N`) and installs the folder as a temporary add-on, what `web-ext run` does. Run the tool again while that Firefox is open and the add-on is reloaded. The add-on is gone when Firefox closes, run the tool again.

## Install by hand
### Chrome
1. Open `chrome://extensions`, switch **Developer mode** on (top right).
2. **Load unpacked**, choose `demo/bin/extension/chromium`.
3. After a rebuild press the reload icon of the extension card.

### Opera
1. Open `opera://extensions`, switch **Developer mode** on.
2. **Load unpacked**, choose `demo/bin/extension/chromium`.
3. Opera GX is the same.

### Edge
1. Open `edge://extensions`, switch **Developer mode** on (left panel).
2. **Load unpacked**, choose `demo/bin/extension/chromium`.

### Firefox
1. Open `about:debugging#/runtime/this-firefox`.
2. **Load Temporary Add-on...**, choose `demo/bin/extension/firefox/manifest.json` (or the `.xpi`).
3. Temporary add-ons are removed when Firefox closes. **Inspect** next to the add-on opens the console of the background.
4. Permanent: sign the `.xpi` (upload it to addons.mozilla.org as "On your own" for a private signed file), or use Firefox Developer Edition / Nightly / ESR with `xpinstall.signatures.required` = `false` in `about:config` and open the `.xpi` there.

Try it: pin the extension, click its icon, **Ping Odin**: the popup answers `pong N from Odin` and the toolbar icon shows N. Pages of https://example.com also log `page:<title>` in the background console (content script of the demo).

## Look at the background
- Chrome / Opera / Edge: on the extension card click **service worker** (Inspect views), console shows `[odin] ...` from `runtime.Log`.
- Firefox: **Inspect** on `about:debugging`.

## Things to know
- A service worker is stopped by the browser when idle and started for the next message: `init` runs again and Odin globals start fresh. Keep what must survive in `storage` (add the `storage` permission and an import). Firefox event pages behave the same way.
- Odin on `js_wasm32` has no threads and no file system. Anything the browser offers (storage, tabs, notifications) is reached through imports in `extension.js`.
- `odin.js` (the Odin JavaScript runtime, copied from your Odin install) is part of every package. In the service worker it needs `window`, `background.js` sets `self.window = self` before loading it.
- The manifest asks for `'wasm-unsafe-eval'` in the extension page CSP, without it no browser compiles `main.wasm`. Store review accepts it for wasm.
- The Firefox manifest has a gecko `id` (required to keep storage between loads) and `data_collection_permissions` (needs Firefox 140+, older versions only warn).
- Extension pages (popup, options) may not run inline scripts or inline event handlers: everything is a file.
- Not on the list: Safari (needs an Xcode project) and Manifest V2.

## Tests
```
odin test . -strict-style -vet            # manifests of both targets, the Firefox protocol packets
odin test youtube_shorts -strict-style -vet && odin test youtube_shorts/options -strict-style -vet
odin check demo/tool -strict-style -vet
```
Checked in real browsers (Windows): Edge and Opera GX load the unpacked folder, the service worker answers `ping` through the wasm; Firefox accepts the add-on through `installTemporaryAddon`. Chrome itself was not installed on the machine, it shares the Chromium path with Edge and Opera.
