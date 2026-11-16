#+build js
package demo_kit

// The browser has no disk for golden images: Capture steps are skipped (see capture.odin for the desktop version), the names are the same so
// a demo and the runner build for js_wasm32 too (the options page of browser_extension is a demo).

DEMO_CAPTURE :: false
DEMO_CAPTURE_UPDATE :: false

CaptureResult :: enum u8 {
    SKIPPED,
    WRITTEN,
    MATCH,
    DIFFERENT,
    SIZE_CHANGED,
    ERROR,
}

CaptureFrame :: proc(ctx: ^Context, allocator := context.allocator) -> (rgba: []u8, width: int, height: int, ok: bool) {
    return nil, 0, 0, false
}

CaptureCompare :: proc(ctx: ^Context, script_file: string, name: string) -> (result: CaptureResult, message: string) {
    return .SKIPPED, ""
}
