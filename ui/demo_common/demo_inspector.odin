#+private file
package demo_common

// The inspector next to a small ui: the tree of the elements of the last frame, what the buffers cost, and picking. Press Pick, then press an element of the ui on the left: it is marked
// and selected in the tree, with its place and its kind; a double click on an element with children closes it. Commands shows the draw commands of the frame, History the cost of the last frames.
// The script picks the slider.

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_inspector: kit.Demo = {
    name = "inspector",
    init = init,
    draw = draw,
    script = script,
}

State :: struct {
    app: UiDemo,
    mute: bool,
    volume: f32,
    clicks: int,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {volume = 0.6}
    ui_demo_init(&state.app)
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "demo", {size = {ui.Fixed(780), ui.Fixed(560)}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingAll(10), gap = 10}) {
        if ui.UiPanel(c, "app", {size = {ui.Fixed(240), ui.Grow()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 8}) {
            ui.UiToggle(c, "Mute", &state.mute)
            ui.UiSlider(c, "Volume", &state.volume, 0, 1, {ui.Fixed(200), {}})
            if ui.UiButton(c, "Count", {ui.Fixed(200), {}}) { state.clicks += 1 }
            ui.UiLabelf(c, "clicks: %d", state.clicks)
        }
        ui.UiInspector(c, "Inspector", {ui.Grow(), ui.Grow()})
    }
    ui_demo_end(&state.app)
}

// the app panel is at (10, 10), padding 10, gap 8, controls 28 high: the toggle at y 20, the slider at y 56 (x 20 .. 220)
script: []kit.Step = {
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return len(ui.InspectorRows(&state.app.ctx)) > 5 }, "the inspector lists the elements"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        ui.UiInspectorPick(&state.app.ctx)
        return true
    }, "start picking"),
    kit.Wait(2),
    kit.MoveTo({100, 70}),
    kit.Wait(3),
    kit.Click({100, 70}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        row, found := ui.UiInspectorSelected(&state.app.ctx)
        return found && row.kind == .SLIDER && abs(row.rect.x - 20) < 1 && abs(row.rect.z - 200) < 1
    }, "the press picked the slider: its kind and place are in the tree"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.volume == 0.6 }, "the press did not reach the slider: it was a pick"),
    kit.Capture("inspector"),
    kit.Wait(1),
    // the draw commands of the frame as a list, and the plots of the last frames
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        ui.UiInspectorView(&state.app.ctx, true, true)
        return true
    }, "show the commands and the history"),
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return len(ui.InspectorCommands(&state.app.ctx)) > 10 }, "the draw commands of the frame are listed"),
    kit.Capture("inspector_commands"),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        ui.UiInspectorView(&state.app.ctx, false, false)
        return true
    }, "back to the tree"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
