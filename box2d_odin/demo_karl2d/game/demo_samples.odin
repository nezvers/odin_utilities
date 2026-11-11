#+private file
package game

import b2_odin "../.."
import glue "../../karl2d"
import _ "../../samples"
import "../../../karl2d"

@(private="package")
samples_state: GameState = {
    init,
    finit,
    process,
    draw,
}

host: b2_odin.SampleHost

keys_to_karl2d: [b2_odin.Key]karl2d.Keyboard_Key = #partial {
    .A = .A, .B = .B, .C = .C, .D = .D, .E = .E, .F = .F, .G = .G, .L = .L, .O = .O, .P = .P, .Q = .Q, .R = .R, .S = .S, .W = .W, .X = .X, .Z = .Z,
    .N0 = .N0, .N1 = .N1, .N2 = .N2, .N3 = .N3, .N4 = .N4, .N5 = .N5, .N6 = .N6, .N7 = .N7, .N8 = .N8, .N9 = .N9,
    .SPACE = .Space, .COMMA = .Comma, .PERIOD = .Period, .TAB = .Tab, .ESCAPE = .Escape,
    .LEFT = .Left, .RIGHT = .Right, .UP = .Up, .DOWN = .Down,
    .LEFT_SHIFT = .Left_Shift, .RIGHT_SHIFT = .Right_Shift, .LEFT_CONTROL = .Left_Control, .RIGHT_CONTROL = .Right_Control,
}

ToColor :: proc(color: b2_odin.Color) -> karl2d.Color {
    return karl2d.Color(color)
}

backend: b2_odin.Backend = {
    rect = proc(rect: b2_odin.Rect, color: b2_odin.Color) {
        karl2d.draw_rect(karl2d.Rect{rect.x, rect.y, rect.w, rect.h}, ToColor(color))
    },
    rect_outline = proc(rect: b2_odin.Rect, color: b2_odin.Color) {
        karl2d.draw_rect_outline(karl2d.Rect{rect.x, rect.y, rect.w, rect.h}, 1, ToColor(color))
    },
    text = proc(text: string, position: b2_odin.Vec2, size: f32, color: b2_odin.Color) {
        karl2d.draw_text(text, position, size, ToColor(color))
    },
    text_width = proc(text: string, size: f32) -> f32 {
        return karl2d.measure_text(text, size).x
    },
}

init :: proc() {
    background_color = karl2d.Color{25, 25, 30, 255}
    b2_odin.HostInit(&host, backend, karl2d.get_screen_size())
    host.margin_top = 80
    glue.InitDebugDraw(&host.debug_draw, &host.ctx.camera)
    b2_odin.HostSelect(&host, host.selected)
}

finit :: proc() {
    b2_odin.HostShutdown(&host)
}

process :: proc() {}

UpdateInput :: proc(input: ^b2_odin.Input) {
    input.mouse = karl2d.get_mouse_position()
    input.mouse_delta = karl2d.get_mouse_delta()
    input.wheel = karl2d.get_mouse_wheel_delta()
    buttons: [b2_odin.MouseButton]karl2d.Mouse_Button = {.LEFT = .Left, .RIGHT = .Right, .MIDDLE = .Middle}
    for button in b2_odin.MouseButton {
        input.mouse_down[button] = karl2d.mouse_button_is_held(buttons[button])
        input.mouse_pressed[button] = karl2d.mouse_button_went_down(buttons[button])
        input.mouse_released[button] = karl2d.mouse_button_went_up(buttons[button])
    }
    for key in b2_odin.Key {
        if key == .NONE { continue }
        input.key_down[key] = karl2d.key_is_held(keys_to_karl2d[key])
        input.key_pressed[key] = karl2d.key_went_down(keys_to_karl2d[key])
    }
}

draw :: proc() {
    host.screen = karl2d.get_screen_size()
    UpdateInput(&host.input)
    b2_odin.HostFrame(&host, karl2d.get_frame_time())
}
