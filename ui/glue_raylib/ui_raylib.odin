package ui_raylib

// Glue for raylib: the Painter of the default style drawn with raylib calls, and the input of a frame as ui.Input.
// A frame in a raylib program:
//
//     painter: ui_default.Painter
//     ui_raylib.PainterInit(&painter)
//     style := ui_default.StyleMake()
//     ui.UiInit(&ctx, &storage, ui_default.Measure, &painter)
//
//     rl.BeginDrawing()
//     ... the game ...
//     ui.UiBegin(&ctx, ui_raylib.InputPoll(), rl.GetFrameTime(), ui_raylib.ScreenSize(), &style)
//     ... widgets ...
//     ui.UiEnd(&ctx)
//     ui.UiRender(&ctx)           // draws into the batch of raylib that is open: same one as the game
//     rl.EndDrawing()

import rl "vendor:raylib"
import ui ".."
import ui_default "../default_style"

// Fills a painter with raylib draw procs. `font` is the font of the text (nil: the default font of raylib), it has to live as long as the painter.
PainterInit :: proc(painter: ^ui_default.Painter, font: ^rl.Font = nil) {
    painter^ = {
        user = font,
        theme = ui_default.THEME_DARK,
        fill_rect = proc(painter: ^ui_default.Painter, rect: ui.Rect, color: ui.Color) {
            rl.DrawRectangleRec(transmute(rl.Rectangle)(rect * ui_default.PainterScale(painter)), rl.Color(color))
        },
        fill_polygon = fillPolygon,
        fill_rounded = proc(painter: ^ui_default.Painter, rect: ui.Rect, radius: f32, color: ui.Color) {
            // raylib's roundness is the radius as a part of half of the shortest side: the same as the rounding of the ui
            scale: f32 = ui_default.PainterScale(painter)
            roundness: f32 = radius / (min(rect.z, rect.w) * 0.5)
            rl.DrawRectangleRounded(transmute(rl.Rectangle)(rect * scale), roundness, i32(ui.RoundedSegments(radius * scale) * 4), rl.Color(color))
        },
        draw_text = proc(painter: ^ui_default.Painter, text: string, position: ui.Vec2, size: f32, color: ui.Color) {
            buffer: [TEXT_BUFFER_SIZE]u8
            scale: f32 = ui_default.PainterScale(painter)
            rl.DrawTextEx(fontOf(painter), cstringInto(&buffer, text), position * scale, size * scale, size * scale / 10, rl.Color(color))
        },
        measure_text = proc(painter: ^ui_default.Painter, text: string, size: f32) -> ui.Vec2 {
            buffer: [TEXT_BUFFER_SIZE]u8
            scale: f32 = ui_default.PainterScale(painter)
            return rl.MeasureTextEx(fontOf(painter), cstringInto(&buffer, text), size * scale, size * scale / 10) / scale
        },
        clip = proc(painter: ^ui_default.Painter, rect: ui.Rect, begin: bool) {
            if begin {
                physical: ui.Rect = rect * ui_default.PainterScale(painter)
                rl.BeginScissorMode(i32(physical.x), i32(physical.y), i32(physical.z), i32(physical.w))
            } else {
                rl.EndScissorMode()
            }
        },
    }
}

// raylib wants a C string: the text is copied into a buffer of the caller (on its stack) with a zero at the end, cut when too long.
// No allocation, nothing left in the temp allocator for every text of every frame.
@(private)
TEXT_BUFFER_SIZE :: 512

@(private)
cstringInto :: proc(buffer: ^[TEXT_BUFFER_SIZE]u8, text: string) -> cstring {
    count: int = min(len(text), TEXT_BUFFER_SIZE - 1)
    copy(buffer[:count], text[:count])
    buffer[count] = 0
    return cstring(raw_data(buffer[:]))
}

@(private)
fontOf :: proc(painter: ^ui_default.Painter) -> rl.Font {
    if painter.user == nil { return rl.GetFontDefault() }
    return (cast(^rl.Font)painter.user)^
}

// raylib wants the corners of a fan counter clockwise, the points of the ui go clockwise
@(private)
fillPolygon :: proc(painter: ^ui_default.Painter, points: []ui.Vec2, color: ui.Color) {
    buffer: ui.RoundedBuffer
    count: int = min(len(points), len(buffer))
    scale: f32 = ui_default.PainterScale(painter)
    for i in 0 ..< count {
        buffer[i] = points[count - 1 - i] * scale
    }
    rl.DrawTriangleFan(raw_data(buffer[:]), i32(count), rl.Color(color))
}

// The size of the window in logical units: pass the UI scale of the painter (`ui_default.PainterScale(&painter)`)
ScreenSize :: proc(scale: f32 = 1) -> ui.Vec2 {
    return {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())} / scale
}

