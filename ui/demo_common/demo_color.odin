#+private file
package demo_common

// The color picker: a square for saturation and brightness, bars for the hue and the alpha, the channels as drag values. The script picks a color in the square,
// turns the hue and clears the alpha, and checks what the program's color became.

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_color: kit.Demo = {
    name = "color",
    init = init,
    draw = draw,
    script = script,
}

state: UiDemo
color: [3]f32
alpha: f32
hex: [9]u8

init :: proc(ctx: ^kit.Context) {
    ui_demo_init(&state)
    ctx.background = {24, 26, 32, 255}
    color = {0.9, 0.4, 0.1}
    alpha = 1
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state, ctx)
    c: ^ui.Context = &state.ctx
    if ui.UiWindow(c, "Color", {40, 40}, {ui.Fixed(270), {}}) {
        ui.UiColorPicker(c, "Tint", &color, &alpha, 150)
        ui.UiLabelf(c, "%s", ui.ColorToHex(color, alpha, hex[:], true))
    }
    ui_demo_end(&state)
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Capture("color_start"),
    // the square is at (50, 50), 150 wide: from the middle to near the top right corner (a saturated, bright color of the same hue)
    kit.MoveTo({125, 125}),
    kit.Wait(3),
    kit.Drag({125, 125}, {190, 60}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        expected: [3]f32 = ui.ColorHsvToRgb(0.0625, 140.0 / 150, 1 - 10.0 / 150)
        return abs(color.r - expected.r) < 0.02 && abs(color.g - expected.g) < 0.02 && abs(color.b - expected.b) < 0.02
    }, "the square set saturation and brightness and kept the hue"),
    // the hue bar at x 204..226: halfway down is the opposite hue
    kit.MoveTo({215, 60}),
    kit.Wait(3),
    kit.Drag({215, 60}, {215, 125}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return color.r < color.g && color.r < color.b }, "the hue bar turned the color towards cyan"),
    // the alpha bar at x 230..252: 120 pixels down is 0.2
    kit.MoveTo({241, 60}),
    kit.Wait(3),
    kit.Drag({241, 60}, {241, 170}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(alpha - 0.2) < 0.02 }, "the alpha bar sets the alpha"),
    kit.Capture("color_picked"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the frames had no problems"),
}
