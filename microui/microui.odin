// Framework agnostic helpers for vendor:microui, shared by raylib and karl2d glue.
// Designed to not allocate, all buffers are inside of structs owned by the user.
package microui_utils

import mu "vendor:microui"

LOG_BUFFER_SIZE :: 1 << 16

// Text log that can be shown inside of a microui panel
MuiLog :: struct {
    buffer: [LOG_BUFFER_SIZE]byte,
    length: int,
    updated: bool,
}

// Atlas pixel count, size of the buffer for AtlasToRGBA
ATLAS_PIXELS :: mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT

// Append a line. When the buffer is full the log starts over
LogWrite :: proc(log: ^MuiLog, str: string) {
    if log.length + len(str) + 1 > len(log.buffer) {
        log.length = 0
    }
    log.length += copy(log.buffer[log.length:], str)
    log.length += copy(log.buffer[log.length:], "\n")
    log.updated = true
}

LogRead :: proc(log: ^MuiLog) -> string {
    return string(log.buffer[:log.length])
}

// True once after the log was changed, use it to scroll the log panel to the end
LogIsUpdated :: proc(log: ^MuiLog) -> bool {
    if log.updated {
        log.updated = false
        return true
    }
    return false
}

LogReset :: proc(log: ^MuiLog) {
    log.updated = true
    log.length = 0
}

// Convert microui default atlas (alpha only) to white RGBA pixels
AtlasToRGBA :: proc(buffer: ^[ATLAS_PIXELS][4]u8) {
    for alpha, i in mu.default_atlas_alpha {
        buffer[i] = {0xff, 0xff, 0xff, alpha}
    }
}

// Slider for u8 values, for example colors
U8Slider :: proc(ctx: ^mu.Context, val: ^u8, lo: u8, hi: u8) -> (res: mu.Result_Set) {
    mu.push_id(ctx, uintptr(val))

    @(static) tmp: mu.Real
    tmp = mu.Real(val^)
    res = mu.slider(ctx, &tmp, mu.Real(lo), mu.Real(hi), 0, "%.0f", {.ALIGN_CENTER})
    val^ = u8(tmp)
    mu.pop_id(ctx)
    return
}
