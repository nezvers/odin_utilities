package browser_drive

// Start a browser, load a page in it, click, type, read values from the page, answer its file chooser, take screenshots and collect what the page writes to its console as an error. One API over
// two protocols: Chrome and Edge speak the DevTools protocol (CDP), Firefox speaks WebDriver BiDi. Both are JSON messages over a WebSocket (websocket.odin), so no driver program is needed.
//
//     driver: ^Driver = new(Driver)                     // about 17 MB of buffers, once
//     if DriverStart(driver, {browser = .CHROME}) != .NONE { ... }
//     defer DriverStop(driver)
//     DriverNavigate(driver, "http://127.0.0.1:8000/")
//     DriverClick(driver, 84, 58)
//     DriverWait(driver, 500)                           // events (console, file dialogs) are handled while the driver waits or calls
//     title, _ := DriverEvaluate(driver, "document.title")
//
// Memory: the buffers are in `Driver`; the JSON of every message is parsed with the temp allocator, so free it now and then (`free_all(context.temp_allocator)`), and the strings that come back
// (`DriverEvaluate`, `DriverConsoleErrors`, `DriverLastError`) are valid until the next call.

import "core:encoding/base64"
import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:time"

INCOMING_CAPACITY :: 8 * 1024 * 1024        // one frame: a screenshot is one
MESSAGE_CAPACITY :: 8 * 1024 * 1024
OUTGOING_CAPACITY :: 256 * 1024
CONSOLE_CAPACITY :: 8192
PATH_CAPACITY :: 512
DEFAULT_TIMEOUT_MS :: 15000

Error :: enum {
    NONE,
    NO_BROWSER,             // the browser is not installed (not a failure of the test: skip)
    START_FAILED,
    CONNECT_FAILED,         // the browser started and did not answer, or a page did not load
    PROTOCOL,               // the browser answered with an error: DriverLastError says which
    TIMEOUT,
    CLOSED,
    SCRIPT,                 // the expression threw in the page
    FILE,
}

DriverConfig :: struct {
    browser: Browser,
    executable: string,     // "" - find the installed one
    width: int,             // the viewport, 0 - 1280
    height: int,            // 0 - 720
    visible: bool,          // a window instead of headless
    extension: string,      // Chrome and Edge: an unpacked extension folder to load (absolute path); see DriverExtensionId
    timeout_ms: int,        // for a call, a page load, the start; 0 - 15000
}

Driver :: struct {
    config: DriverConfig,
    protocol: Protocol,
    process: os.Process,
    started: bool,
    port: int,
    profile: [PATH_CAPACITY]u8,
    profile_length: int,
    extension_id: [64]u8,           // DriverExtensionId
    ws: WebSocket,
    next_id: int,
    context_id: [64]u8,                 // BiDi: the tab that is driven
    context_length: int,
    console: [CONSOLE_CAPACITY]u8,      // the errors the page wrote, a line each
    console_length: int,
    pending_file: [PATH_CAPACITY]u8,    // the file the next file chooser gets
    pending_length: int,
    file_dialogs: int,                  // choosers that were answered
    last_error: [512]u8,
    last_error_length: int,
    incoming: [INCOMING_CAPACITY]u8,
    message: [MESSAGE_CAPACITY]u8,
    outgoing: [OUTGOING_CAPACITY]u8,
}

// --- start and stop ---

// A free port: the system hands one out for a socket that asks for port 0
@(private)
freePort :: proc() -> int {
    socket, listen_error := net.listen_tcp({net.IP4_Loopback, 0})
    if listen_error != nil { return 0 }
    defer net.close(socket)
    endpoint, _ := net.bound_endpoint(socket)
    return endpoint.port
}

