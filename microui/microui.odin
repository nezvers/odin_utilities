// Framework agnostic helpers for vendor:microui, shared by raylib and karl2d glue.
// Designed to not allocate, all buffers are inside of structs owned by the user.
package microui_utils

import mu "vendor:microui"
import "core:testing"

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

// --- Tests ---

@(test)
test_log_write_read_and_updated_flag :: proc(t: ^testing.T) {
    log := new(MuiLog)
    defer free(log)

    testing.expect(t, !LogIsUpdated(log))
    LogWrite(log, "first")
    LogWrite(log, "second")
    testing.expect_value(t, LogRead(log), "first\nsecond\n")
    testing.expect(t, LogIsUpdated(log), "true once after a change")
    testing.expect(t, !LogIsUpdated(log), "and then false until the next change")

    LogReset(log)
    testing.expect_value(t, LogRead(log), "")
    testing.expect(t, LogIsUpdated(log), "a reset counts as a change")
}

@(test)
test_log_starts_over_when_full :: proc(t: ^testing.T) {
    log := new(MuiLog)
    defer free(log)

    line: [1000]byte
    for &b in line { b = 'x' }
    for _ in 0 ..< LOG_BUFFER_SIZE / 1001 { LogWrite(log, string(line[:])) }
    full: int = log.length
    testing.expect(t, full > LOG_BUFFER_SIZE - 1001 && full + 601 > LOG_BUFFER_SIZE)

    LogWrite(log, string(line[:600]))                                                      // does not fit in the rest: the log wraps instead of overflowing
    testing.expect_value(t, log.length, 601)                                               // only the new line is left
}

@(test)
test_atlas_to_rgba_is_white_with_the_atlas_alpha :: proc(t: ^testing.T) {
    pixels := new([ATLAS_PIXELS][4]u8)
    defer free(pixels)
    AtlasToRGBA(pixels)

    for alpha, i in mu.default_atlas_alpha {
        if pixels[i] != {0xff, 0xff, 0xff, alpha} {
            testing.expectf(t, false, "pixel %d is %v, atlas alpha is %d", i, pixels[i], alpha)
            return
        }
    }
    testing.expect_value(t, len(pixels), mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT)
}

@(private="file")
test_text_width :: proc(font: mu.Font, text: string) -> i32 { return i32(len(text)) * 8 }
@(private="file")
test_text_height :: proc(font: mu.Font) -> i32 { return 16 }

@(test)
test_u8_slider_follows_the_pointer :: proc(t: ^testing.T) {
    ctx := new(mu.Context)
    defer free(ctx)
    mu.init(ctx)
    ctx.text_width = test_text_width
    ctx.text_height = test_text_height

    value: u8 = 0
    frame :: proc(ctx: ^mu.Context, value: ^u8, mouse: [2]i32, down: bool, was_down: bool) {
        mu.input_mouse_move(ctx, mouse.x, mouse.y)
        if down && !was_down { mu.input_mouse_down(ctx, mouse.x, mouse.y, .LEFT) }
        if !down && was_down { mu.input_mouse_up(ctx, mouse.x, mouse.y, .LEFT) }
        mu.begin(ctx)
        if mu.begin_window(ctx, "test", {0, 0, 300, 200}, {.NO_TITLE, .NO_RESIZE, .NO_CLOSE}) {
            mu.layout_row(ctx, {-1}, 0)
            U8Slider(ctx, value, 0, 200)
            mu.end_window(ctx)
        }
        mu.end(ctx)
    }

    // The slider is the first row of the window, it spans most of the width
    middle: [2]i32 = {150, 12}
    frame(ctx, &value, middle, false, false)                                               // microui needs two frames of hovering before it accepts a press
    frame(ctx, &value, middle, false, false)
    frame(ctx, &value, middle, true, false)                                                // press
    testing.expect(t, value > 70 && value < 130, "pressed in the middle of the slider")

    frame(ctx, &value, {1000, 12}, true, true)                                             // dragged far to the right while held
    testing.expect_value(t, value, u8(200))                                                // limited to the upper end
    frame(ctx, &value, {-1000, 12}, true, true)
    testing.expect_value(t, value, u8(0))

    frame(ctx, &value, middle, false, true)                                                // released
    frame(ctx, &value, {200, 12}, false, false)
    testing.expect_value(t, value, u8(0))                                                    // no change without the button down
}
