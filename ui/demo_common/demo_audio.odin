#+private file
package demo_common

// The controls of a mixing desk: three knobs (drag up and down, wheel, double click for the default), two faders and two level meters that show what the
// faders let through, with a peak mark that falls slowly. The script turns a knob, sets a fader and resets a knob with a double click.

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_audio: kit.Demo = {
    name = "audio",
    init = init,
    draw = draw,
    script = script,
}

State :: struct {
    app: UiDemo,
    gain: f32,
    pan: f32,
    cutoff: f32,
    left: f32,
    right: f32,
    peak_left: f32,
    peak_right: f32,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {gain = 5, pan = 0, cutoff = 1000, left = 0.8, right = 0.5}
    ui_demo_init(&state.app)
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    // the peak holds the highest level and falls a little every frame
    levels: [2]f32 = {state.left * state.gain / 10, state.right * state.gain / 10}
    state.peak_left = max(levels[0], state.peak_left - 0.002)
    state.peak_right = max(levels[1], state.peak_right - 0.002)
    if ui.UiPanel(c, "desk", {size = {ui.Fixed(420), ui.Fixed(190)}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingAll(10), gap = 10}) {
        ui.UiKnob(c, "Gain", &state.gain, 0, 10, 5, {ui.Fixed(56), ui.Fixed(56)}, "%.1f")
        ui.UiKnob(c, "Pan", &state.pan, -1, 1, 0, {ui.Fixed(56), ui.Fixed(56)}, "%.2f")
        ui.UiKnob(c, "Cutoff", &state.cutoff, 20, 20000, 1000, {ui.Fixed(56), ui.Fixed(56)}, "%.0f")
        ui.UiFader(c, "Left", &state.left, 0, 1, 0.8, {ui.Fixed(30), ui.Fixed(150)})
        ui.UiFader(c, "Right", &state.right, 0, 1, 0.8, {ui.Fixed(30), ui.Fixed(150)})
        ui.UiMeter(c, "Meter left", levels[0], state.peak_left, 0, 1, {ui.Fixed(14), ui.Fixed(150)})
        ui.UiMeter(c, "Meter right", levels[1], state.peak_right, 0, 1, {ui.Fixed(14), ui.Fixed(150)})
    }
    ui_demo_end(&state.app)
}

// The window is at (0, 0), padding 10, gap 10: the knobs are at x 10, 76, 142 (56 wide), y 10; the faders at x 208 and 248 (30 wide), y 10 .. 160
script: []kit.Step = {
    kit.Wait(4),
    kit.MoveTo({38, 38}),
    kit.Wait(3),
    kit.Drag({38, 38}, {38, 8}, 10),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return abs(state.gain - (5 + 10 * 30.0 / ui.KNOB_DRAG_PIXELS)) < 0.05
    }, "dragging a knob up turned it up by the distance"),
    kit.MoveTo({223, 100}),
    kit.Wait(3),
    kit.Click({223, 60}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return abs(state.left - (1 - (60.0 - 10 - 10.5) / (150 - 21))) < 0.02
    }, "a press on the fader set the value where the pointer is"),
    kit.Capture("audio"),
    kit.MoveTo({38, 38}),
    kit.Wait(3),
    kit.Click({38, 38}),
    kit.Click({38, 38}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.gain == 5 }, "a double click set the default"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