DriverStart :: proc(driver: ^Driver, config: DriverConfig) -> Error {
    driver.config = config
    if driver.config.width == 0 { driver.config.width = 1280 }
    if driver.config.height == 0 { driver.config.height = 720 }
    if driver.config.timeout_ms == 0 { driver.config.timeout_ms = DEFAULT_TIMEOUT_MS }
    driver.protocol = BrowserProtocol(config.browser)
    driver.next_id, driver.console_length, driver.pending_length, driver.file_dialogs, driver.last_error_length, driver.context_length = 0, 0, 0, 0, 0, 0
    executable: string = config.executable if len(config.executable) > 0 else BrowserFind(config.browser)
    if len(executable) == 0 { return .NO_BROWSER }

    driver.port = freePort()
    if driver.port == 0 { return .START_FAILED }
    temp, _ := os.temp_directory(context.temp_allocator)
    profile: string = fmt.tprintf("%s/odin_utilities_browser_drive_%d", temp, driver.port)
    os.remove_all(profile)
    if os.make_directory_all(profile) != nil { return .START_FAILED }
    driver.profile_length = copy(driver.profile[:], profile)

    command: [dynamic]string
    command.allocator = context.temp_allocator
    append(&command, executable)
    if driver.protocol == .CDP {
        // a profile of its own: a browser that is already open would take the request and exit
        append(&command, "--disable-gpu", fmt.tprintf("--remote-debugging-port=%d", driver.port), fmt.tprintf("--user-data-dir=%s", profile), "--no-first-run",
            "--no-default-browser-check", "--autoplay-policy=no-user-gesture-required", fmt.tprintf("--window-size=%d,%d", driver.config.width, driver.config.height))
        if len(config.extension) > 0 {
            // Chrome 137+ ignores --load-extension in the branded build unless this feature is off
            append(&command, fmt.tprintf("--load-extension=%s", config.extension), "--disable-features=DisableLoadExtensionCommandLineSwitch")
        }
        if !config.visible { append(&command, "--headless=new") }
    } else {
        append(&command, "--no-remote", "--profile", profile, "--remote-debugging-port", fmt.tprintf("%d", driver.port), "--width", fmt.tprintf("%d", driver.config.width),
            "--height", fmt.tprintf("%d", driver.config.height))
        if !config.visible { append(&command, "--headless") }
    }
    append(&command, "about:blank")
    process, start_error := os.process_start({command = command[:]})
    if start_error != nil { return .START_FAILED }
    driver.process = process
    driver.started = true

    WebSocketInit(&driver.ws, driver.incoming[:], driver.message[:], driver.outgoing[:])
    if !driverConnect(driver) {
        DriverStop(driver)
        return .CONNECT_FAILED
    }
    if error := driverSetup(driver); error != .NONE {
        DriverStop(driver)
        return error
    }
    return .NONE
}

// The browser needs a moment before it listens: try until it does
@(private)
driverConnect :: proc(driver: ^Driver) -> bool {
    deadline: time.Time = time.time_add(time.now(), time.Duration(driver.config.timeout_ms) * time.Millisecond)
    for time.diff(time.now(), deadline) > 0 {
        if driver.protocol == .BIDI {
            if WebSocketConnect(&driver.ws, "127.0.0.1", driver.port, "/session") { return true }
        } else {
            // the list of tabs: the first page is the one to drive
            body, ok := HttpGet(driver.port, "/json", driver.message[:])
            if ok {
                list, parse_error := json.parse(transmute([]u8)body, json.DEFAULT_SPECIFICATION, true, context.temp_allocator)
                if array, is_array := list.(json.Array); parse_error == .None && is_array {
                    for item in array {
                        if jsonText(jsonPath(item, "type")) != "page" { continue }
                        url: string = jsonText(jsonPath(item, "webSocketDebuggerUrl"))
                        // ws://127.0.0.1:PORT/devtools/page/ID: the path is what the handshake needs
                        start: int = strings.index(url, "/devtools/")
                        if start >= 0 && WebSocketConnect(&driver.ws, "127.0.0.1", driver.port, url[start:]) { return true }
                    }
                }
            }
        }
        time.sleep(200 * time.Millisecond)
    }
    return false
}

