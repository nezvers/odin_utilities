# browser_drive

Drive a real browser from Odin: load a page, click, type, read values out of the page, answer its file chooser, take screenshots, and collect what the page writes to its console as an error. For testing anything that runs in a browser: a web build of a game (`web_build`), a browser extension, a page you serve with `web_serve`. Chrome and Edge are driven through the Chrome DevTools Protocol, Firefox through WebDriver BiDi. Both are JSON over a WebSocket, so there is no driver program, no Node and no Selenium: a WebSocket client (`websocket.odin`) and the two protocols.

```odin
driver: ^browser_drive.Driver = new(browser_drive.Driver)            // about 17 MB of buffers, once
switch browser_drive.DriverStart(driver, {browser = .FIREFOX}) {     // .CHROME, .EDGE, .FIREFOX; visible = true for a window
case .NONE:
case .NO_BROWSER: return                                             // not installed: skip, do not fail
case: panic(browser_drive.DriverLastError(driver))
}
defer browser_drive.DriverStop(driver)

browser_drive.DriverNavigate(driver, "http://127.0.0.1:8000/")       // waits for document.readyState
browser_drive.DriverClick(driver, 84, 58)                            // a real mouse click: the browser allows what needs a gesture
browser_drive.DriverWait(driver, 500)                                // events are handled while the driver waits or calls
title, _ := browser_drive.DriverEvaluate(driver, "document.title")   // String(expression); JSON.stringify(...) for structured data
errors := browser_drive.DriverConsoleErrors(driver)                  // "" when the page wrote none
```

## What it does
| Call | What |
|---|---|
| `DriverStart`, `DriverStop` | start the browser with a profile of its own (an open browser of yours is not touched), connect, stop it and delete the profile |
| `DriverNavigate`, `DriverWaitUntil(expression)` | load a page, wait for an expression of the page to be true |
| `DriverEvaluate` | the value of an expression, a promise is awaited; an exception in the page is `.SCRIPT` |
| `DriverClick`, `DriverType` | a click at a point of the viewport, text into what has the focus |
| `DriverAnswerFileChooser(path)`, `DriverFileDialogs` | the file the next `<input type=file>` chooser gets (a headless browser shows no dialog: the driver answers the event) |
| `DriverTrackDownloads`, `DriverDownloads` | what the page saves with an `<a download>`, as `name:bytes,...` (the same on every browser) |
| `DriverConsoleErrors`, `DriverConsoleClear` | uncaught exceptions, `console.error`, failed loads (a 404, a failed import) |
| `DriverScreenshot(path)` | a PNG of the page |
| `DriverPictureHash`, `DriverWaitStable`, `DriverWaitChanged(before)` | wait for a canvas that has no event: until the picture is quiet, or until it changed (after a click) and is quiet again. The quiet time must be longer than the page's own delays; a page that always moves times out |
| `DriverCall`, `DriverSend` | any command of the protocol (`Page.reload`, `browsingContext.reload`, ...) with its JSON params |

`BrowserFind(browser)` says whether one is installed; a test that needs a browser skips when it is not.

## Memory
`Driver` holds every buffer (incoming frames 8 MB, the message 8 MB, outgoing 256 KB, console 8 KB), so allocate it once with `new`. The JSON of each message is parsed with the temp allocator: call `free_all(context.temp_allocator)` now and then in a long run. Strings that come back are valid until the next call.

## Limits
Local browsers only (127.0.0.1, no TLS). One tab. A viewport size, not device emulation. `DriverType` types characters, it has no named keys yet.

## Example
`file_browser/demo_web/drive` clicks through the web demo of `file_browser` in Chrome, Edge or Firefox (`odin run file_browser/demo_web/build_web -- --drive firefox`), and `odin run tool/test -- --browser` runs it with the other checks.
