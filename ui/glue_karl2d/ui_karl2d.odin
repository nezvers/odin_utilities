package ui_karl2d

// Glue for Karl2D: the Painter of the default style drawn with Karl2D calls, and the input of a frame as ui.Input.
// A frame in a Karl2D program:
//
//     painter: ui_default.Painter
//     ui_karl2d.PainterInit(&painter)
//     style := ui_default.StyleMake()
//     ui.UiInit(&ctx, &storage, ui_default.Measure, &painter)
//
//     for karl2d.update() {
//         karl2d.clear(...)
//         ... the game ...
//         ui.UiBegin(&ctx, ui_karl2d.InputPoll(), karl2d.get_frame_time(), ui_karl2d.ScreenSize(), &style)
//         ... widgets ...
//         ui.UiEnd(&ctx)
//         ui.UiRender(&ctx)       // the style procs draw into the batch of Karl2D that is open: the one of the game
//         karl2d.present()
//     }
//
// Karl2D has no rounded rectangle: the painter does not set `fill_rounded`, so the default style fills the polygon of ui.RoundedPoints.

import "../../karl2d"
import ui ".."
import ui_default "../default_style"

// Fills a painter with Karl2D draw procs. `font` is the font of the text (the default font of Karl2D when left as it is).
PainterInit :: proc(painter: ^ui_default.Painter, font: ^karl2d.Font = nil) {
    painter^ = {
        user = font,
        theme = ui_default.THEME_DARK,
        fill_rect = proc(painter: ^ui_default.Painter, rect: ui.Rect, color: ui.Color) {
            karl2d.draw_rect(transmute(karl2d.Rect)(rect * ui_default.PainterScale(painter)), color)
        },
        fill_polygon = proc(painter: ^ui_default.Painter, points: []ui.Vec2, color: ui.Color) {
            // the polygon is convex: a fan from its first point
            scale: f32 = ui_default.PainterScale(painter)
            for i in 1 ..< len(points) - 1 {
                karl2d.draw_triangle({points[0] * scale, points[i] * scale, points[i + 1] * scale}, color)
            }
        },
        draw_text = proc(painter: ^ui_default.Painter, text: string, position: ui.Vec2, size: f32, color: ui.Color) {
            scale: f32 = ui_default.PainterScale(painter)
            karl2d.draw_text(text, position * scale, size * scale, color, fontOf(painter))
        },
        measure_text = proc(painter: ^ui_default.Painter, text: string, size: f32) -> ui.Vec2 {
            scale: f32 = ui_default.PainterScale(painter)
            return karl2d.measure_text(text, size * scale, fontOf(painter)) / scale
        },
        clip = proc(painter: ^ui_default.Painter, rect: ui.Rect, begin: bool) {
            if begin {
                karl2d.set_scissor_rect(transmute(karl2d.Rect)(rect * ui_default.PainterScale(painter)))
            } else {
                karl2d.set_scissor_rect(nil)
            }
        },
    }
}

@(private)
fontOf :: proc(painter: ^ui_default.Painter) -> karl2d.Font {
    if painter.user == nil { return karl2d.FONT_DEFAULT }
    return (cast(^karl2d.Font)painter.user)^
}

// The size of the window in logical units: pass the UI scale of the painter (`ui_default.PainterScale(&painter)`)
ScreenSize :: proc(scale: f32 = 1) -> ui.Vec2 {
    return {f32(karl2d.get_screen_width()), f32(karl2d.get_screen_height())} / scale
}