// What has to be switched on before the page is used: the events that the driver collects, the viewport, the file chooser
@(private)
driverSetup :: proc(driver: ^Driver) -> Error {
    if driver.protocol == .CDP {
        for method in ([?]string{"Runtime.enable", "Page.enable", "Log.enable", "DOM.enable"}) {
            if _, error := DriverCall(driver, method); error != .NONE { return error }
        }
        // the file chooser does not open a window: the browser says that it wanted one (Page.fileChooserOpened) and the driver answers
        DriverCall(driver, "Page.setInterceptFileChooserDialog", `{"enabled":true}`)
        DriverCall(driver, "Emulation.setDeviceMetricsOverride", fmt.tprintf(`{{"width":%d,"height":%d,"deviceScaleFactor":1,"mobile":false}}`, driver.config.width, driver.config.height))
        return .NONE
    }
    if _, error := DriverCall(driver, "session.new", `{"capabilities":{}}`); error != .NONE { return error }
    if _, error := DriverCall(driver, "session.subscribe", `{"events":["log.entryAdded","input.fileDialogOpened"]}`); error != .NONE { return error }
    tree, error := DriverCall(driver, "browsingContext.getTree")
    if error != .NONE { return error }
    contexts, is_array := jsonPath(tree, "contexts").(json.Array)
    if !is_array || len(contexts) == 0 { return .PROTOCOL }
    driver.context_length = copy(driver.context_id[:], jsonText(jsonPath(contexts[0], "context")))
    // the window of Firefox has bars: the viewport is set to the size that was asked for (an older Firefox does not know the command, the window size stays)
    DriverCall(driver, "browsingContext.setViewport", fmt.tprintf(`{{"context":%s,"viewport":{{"width":%d,"height":%d}}}}`, quote(driverContext(driver)), driver.config.width, driver.config.height))
    return .NONE
}

DriverStop :: proc(driver: ^Driver) {
    if !driver.started { return }
    if driver.ws.open {
        // asks the browser to quit; it may close the socket before it answers
        DriverSend(driver, "Browser.close" if driver.protocol == .CDP else "browser.close", "{}")
        WebSocketClose(&driver.ws)
    }
    if _, error := os.process_wait(driver.process, 2000 * time.Millisecond); error != nil {
        _ = os.process_kill(driver.process)
        _, _ = os.process_wait(driver.process, 2000 * time.Millisecond)
    }
    driver.started = false
    // the browser may still hold files of its profile for a moment
    for _ in 0 ..< 5 {
        if os.remove_all(string(driver.profile[:driver.profile_length])) == nil { break }
        time.sleep(200 * time.Millisecond)
    }
}

// --- calls ---

// Send a call and wait for its answer; events that arrive meanwhile are handled. `result` is the answer's result (a JSON value in the temp allocator).
DriverCall :: proc(driver: ^Driver, method: string, params: string = "{}") -> (result: json.Value, error: Error) {
    driver.next_id += 1
    id: int = driver.next_id
    if !WebSocketSend(&driver.ws, fmt.tprintf(`{{"id":%d,"method":"%s","params":%s}}`, id, method, params)) { return nil, .CLOSED }
    deadline: time.Time = time.time_add(time.now(), time.Duration(driver.config.timeout_ms) * time.Millisecond)
    for {
        remaining: time.Duration = time.diff(time.now(), deadline)
        if remaining <= 0 { return nil, .TIMEOUT }
        text, status := WebSocketReceive(&driver.ws, int(time.duration_milliseconds(remaining)) + 1)
        switch status {
        case .MESSAGE:
        case .TIMEOUT: return nil, .TIMEOUT
        case .CLOSED: return nil, .CLOSED
        case .TOO_BIG: return nil, .PROTOCOL
        }
        root, parse_error := json.parse(transmute([]u8)text, json.DEFAULT_SPECIFICATION, true, context.temp_allocator)
        object, is_object := root.(json.Object)
        if parse_error != .None || !is_object { continue }
        reply_id, is_reply := object["id"]
        if !is_reply {
            driverEvent(driver, object)
            continue
        }
        if number, is_number := reply_id.(json.Integer); !is_number || int(number) != id { continue }     // the answer to a call that nobody waits for
        if failure, failed := object["error"]; failed {
            // CDP: {"code":..,"message":..}, BiDi: "error" is a name and "message" the text
            message: string = jsonText(jsonPath(failure, "message"))
            if len(message) == 0 { message = fmt.tprintf("%s %s", jsonText(failure), jsonText(object["message"])) }
            driverSetError(driver, fmt.tprintf("%s: %s", method, message))
            return nil, .PROTOCOL
        }
        return object["result"], .NONE
    }
}

