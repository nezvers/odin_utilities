#+build js
package file_browser

// The file chooser of a web page. A program in a page cannot see a disk: to open a file the browser's own chooser (`<input type="file">`) is used and the bytes are copied into the memory of the
// program; to save, the bytes are handed to the browser as a download. The JavaScript side is `file_browser.js` (copy it next to index.html, load it with a <script> before odin.js, merge
// `fileBrowserJsImports` into the imports and call `setFileBrowserWasmMemory(exports.memory)`: `web_build` does it with `scripts`, `imports_js` and `start_js`, see the README).
// The procs below are polled once a frame, nothing calls back into the program.

foreign import file_browser_js "file_browser"

@(default_calling_convention = "contextless")
foreign file_browser_js {
    file_browser_pick_start :: proc(accept: string) ---
    file_browser_pick_poll :: proc() -> i32 ---                     // 0 pending, 1 ready, 2 cancelled, 3 failed
    file_browser_pick_name :: proc(buffer: []u8) -> int ---         // bytes written
    file_browser_pick_take :: proc(buffer: []u8) -> int ---         // bytes written, -1 when the file does not fit
    file_browser_download :: proc(name: string, data: []u8) ---
}

IoWeb :: proc() -> Io {
    return {
        list = webList,
        read = webRead,
        write = webWrite,
        stat = webStat,
        start = webStart,
        pick_start = webPickStart,
        pick_poll = webPickPoll,
        pick_name = webPickName,
        pick_take = webPickTake,
        download = webDownload,
    }
}

@(private)
webList :: proc(user: rawptr, dir: string, out: ^Listing) -> Error {
    return .UNSUPPORTED
}

@(private)
webRead :: proc(user: rawptr, path: string, buffer: []u8) -> (count: int, err: Error) {
    return 0, .UNSUPPORTED
}

@(private)
webWrite :: proc(user: rawptr, path: string, data: []u8) -> Error {
    return .UNSUPPORTED
}

@(private)
webStat :: proc(user: rawptr, path: string) -> (exists: bool, directory: bool) {
    return false, false
}

@(private)
webStart :: proc(user: rawptr, buffer: []u8) -> string {
    return ""
}

@(private)
webPickStart :: proc(user: rawptr, accept: string) {
    file_browser_pick_start(accept)
}

@(private)
webPickPoll :: proc(user: rawptr) -> PickStatus {
    switch file_browser_pick_poll() {
    case 1: return .READY
    case 2: return .CANCELLED
    case 3: return .FAILED
    }
    return .PENDING
}

@(private)
webPickName :: proc(user: rawptr, buffer: []u8) -> string {
    return string(buffer[:file_browser_pick_name(buffer)])
}

@(private)
webPickTake :: proc(user: rawptr, buffer: []u8) -> (count: int, err: Error) {
    taken: int = file_browser_pick_take(buffer)
    if taken < 0 { return 0, .TOO_BIG }
    return taken, .NONE
}

@(private)
webDownload :: proc(user: rawptr, name: string, data: []u8) -> Error {
    file_browser_download(name, data)
    return .NONE
}
