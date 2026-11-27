#+private file
package demo_common

// The Box2D samples (box2d_odin/samples, ports of box2d/samples) in the sample browser of the library: its own small ui, camera and
// mouse joint. The library draws through a Backend and Box2D debug draw, both are made over the demo kit here.

import b2 "vendor:box2d"
import b2_odin ".."
import b2_kit "../kit"
import _ "../samples"
import kit "../../demo_kit"

@(private="package")
demo_samples: kit.Demo = {
    name = "samples",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

host: b2_odin.SampleHost
ctx_now: ^kit.Context       // the Backend procs have no context of their own

keys: [b2_odin.Key]kit.Key = #partial {
    .A = .A, .B = .B, .C = .C, .D = .D, .E = .E, .F = .F, .G = .G, .L = .L, .O = .O, .P = .P, .Q = .Q, .R = .R, .S = .S, .W = .W, .X = .X, .Z = .Z,
    .N0 = .N0, .N1 = .N1, .N2 = .N2, .N3 = .N3, .N4 = .N4, .N5 = .N5, .N6 = .N6, .N7 = .N7, .N8 = .N8, .N9 = .N9,
    .SPACE = .SPACE, .COMMA = .COMMA, .PERIOD = .PERIOD, .TAB = .TAB, .ESCAPE = .ESCAPE,
    .LEFT = .LEFT, .RIGHT = .RIGHT, .UP = .UP, .DOWN = .DOWN,
    .LEFT_SHIFT = .LEFT_SHIFT, .RIGHT_SHIFT = .RIGHT_SHIFT, .LEFT_CONTROL = .LEFT_CTRL, .RIGHT_CONTROL = .RIGHT_CTRL,
}

backend: b2_odin.Backend = {
    rect = proc(rect: b2_odin.Rect, color: b2_odin.Color) {
        kit.DrawRect(ctx_now, {rect.x, rect.y, rect.w, rect.h}, kit.Color(color))
    },
    rect_outline = proc(rect: b2_odin.Rect, color: b2_odin.Color) {
        kit.DrawRectOutline(ctx_now, {rect.x, rect.y, rect.w, rect.h}, 1, kit.Color(color))
    },
    text = proc(text: string, position: b2_odin.Vec2, size: f32, color: b2_odin.Color) {
        kit.DrawText(ctx_now, text, position, size, kit.Color(color))
    },
    text_width = proc(text: string, size: f32) -> f32 {
        return kit.MeasureText(ctx_now, text, size).x
    },
}

init :: proc(ctx: ^kit.Context) {
    ctx_now = ctx
    b2_odin.HostInit(&host, backend, ctx.screen)
    host.margin_top = 80
    b2_kit.InitDebugDraw(&host.debug_draw, &host.ctx.camera)
    b2_odin.HostSelect(&host, host.selected)
}

finit :: proc(ctx: ^kit.Context) {
    b2_odin.HostShutdown(&host)
}

update :: proc(ctx: ^kit.Context) {}

// the input of the frame for the library, from the kit
read_input :: proc(input: ^b2_odin.Input, from: ^kit.Input) {
    input.mouse = from.mouse_position
    input.mouse_delta = from.mouse_delta
    input.wheel = from.mouse_wheel
    buttons: [b2_odin.MouseButton]kit.MouseButton = {.LEFT = .LEFT, .RIGHT = .RIGHT, .MIDDLE = .MIDDLE}
    for button in b2_odin.MouseButton {
        input.mouse_down[button] = kit.MouseDown(from, buttons[button])
        input.mouse_pressed[button] = kit.MousePressed(from, buttons[button])
        input.mouse_released[button] = kit.MouseReleased(from, buttons[button])
    }
    for key in b2_odin.Key {
        if key == .NONE { continue }
        input.key_down[key] = kit.KeyDown(from, keys[key])
        input.key_pressed[key] = kit.KeyPressed(from, keys[key])
    }
}

draw :: proc(ctx: ^kit.Context) {
    ctx_now = ctx
    b2_kit.Begin(ctx)
    host.screen = ctx.screen
    read_input(&host.input, &ctx.input)
    b2_odin.HostFrame(&host, ctx.delta_time)
}

script: []kit.Step = {
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return b2.World_IsValid(host.ctx.world) && b2_odin.SampleCount() > 1 }, "a sample world is running and the library has samples"),
    kit.Wait(60),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return host.ctx.step_count > 30 }, "the world is stepped every frame"),
    kit.Tap(.RIGHT),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return host.selected == 1 && b2.World_IsValid(host.ctx.world) }, "the right arrow selects the next sample and makes its world"),
    kit.Tap(.LEFT),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return host.selected == 0 }, "the left arrow goes back"),
    kit.Tap(.P),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return host.ctx.pause }, "P pauses"),
    kit.Tap(.P),
    kit.Wait(1),
    kit.Tap(.R),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return host.ctx.step_count < 10 }, "R restarts the sample: the step counter starts over"),
    kit.Wait(2),
    kit.Capture("box2d_odin_samples_end"),
    kit.Wait(1),
    kit.Tap(.RIGHT),
    kit.Wait(90),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return host.selected == 1 && host.ctx.step_count > 60 }, "sample 1 runs for a while"),
    kit.Capture("box2d_odin_sample_1"),
    kit.Wait(1),
    kit.Tap(.RIGHT),
    kit.Wait(90),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return host.selected == 2 && host.ctx.step_count > 60 }, "sample 2 runs for a while"),
    kit.Capture("box2d_odin_sample_2"),
    kit.Wait(1),
    kit.Tap(.RIGHT),
    kit.Wait(90),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return host.selected == 3 && host.ctx.step_count > 60 }, "sample 3 runs for a while"),
    kit.Capture("box2d_odin_sample_3"),
    kit.Wait(1),
    kit.Tap(.RIGHT),
    kit.Wait(90),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return host.selected == 4 && host.ctx.step_count > 60 }, "sample 4 runs for a while"),
    kit.Capture("box2d_odin_sample_4"),
    kit.Wait(1),
}