// A call whose answer nobody waits for (the answer arrives later and is dropped)
DriverSend :: proc(driver: ^Driver, method: string, params: string = "{}") -> bool {
    driver.next_id += 1
    return WebSocketSend(&driver.ws, fmt.tprintf(`{{"id":%d,"method":"%s","params":%s}}`, driver.next_id, method, params))
}

// Let the browser work for `ms`: events (console errors, file choosers) are handled meanwhile
DriverWait :: proc(driver: ^Driver, ms: int) {
    deadline: time.Time = time.time_add(time.now(), time.Duration(ms) * time.Millisecond)
    for {
        remaining: time.Duration = time.diff(time.now(), deadline)
        if remaining <= 0 || !driver.ws.open { return }
        text, status := WebSocketReceive(&driver.ws, int(time.duration_milliseconds(remaining)) + 1)
        if status != .MESSAGE { return }
        root, parse_error := json.parse(transmute([]u8)text, json.DEFAULT_SPECIFICATION, true, context.temp_allocator)
        object, is_object := root.(json.Object)
        if parse_error == .None && is_object {
            if _, is_reply := object["id"]; !is_reply { driverEvent(driver, object) }
        }
    }
}

// The id of the unpacked extension (DriverConfig.extension, Chrome and Edge) with this manifest name: the host of its pages, `chrome-extension://<id>/options/options.html`. The browser's own
// chrome://extensions page knows it (a service worker target only exists once the worker was woken, and the browser's built in extensions have targets too), so this navigates the tab there:
// navigate again afterwards. "" when it is not found. Valid until the next call.
DriverExtensionId :: proc(driver: ^Driver, name: string) -> string {
    if driver.protocol != .CDP { return "" }
    if DriverNavigate(driver, "chrome://extensions/") != .NONE { return "" }
    expression: string = fmt.tprintf("chrome.developerPrivate.getExtensionsInfo().then(list => (list.find(e => e.location === 'UNPACKED' && e.name === %s) || {{id: ''}}).id)", quote(name))
    id, error := DriverEvaluate(driver, expression)
    if error != .NONE || len(id) > len(driver.extension_id) { return "" }
    copy(driver.extension_id[:], id)
    return string(driver.extension_id[:len(id)])
}

// Load a page and wait until it says it is loaded
DriverNavigate :: proc(driver: ^Driver, url: string) -> Error {
    if driver.protocol == .CDP {
        result, error := DriverCall(driver, "Page.navigate", fmt.tprintf(`{{"url":%s}}`, quote(url)))
        if error != .NONE { return error }
        if failure := jsonText(jsonPath(result, "errorText")); len(failure) > 0 {
            driverSetError(driver, fmt.tprintf("%s: %s", url, failure))
            return .CONNECT_FAILED
        }
    } else {
        if _, error := DriverCall(driver, "browsingContext.navigate", fmt.tprintf(`{{"context":%s,"url":%s,"wait":"complete"}}`, quote(driverContext(driver)), quote(url))); error != .NONE { return error }
    }
    return DriverWaitUntil(driver, "document.readyState === 'complete'")
}

// The page's own value of an expression, as text (`String(expression)`: use JSON.stringify(...) in the expression for an object). A promise is waited for. The text is valid until the next call.
DriverEvaluate :: proc(driver: ^Driver, expression: string) -> (value: string, error: Error) {
    wrapped: string = quote(fmt.tprintf("(async () => String(await (%s)))()", expression))
    if driver.protocol == .CDP {
        result, call_error := DriverCall(driver, "Runtime.evaluate", fmt.tprintf(`{{"expression":%s,"returnByValue":true,"awaitPromise":true}}`, wrapped))
        if call_error != .NONE { return "", call_error }
        if details, thrown := jsonPath(result, "exceptionDetails").(json.Object); thrown {
            text: string = jsonText(jsonPath(details["exception"], "description"))
            driverSetError(driver, text if len(text) > 0 else jsonText(details["text"]))
            return "", .SCRIPT
        }
        return jsonText(jsonPath(result, "result", "value")), .NONE
    }
    result, call_error := DriverCall(driver, "script.evaluate", fmt.tprintf(`{{"expression":%s,"target":{{"context":%s}},"awaitPromise":true,"resultOwnership":"none"}}`, wrapped, quote(driverContext(driver))))
    if call_error != .NONE { return "", call_error }
    if jsonText(jsonPath(result, "type")) == "exception" {
        driverSetError(driver, jsonText(jsonPath(result, "exceptionDetails", "text")))
        return "", .SCRIPT
    }
    return jsonText(jsonPath(result, "result", "value")), .NONE
}

