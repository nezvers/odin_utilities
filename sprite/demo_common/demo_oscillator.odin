#+private file
package demo_common

// A pixel moved by two oscillators: a cosine for x and a sine for y. The sliders change the amplitude, the phase, the offset and the speed.

import "core:fmt"
import sp ".."
import kit "../../demo_kit"

@(private="package")
demo_oscillator: kit.Demo = {
    name = "oscillator",
    init = init,
    draw = draw,
    script = script,
}

ZOOM :: 8

osc: sp.Oscillator2D
offset: kit.Vec2        // the last value of the oscillator

init :: proc(ctx: ^kit.Context) {
    osc = {}
    osc[0] = {time_scale = 1, amplitude = 8}
    osc[1] = {amplitude = 8}
    offset = {}
}

draw :: proc(ctx: ^kit.Context) {
    kit.CameraBegin(ctx, {zoom = ZOOM})
    offset = sp.OscilateProperty2D(&osc, ctx.delta_time)
    kit.DrawRect(ctx, {32 + offset.x, 32 + offset.y, 1, 1}, kit.ORANGE)
    kit.CameraEnd(ctx)

    x: f32 = 800
    kit.Slider(ctx, {x, 20, 300, 22}, fmt.tprintf("time scale = %.1f", osc[0].time_scale), &osc[0].time_scale, 0, 6)
    kit.Slider(ctx, {x, 50, 300, 22}, fmt.tprintf("x amplitude = %.1f", osc[0].amplitude), &osc[0].amplitude, -16, 16)
    kit.Slider(ctx, {x, 80, 300, 22}, "x phase", &osc[0].phase, -0.5, 0.5)
    kit.Slider(ctx, {x, 110, 300, 22}, "x offset", &osc[0].offset, -16, 16)
    kit.Slider(ctx, {x, 160, 300, 22}, fmt.tprintf("y amplitude = %.1f", osc[1].amplitude), &osc[1].amplitude, -16, 16)
    kit.Slider(ctx, {x, 190, 300, 22}, "y phase", &osc[1].phase, -0.5, 0.5)
    kit.Slider(ctx, {x, 220, 300, 22}, "y offset", &osc[1].offset, -16, 16)
    kit.DrawText(ctx, "2D oscillator: x is a cosine, y a sine, both use the time of the first", {10, 10}, 16, kit.DARK_GRAY)
}

script: []kit.Step = {
    kit.Wait(30),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(offset.x) <= 8.001 && abs(offset.y) <= 8.001 }, "the pixel stays inside of the amplitude"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return osc[0].t > 0 }, "time runs with the time scale"),
    // time scale to 0 with the slider: the pixel stops
    kit.Drag({800 + 250, 31}, {600, 31}, 5),      // from inside of the bar to past its left end
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return osc[0].time_scale < 0.2 }, "the slider sets the time scale"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        before: f32 = osc[0].t
        return before == osc[0].t
    }, "(a stopped oscillator keeps its time)"),
    kit.Wait(2),
    kit.Capture("sprite_oscillator_end"),
    kit.Wait(1),
}
