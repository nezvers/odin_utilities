# browser_drive

Drive Chrome, Edge and Firefox over their debugging protocols. See README for the API. Non visual library: no demos.

- `websocket.odin`: client (handshake with the accept check, masked frames, fragments, ping/pong, close). `FrameEncode` / `FrameParse` / `WebSocketAccept` are pure and tested against the RFC 6455 examples. All buffers are the caller's, `incoming` must hold the biggest single frame (a screenshot).
- `http.odin`: one GET for the DevTools target list. Chrome keeps the connection open after `Connection: close`, so the end of the answer is the `Content-Length`, not the end of the stream (this was the bug that made Chrome "not connect").
- `browsers.odin`: `Browser`, `BrowserProtocol`, `BrowserFind` (install paths, Windows, Linux, macOS).
- `driver.odin`: `DriverStart` (free port, own profile folder, `os.process_start`, retry connect), `DriverCall` (id match, other messages are events), `driverEvent` (console errors, file choosers), the high level calls.
- Differences handled inside, so a caller sees one API: CDP has to find the page target (`/json`, first `type == "page"`, the background pages of extensions are skipped) and uses `Page.setInterceptFileChooserDialog` + `DOM.setFileInputFiles`; BiDi has a browsing context (`browsingContext.getTree`) and answers `input.fileDialogOpened` with `input.setFiles`.
- File chooser: a headless Firefox has no dialog and cancels it at once, so the answer is sent from the event handler, in the same pass (not after the wait). Firefox wants a path with backslashes on Windows (done in `driverEvent`). Click first, then `DriverWait`: events are only read while the driver waits or calls.
- Downloads: no protocol event is shared by both, so `DriverTrackDownloads` wraps `HTMLAnchorElement.prototype.click` in the page (call it again after each navigation).
- Console errors: CDP `Runtime.exceptionThrown`, `Runtime.consoleAPICalled` (type error), `Log.entryAdded` (level error: failed loads, a 404 for a missing favicon counts); BiDi `log.entryAdded` (level error).
- Strings are built with `fmt.tprintf` and `json.marshal` of a string (`quote`), JSON parsed in the temp allocator. A path or an expression is always quoted, never pasted into the JSON.
- Tests (`browser_drive_test.odin`, `#+build !js`): the RFC vectors, and per browser one flow over a page served by `web_serve`: evaluate, exception, click, console error, type, file chooser, download, screenshot. A browser that is not installed is skipped with a printed line. They take a few seconds each and run in parallel.
- Commands: `odin test browser_drive -strict-style -vet`. A headless browser of yours may stay running if a test is killed: the profile folders are `odin_utilities_browser_drive_<port>` in the temp directory.
- Never kill browsers by name (`taskkill /IM firefox.exe` would close the user's own windows): the driver stops only the process it started.
- Extensions: `DriverConfig.extension` (Chrome, Edge: unpacked folder, loaded with `--load-extension` and the feature switch) and `DriverExtensionId(driver, manifest_name)`, which reads the id from chrome://extensions (`chrome.developerPrivate`): a service worker target exists only after it was woken and the browser has built in extensions with workers of their own, so targets cannot tell. The branded Chrome 158 does not load it at all (id is "").
- `DriverEvaluate` wraps the expression in an async function that awaits it, so a promise gives its value (it printed `[object Promise]` before).