// Wait until an expression of the page is true
DriverWaitUntil :: proc(driver: ^Driver, expression: string, timeout_ms: int = 0) -> Error {
    limit: int = timeout_ms if timeout_ms > 0 else driver.config.timeout_ms
    deadline: time.Time = time.time_add(time.now(), time.Duration(limit) * time.Millisecond)
    for time.diff(time.now(), deadline) > 0 {
        value, error := DriverEvaluate(driver, expression)
        if error == .NONE && value == "true" { return .NONE }
        if error == .CLOSED { return error }
        DriverWait(driver, 50)
    }
    return .TIMEOUT
}

// A click of the left mouse button at a point of the viewport (a person's click: the browser allows what needs a gesture, a file chooser or a download)
DriverClick :: proc(driver: ^Driver, x: f64, y: f64) -> Error {
    if driver.protocol == .CDP {
        for kind in ([?]string{"mouseMoved", "mousePressed", "mouseReleased"}) {
            buttons: int = 1 if kind == "mousePressed" else 0
            if _, error := DriverCall(driver, "Input.dispatchMouseEvent", fmt.tprintf(`{{"type":"%s","x":%v,"y":%v,"button":"left","buttons":%d,"clickCount":1}}`, kind, x, y, buttons)); error != .NONE { return error }
        }
        return .NONE
    }
    _, error := DriverCall(driver, "input.performActions", fmt.tprintf(
        `{{"context":%s,"actions":[{{"type":"pointer","id":"mouse","parameters":{{"pointerType":"mouse"}},"actions":[{{"type":"pointerMove","x":%d,"y":%d}},{{"type":"pointerDown","button":0}},{{"type":"pointerUp","button":0}}]}}]}}`,
        quote(driverContext(driver)), int(x), int(y)))
    return error
}

// Type text into what has the focus
DriverType :: proc(driver: ^Driver, text: string) -> Error {
    if driver.protocol == .CDP {
        _, error := DriverCall(driver, "Input.insertText", fmt.tprintf(`{{"text":%s}}`, quote(text)))
        return error
    }
    actions: strings.Builder
    strings.builder_init(&actions, context.temp_allocator)
    for character in text {
        one: string = quote(fmt.tprintf("%c", character))
        fmt.sbprintf(&actions, `%s{{"type":"keyDown","value":%s}},{{"type":"keyUp","value":%s}}`, "," if strings.builder_len(actions) > 0 else "", one, one)
    }
    _, error := DriverCall(driver, "input.performActions", fmt.tprintf(`{{"context":%s,"actions":[{{"type":"key","id":"keyboard","actions":[%s]}}]}}`, quote(driverContext(driver)), strings.to_string(actions)))
    return error
}

// The picture of the page as base64 PNG text (temp allocator, valid until the temp allocator is cleared)
@(private)
driverCapture :: proc(driver: ^Driver) -> (data: string, error: Error) {
    result: json.Value
    if driver.protocol == .CDP {
        result, error = DriverCall(driver, "Page.captureScreenshot", `{"format":"png"}`)
    } else {
        result, error = DriverCall(driver, "browsingContext.captureScreenshot", fmt.tprintf(`{{"context":%s}}`, quote(driverContext(driver))))
    }
    if error != .NONE { return "", error }
    data = jsonText(jsonPath(result, "data"))
    if len(data) == 0 { return "", .PROTOCOL }
    return data, .NONE
}

// The picture of the page as a PNG file
DriverScreenshot :: proc(driver: ^Driver, path: string) -> Error {
    data, error := driverCapture(driver)
    if error != .NONE { return error }
    png, decode_error := base64.decode(data, allocator = context.temp_allocator)
    if decode_error != nil || len(png) == 0 { return .PROTOCOL }
    if os.write_entire_file(path, png) != nil { return .FILE }
    return .NONE
}

