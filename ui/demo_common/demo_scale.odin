#+private file
package demo_common

// The UI scale: the layout and the style work in logical units, the painter multiplies what it draws and the pointer is divided, so the same program
// runs at any scale (a high DPI screen, a setting for people who want it bigger). The toggle doubles the scale; the script clicks the button at the same
// logical place before and after (the pointer is in pixels, so the second click is at twice the coordinates), and a picture shows the doubled ui.

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_scale: kit.Demo = {
    name = "scale",
    init = init,
    draw = draw,
    script = script,
}

State :: struct {
    app: UiDemo,
    big: bool,
    clicks: int,
    volume: f32,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {volume = 0.5}
    ui_demo_init(&state.app)
    ctx.background = {24, 26, 32, 255}
}

draw :: proc(ctx: ^kit.Context) {
    state.app.painter.scale = 2 if state.big else 1
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "scale demo", {size = {ui.Fixed(220), ui.Fit()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 8}) {
        ui.UiToggle(c, "Double size", &state.big)
        if ui.UiButton(c, "Click me", {ui.Fixed(120), {}}) { state.clicks += 1 }
        ui.UiSlider(c, "Volume", &state.volume, 0, 1, {ui.Fixed(190), {}})
        ui.UiLabelf(c, "clicks: %d", state.clicks)
    }
    ui_demo_end(&state.app)
}

// logical: the toggle at (10, 10) 28 high, the button at (10, 46) 120 x 28
script: []kit.Step = {
    kit.Wait(4),
    kit.Click({70, 60}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.clicks == 1 }, "the button is clicked at scale 1"),
    kit.Click({24, 24}),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.big && state.app.painter.scale == 2 }, "the toggle doubled the scale"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        // the layout did not change: the same logical rectangle, the screen the ui sees is half of the pixels
        rect, found := ui.UiElementRect(&state.app.ctx, ui.UiIdPath("scale demo", "Click me"))
        return found && abs(rect.x - 10) < 0.5 && abs(rect.y - 46) < 0.5 && abs(rect.z - 120) < 0.5 && abs(state.app.ctx.screen.x * 2 - ctx.screen.x) < 0.5
    }, "the layout is in logical units: the same rectangles, half of the screen"),
    kit.Click({140, 120}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.clicks == 2 }, "the same button is at twice the pixels and is clicked there"),
    kit.Capture("scale_2x"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