// What Karl2D knows of this frame (call it after karl2d.update), for ui.UiBegin. The pointer is given in logical units: pass the UI scale of the painter.
InputPoll :: proc(scale: f32 = 1) -> ui.Input {
    input: ui.Input = {
        mouse_position = karl2d.get_mouse_position() / scale,
        mouse_down = karl2d.mouse_button_is_held(.Left),
        mouse_pressed = karl2d.mouse_button_went_down(.Left),
        mouse_released = karl2d.mouse_button_went_up(.Left),
    }
    for event in karl2d.get_events() {
        #partial switch e in event {
        case karl2d.Event_Mouse_Wheel:
            input.wheel.y += e.delta
        case karl2d.Event_Typed_Rune:
            // printable characters only: a control character (backspace, enter) arrives as a key
            if e.typed >= 32 && e.typed != 127 {
                encoded, width := encodeRune(e.typed)
                if int(input.text_count) + width <= ui.INPUT_TEXT_CAPACITY {
                    for i in 0 ..< width {
                        input.text[input.text_count] = encoded[i]
                        input.text_count += 1
                    }
                }
            }
        }
    }
    keys: [ui.Key]karl2d.Keyboard_Key = {
        .BACKSPACE = .Backspace, .DELETE = .Delete, .LEFT = .Left, .RIGHT = .Right, .HOME = .Home, .END = .End,
        .ENTER = .Enter, .ESCAPE = .Escape, .TAB = .Tab,
    }
    for key in ui.Key {
        if karl2d.key_went_down(keys[key], allow_repeat = true) { input.keys += {key} }
    }
    input.actions = actionsPoll()
    return input
}

// The default actions of Godot's input map from the keyboard and the first gamepad (d-pad, A accepts, B cancels, the shoulders are next / previous)
@(private)
actionsPoll :: proc() -> ui.Actions {
    actions: ui.Actions
    if karl2d.key_went_down(.Enter) || karl2d.key_went_down(.Space) { actions += {.ACCEPT} }
    if karl2d.key_went_down(.Space) { actions += {.SELECT} }
    if karl2d.key_went_down(.Escape) { actions += {.CANCEL} }
    if karl2d.key_went_down(.Tab) {
        actions += {.FOCUS_PREV} if karl2d.key_is_held(.Left_Shift) || karl2d.key_is_held(.Right_Shift) else {.FOCUS_NEXT}
    }
    if karl2d.key_went_down(.Up, allow_repeat = true) { actions += {.UP} }
    if karl2d.key_went_down(.Down, allow_repeat = true) { actions += {.DOWN} }
    if karl2d.key_went_down(.Left, allow_repeat = true) { actions += {.LEFT} }
    if karl2d.key_went_down(.Right, allow_repeat = true) { actions += {.RIGHT} }
    if karl2d.key_went_down(.Page_Up, allow_repeat = true) { actions += {.PAGE_UP} }
    if karl2d.key_went_down(.Page_Down, allow_repeat = true) { actions += {.PAGE_DOWN} }
    if karl2d.key_went_down(.Home) { actions += {.HOME} }
    if karl2d.key_went_down(.End) { actions += {.END} }
    if karl2d.is_gamepad_active(0) {
        if karl2d.gamepad_button_went_down(0, .Left_Face_Up) { actions += {.UP} }
        if karl2d.gamepad_button_went_down(0, .Left_Face_Down) { actions += {.DOWN} }
        if karl2d.gamepad_button_went_down(0, .Left_Face_Left) { actions += {.LEFT} }
        if karl2d.gamepad_button_went_down(0, .Left_Face_Right) { actions += {.RIGHT} }
        if karl2d.gamepad_button_went_down(0, .Right_Face_Down) { actions += {.ACCEPT, .SELECT} }
        if karl2d.gamepad_button_went_down(0, .Right_Face_Right) { actions += {.CANCEL} }
        if karl2d.gamepad_button_went_down(0, .Left_Shoulder) { actions += {.FOCUS_PREV} }
        if karl2d.gamepad_button_went_down(0, .Right_Shoulder) { actions += {.FOCUS_NEXT} }
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
    cursor: karl2d.Standard_Cursor
    switch ui.UiCursor(ctx) {
    case .ARROW: cursor = .Default
    case .TEXT: cursor = .Text
    case .HAND: cursor = .Hand
    case .RESIZE_HORIZONTAL: cursor = .Resize_EW
    case .RESIZE_VERTICAL: cursor = .Resize_NS
    case .RESIZE_DIAGONAL_NWSE: cursor = .Resize_NWSE
    case .RESIZE_DIAGONAL_NESW: cursor = .Resize_NESW
    case .NOT_ALLOWED: cursor = .Not_Allowed
    }
    karl2d.set_cursor(cursor)
}