// A number that is the same for two pictures of the page that are the same (a hash of the PNG; the same pixels give the same PNG)
DriverPictureHash :: proc(driver: ^Driver) -> (hash: u64, error: Error) {
    // the picture is a few hundred KB of text: give it back at once, a wait takes many of them
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    data, capture_error := driverCapture(driver)
    if capture_error != .NONE { return 0, capture_error }
    hash = 14695981039346656037 // FNV-1a
    for b in transmute([]u8)data {
        hash = (hash ~ u64(b)) * 1099511628211
    }
    return hash, .NONE
}

// Wait until the picture of the page has not changed for `quiet_ms` (the default 200): for a canvas that is drawn in the frames after a click, where there is no event to wait for. A page that
// always moves (a blinking cursor, an animation) never gets quiet: .TIMEOUT after `timeout_ms` (0 - the driver's timeout).
DriverWaitStable :: proc(driver: ^Driver, quiet_ms: int = 200, timeout_ms: int = 0) -> Error {
    limit: int = timeout_ms if timeout_ms > 0 else driver.config.timeout_ms
    deadline: time.Time = time.time_add(time.now(), time.Duration(limit) * time.Millisecond)
    last, error := DriverPictureHash(driver)
    if error != .NONE { return error }
    since: time.Time = time.now()
    for time.diff(time.now(), deadline) > 0 {
        DriverWait(driver, 30)
        hash: u64
        hash, error = DriverPictureHash(driver)
        if error != .NONE { return error }
        if hash != last {
            last = hash
            since = time.now()
        } else if time.diff(since, time.now()) >= time.Duration(quiet_ms) * time.Millisecond {
            return .NONE
        }
    }
    return .TIMEOUT
}

// Wait until the picture differs from the one with hash `before` (take it with DriverPictureHash before the click) and is quiet again: the page reacted and finished drawing
DriverWaitChanged :: proc(driver: ^Driver, before: u64, quiet_ms: int = 200, timeout_ms: int = 0) -> Error {
    limit: int = timeout_ms if timeout_ms > 0 else driver.config.timeout_ms
    deadline: time.Time = time.time_add(time.now(), time.Duration(limit) * time.Millisecond)
    for time.diff(time.now(), deadline) > 0 {
        hash, error := DriverPictureHash(driver)
        if error != .NONE { return error }
        if hash != before { return DriverWaitStable(driver, quiet_ms, int(time.diff(time.now(), deadline) / time.Millisecond)) }
        DriverWait(driver, 30)
    }
    return .TIMEOUT
}

// The file that the next file chooser of the page gets (a page can only open it after a click: click, then DriverWait). The path is a path of this machine.
DriverAnswerFileChooser :: proc(driver: ^Driver, path: string) {
    driver.pending_length = copy(driver.pending_file[:], path)
}

// How many file choosers were answered so far
DriverFileDialogs :: proc(driver: ^Driver) -> int {
    return driver.file_dialogs
}

// Remember what the page saves as a download (an anchor with `download` that is clicked): a headless browser has no place to put it and no event for all browsers. Call it after each navigation.
DriverTrackDownloads :: proc(driver: ^Driver) -> Error {
    _, error := DriverEvaluate(driver, `(() => { if (!window.__driveDownloads) { window.__driveDownloads = []; const click = HTMLAnchorElement.prototype.click;
        HTMLAnchorElement.prototype.click = function () { const a = this; if (a.download) { fetch(a.href).then(r => r.arrayBuffer()).then(b => window.__driveDownloads.push(a.download + ':' + b.byteLength)); } return click.call(this); }; } return 'tracking'; })()`)
    return error
}

// The downloads so far as "name:bytes,name:bytes"
DriverDownloads :: proc(driver: ^Driver) -> string {
    value, _ := DriverEvaluate(driver, "window.__driveDownloads ? window.__driveDownloads.join(',') : ''")
    return value
}

// What the page wrote to its console as an error (an exception, console.error, a failed load), a line each
DriverConsoleErrors :: proc(driver: ^Driver) -> string {
    return string(driver.console[:driver.console_length])
}

DriverConsoleClear :: proc(driver: ^Driver) {
    driver.console_length = 0
}

