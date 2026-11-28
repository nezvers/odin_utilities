# file_browser

Open and save files from an Odin program on the desktop and in a web page, with a dialog made of the `ui` library, extension filters and remembered folders. Framework agnostic, no hidden allocations: the caller gives the entry list, the name storage and the buffer a file is read into.

## Use
```odin
browser: file_browser.FileBrowser
entries: [256]file_browser.Entry
names: [16384]u8
file_browser.FileBrowserInit(&browser, file_browser.IoPlatform(), entries[:], names[:])

// every frame
file_browser.FileBrowserUpdate(&browser)                    // results arrive once, through the Result of UiFileBrowser
result := file_browser.UiFileBrowser(ctx, &browser)         // draws the dialog while one is open
if result.kind == .OPENED { /* result.path, result.data (the bytes, in your buffer) */ }

// from a button
file_browser.FileBrowserOpen(&browser, buffer[:], filters)                     // filters: {name = "Pictures", extensions = {"png", "jpg"}}
file_browser.FileBrowserSave(&browser, bytes, "picture.png", filters)
```
- `IoPlatform()` is the disk on a desktop (`IoOs`) and the file chooser plus a download in a web page (`IoWeb`, needs `file_browser.js`, see `demo_web`). `IoMemory` is a file system in fixed memory for tests.
- Filters: case insensitive, dot optional, compound extensions ("tar.gz"), "*" for all. `FilterAccept` gives the `accept` text of an HTML file input.
- Folders: the last opened and last saved folder are remembered, shared or separate (`FileBrowserSetMemory`); `FileBrowserSetDirectories` loads them from your own settings and `FileBrowserDirectories` reads them back.
- State and errors: `browser.state` (IDLE, BROWSING, PICKING, OPENED, SAVED, CANCELLED, FAILED), `browser.error`, `FileBrowserStatus` is a sentence for a label.
- Saving over an existing file asks first.

## Demos
`odin run file_browser/demo_raylib`, `odin run file_browser/demo_karl2d`: open a picture (png, jpg, bmp) and a sound (wav, ogg), invert the picture, make a tone, play the sound, save both back; labels show the state and the error. `-define:DEMO_TEST=true` plays the script over files in memory.
Web: `odin run file_browser/demo_web/build_web -- --open` builds with `web_build` and serves with `web_serve` (from odin_utilities).
