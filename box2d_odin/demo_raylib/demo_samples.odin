#+private file
package demo_raylib

import b2_odin ".."
import glue "../raylib"
import _ "../samples"
import rl "vendor:raylib"

@(private="package")
state_samples:State = {
    enter,
    exit,
    update,
    draw,
}

host: b2_odin.SampleHost

keys_to_raylib: [b2_odin.Key]rl.KeyboardKey = #partial {
    .A = .A, .B = .B, .C = .C, .D = .D, .E = .E, .F = .F, .G = .G, .L = .L, .O = .O, .P = .P, .Q = .Q, .R = .R, .S = .S, .W = .W, .X = .X, .Z = .Z,
    .N0 = .ZERO, .N1 = .ONE, .N2 = .TWO, .N3 = .THREE, .N4 = .FOUR, .N5 = .FIVE, .N6 = .SIX, .N7 = .SEVEN, .N8 = .EIGHT, .N9 = .NINE,
    .SPACE = .SPACE, .COMMA = .COMMA, .PERIOD = .PERIOD, .TAB = .TAB, .ESCAPE = .ESCAPE,
    .LEFT = .LEFT, .RIGHT = .RIGHT, .UP = .UP, .DOWN = .DOWN,
    .LEFT_SHIFT = .LEFT_SHIFT, .RIGHT_SHIFT = .RIGHT_SHIFT, .LEFT_CONTROL = .LEFT_CONTROL, .RIGHT_CONTROL = .RIGHT_CONTROL,
}

// Raylib needs a null terminated string, keep it in a fixed buffer
text_buffer: [512]byte

ToCString :: proc(text: string) -> cstring {
    count: int = min(len(text), len(text_buffer) - 1)
    copy(text_buffer[:count], text)
    text_buffer[count] = 0
    return cstring(raw_data(text_buffer[:]))
}

ToColor :: proc(color: b2_odin.Color) -> rl.Color {
    return rl.Color(color)
}

backend: b2_odin.Backend = {
    rect = proc(rect: b2_odin.Rect, color: b2_odin.Color) {
        rl.DrawRectangleRec({rect.x, rect.y, rect.w, rect.h}, ToColor(color))
    },
    rect_outline = proc(rect: b2_odin.Rect, color: b2_odin.Color) {
        rl.DrawRectangleLinesEx({rect.x, rect.y, rect.w, rect.h}, 1, ToColor(color))
    },
    text = proc(text: string, position: b2_odin.Vec2, size: f32, color: b2_odin.Color) {
        rl.DrawText(ToCString(text), i32(position.x), i32(position.y), i32(size), ToColor(color))
    },
    text_width = proc(text: string, size: f32) -> f32 {
        return f32(rl.MeasureText(ToCString(text), i32(size)))
    },
}

enter :: proc() {
    b2_odin.HostInit(&host, backend, {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())})
    host.margin_top = 80
    glue.InitDebugDraw(&host.debug_draw, &host.ctx.camera)
    b2_odin.HostSelect(&host, host.selected)
}

exit :: proc() {
    b2_odin.HostShutdown(&host)
}

update :: proc() {}

UpdateInput :: proc(input: ^b2_odin.Input) {
    input.mouse = rl.GetMousePosition()
    input.mouse_delta = rl.GetMouseDelta()
    input.wheel = rl.GetMouseWheelMove()
    buttons: [b2_odin.MouseButton]rl.MouseButton = {.LEFT = .LEFT, .RIGHT = .RIGHT, .MIDDLE = .MIDDLE}
    for button in b2_odin.MouseButton {
        input.mouse_down[button] = rl.IsMouseButtonDown(buttons[button])
        input.mouse_pressed[button] = rl.IsMouseButtonPressed(buttons[button])
        input.mouse_released[button] = rl.IsMouseButtonReleased(buttons[button])
    }
    for key in b2_odin.Key {
        if key == .NONE { continue }
        input.key_down[key] = rl.IsKeyDown(keys_to_raylib[key])
        input.key_pressed[key] = rl.IsKeyPressed(keys_to_raylib[key])
    }
}

draw :: proc() {
    host.screen = {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
    UpdateInput(&host.input)
    b2_odin.HostFrame(&host, rl.GetFrameTime())
}