// The text of the last error of the browser (the call that failed, and what it said)
DriverLastError :: proc(driver: ^Driver) -> string {
    return string(driver.last_error[:driver.last_error_length])
}

// --- events ---

@(private)
driverContext :: proc(driver: ^Driver) -> string {
    return string(driver.context_id[:driver.context_length])
}

@(private)
driverSetError :: proc(driver: ^Driver, text: string) {
    driver.last_error_length = copy(driver.last_error[:], text)
}

@(private)
driverConsoleAdd :: proc(driver: ^Driver, text: string) {
    if len(text) == 0 || driver.console_length >= CONSOLE_CAPACITY - 1 { return }
    driver.console_length += copy(driver.console[driver.console_length:CONSOLE_CAPACITY - 1], text)
    driver.console[driver.console_length] = '\n'
    driver.console_length += 1
}

@(private)
driverEvent :: proc(driver: ^Driver, event: json.Object) {
    method: string = jsonText(event["method"])
    params: json.Value = event["params"]
    switch method {
    case "Runtime.consoleAPICalled":
        if jsonText(jsonPath(params, "type")) != "error" { return }
        line: strings.Builder
        strings.builder_init(&line, context.temp_allocator)
        if arguments, is_array := jsonPath(params, "args").(json.Array); is_array {
            for argument in arguments {
                text: string = jsonText(jsonPath(argument, "value"))
                if len(text) == 0 { text = jsonText(jsonPath(argument, "description")) }
                if strings.builder_len(line) > 0 { strings.write_byte(&line, ' ') }
                strings.write_string(&line, text)
            }
        }
        driverConsoleAdd(driver, strings.to_string(line))
    case "Runtime.exceptionThrown":
        details: json.Value = jsonPath(params, "exceptionDetails")
        text: string = jsonText(jsonPath(details, "exception", "description"))
        driverConsoleAdd(driver, text if len(text) > 0 else jsonText(jsonPath(details, "text")))
    case "Log.entryAdded":
        if jsonText(jsonPath(params, "entry", "level")) == "error" { driverConsoleAdd(driver, jsonText(jsonPath(params, "entry", "text"))) }
    case "log.entryAdded":
        if jsonText(jsonPath(params, "level")) == "error" { driverConsoleAdd(driver, jsonText(jsonPath(params, "text"))) }
    case "Page.fileChooserOpened":
        if driver.pending_length == 0 { return }
        node, is_number := jsonPath(params, "backendNodeId").(json.Integer)
        if !is_number { return }
        DriverSend(driver, "DOM.setFileInputFiles", fmt.tprintf(`{{"files":[%s],"backendNodeId":%d}}`, quote(string(driver.pending_file[:driver.pending_length])), node))
        driver.pending_length = 0
        driver.file_dialogs += 1
    case "input.fileDialogOpened":
        if driver.pending_length == 0 { return }
        path: string = string(driver.pending_file[:driver.pending_length])
        // Firefox takes a path of the system it runs on
        when ODIN_OS == .Windows { path, _ = strings.replace_all(path, "/", "\\", context.temp_allocator) }
        DriverSend(driver, "input.setFiles", fmt.tprintf(`{{"context":%s,"element":{{"sharedId":%s}},"files":[%s]}}`,
            quote(jsonText(jsonPath(params, "context"))), quote(jsonText(jsonPath(params, "element", "sharedId"))), quote(path)))
        driver.pending_length = 0
        driver.file_dialogs += 1
    }
}

// --- json helpers ---

// The value at a path of object keys, nil when a key is missing
@(private)
jsonPath :: proc(value: json.Value, keys: ..string) -> json.Value {
    current: json.Value = value
    for key in keys {
        object, is_object := current.(json.Object)
        if !is_object { return nil }
        next, found := object[key]
        if !found { return nil }
        current = next
    }
    return current
}

@(private)
jsonText :: proc(value: json.Value) -> string {
    text, is_string := value.(json.String)
    return string(text) if is_string else ""
}

// A string as JSON text, with its quotes (temp allocator)
@(private)
quote :: proc(text: string) -> string {
    bytes, _ := json.marshal(text, {}, context.temp_allocator)
    return string(bytes)
}