// What raylib knows of this frame, for ui.UiBegin. Call it once per frame (it drains the typed characters). The pointer is given in logical units: pass the UI scale of the painter.
InputPoll :: proc(scale: f32 = 1) -> ui.Input {
    input: ui.Input = {
        mouse_position = rl.GetMousePosition() / scale,
        mouse_down = rl.IsMouseButtonDown(.LEFT),
        mouse_pressed = rl.IsMouseButtonPressed(.LEFT),
        mouse_released = rl.IsMouseButtonReleased(.LEFT),
        wheel = rl.GetMouseWheelMoveV(),
    }
    // typed characters come as runes: written as UTF-8
    for int(input.text_count) < ui.INPUT_TEXT_CAPACITY - 4 {
        character: rune = rl.GetCharPressed()
        if character == 0 { break }
        encoded, width := encodeRune(character)
        for i in 0 ..< width {
            input.text[input.text_count] = encoded[i]
            input.text_count += 1
        }
    }
    // a key that is held repeats (the key repeat of raylib), like in a text editor
    keys: [ui.Key]rl.KeyboardKey = {
        .BACKSPACE = .BACKSPACE, .DELETE = .DELETE, .LEFT = .LEFT, .RIGHT = .RIGHT, .HOME = .HOME, .END = .END,
        .ENTER = .ENTER, .ESCAPE = .ESCAPE, .TAB = .TAB,
    }
    for key in ui.Key {
        if rl.IsKeyPressed(keys[key]) || rl.IsKeyPressedRepeat(keys[key]) { input.keys += {key} }
    }
    input.actions = actionsPoll()
    return input
}

// The default actions of Godot's input map from the keyboard and the first gamepad (d-pad, A accepts, B cancels, the shoulders are next / previous)
@(private)
actionsPoll :: proc() -> ui.Actions {
    actions: ui.Actions
    again :: proc(key: rl.KeyboardKey) -> bool { return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key) }
    if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) || rl.IsKeyPressed(.SPACE) { actions += {.ACCEPT} }
    if rl.IsKeyPressed(.SPACE) { actions += {.SELECT} }
    if rl.IsKeyPressed(.ESCAPE) { actions += {.CANCEL} }
    if rl.IsKeyPressed(.TAB) {
        actions += {.FOCUS_PREV} if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) else {.FOCUS_NEXT}
    }
    if again(.UP) { actions += {.UP} }
    if again(.DOWN) { actions += {.DOWN} }
    if again(.LEFT) { actions += {.LEFT} }
    if again(.RIGHT) { actions += {.RIGHT} }
    if again(.PAGE_UP) { actions += {.PAGE_UP} }
    if again(.PAGE_DOWN) { actions += {.PAGE_DOWN} }
    if rl.IsKeyPressed(.HOME) { actions += {.HOME} }
    if rl.IsKeyPressed(.END) { actions += {.END} }
    if rl.IsGamepadAvailable(0) {
        if rl.IsGamepadButtonPressed(0, .LEFT_FACE_UP) { actions += {.UP} }
        if rl.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) { actions += {.DOWN} }
        if rl.IsGamepadButtonPressed(0, .LEFT_FACE_LEFT) { actions += {.LEFT} }
        if rl.IsGamepadButtonPressed(0, .LEFT_FACE_RIGHT) { actions += {.RIGHT} }
        if rl.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) { actions += {.ACCEPT, .SELECT} }
        if rl.IsGamepadButtonPressed(0, .RIGHT_FACE_RIGHT) { actions += {.CANCEL} }
        if rl.IsGamepadButtonPressed(0, .LEFT_TRIGGER_1) { actions += {.FOCUS_PREV} }
        if rl.IsGamepadButtonPressed(0, .RIGHT_TRIGGER_1) { actions += {.FOCUS_NEXT} }
    }
    return actions
}

@(private)
encodeRune :: proc(character: rune) -> (bytes: [4]u8, width: int) {
    value: u32 = u32(character)
    switch {
    case value < 0x80:
        return {u8(value), 0, 0, 0}, 1
    case value < 0x800:
        return {u8(0xC0 | value >> 6), u8(0x80 | value & 0x3F), 0, 0}, 2
    case value < 0x10000:
        return {u8(0xE0 | value >> 12), u8(0x80 | (value >> 6) & 0x3F), u8(0x80 | value & 0x3F), 0}, 3
    }
    return {u8(0xF0 | value >> 18), u8(0x80 | (value >> 12) & 0x3F), u8(0x80 | (value >> 6) & 0x3F), u8(0x80 | value & 0x3F)}, 4
}

// Sets the mouse cursor to what the ui says the pointer is over (call after UiEnd)
ApplyCursor :: proc(ctx: ^ui.Context) {
    cursor: rl.MouseCursor
    switch ui.UiCursor(ctx) {
    case .ARROW: cursor = .DEFAULT
    case .TEXT: cursor = .IBEAM
    case .HAND: cursor = .POINTING_HAND
    case .RESIZE_HORIZONTAL: cursor = .RESIZE_EW
    case .RESIZE_VERTICAL: cursor = .RESIZE_NS
    case .RESIZE_DIAGONAL_NWSE: cursor = .RESIZE_NWSE
    case .RESIZE_DIAGONAL_NESW: cursor = .RESIZE_NESW
    case .NOT_ALLOWED: cursor = .NOT_ALLOWED
    }
    rl.SetMouseCursor(cursor)
}
