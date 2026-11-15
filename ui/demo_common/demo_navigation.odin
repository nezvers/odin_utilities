#+private file
package demo_common

// A menu that is used with the keyboard only: the arrow keys move the focus to the nearest widget in that direction, Enter clicks it.
// "Play" sends down to "Quit" (a link that jumps over "Options"), going up from "Play" is blocked, the slider takes left and right.
// The mouse is not used by the script at all.

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_navigation: kit.Demo = {
    name = "navigation",
    init = init,
    draw = draw,
    script = script,
}

state: UiDemo
last: string
volume: f32

init :: proc(ctx: ^kit.Context) {
    ui_demo_init(&state)
    last = "nothing"
    volume = 50
    ctx.background = {24, 26, 32, 255}
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state, ctx)
    c: ^ui.Context = &state.ctx
    // the keys are the input of the navigation, any other input (a d-pad, a stick) calls the same procs
    keys: ^kit.Input = &ctx.input
    if kit.KeyPressed(keys, .DOWN) { ui.UiNavigate(c, .DOWN) }
    if kit.KeyPressed(keys, .UP) { ui.UiNavigate(c, .UP) }
    if kit.KeyPressed(keys, .LEFT) { ui.UiNavigate(c, .LEFT) }
    if kit.KeyPressed(keys, .RIGHT) { ui.UiNavigate(c, .RIGHT) }
    if kit.KeyPressed(keys, .ENTER) { ui.UiActivate(c) }

    wide: ui.Size = {ui.Fixed(200), {}}
    if ui.UiWindow(c, "Menu", {40, 40}, {ui.Fixed(220), {}}) {
        if ui.UiButton(c, "Play", wide) { last = "play" }
        ui.UiNavLink(c, .DOWN, ui.UiId(c, "Quit"))
        ui.UiNavBlock(c, .UP)
        if ui.UiButton(c, "Options", wide) { last = "options" }
        ui.UiSlider(c, "Volume", &volume, 0, 100, wide, "%.0f")
        if ui.UiButton(c, "Quit", wide) { last = "quit" }
    }
    ui_demo_end(&state)
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Tap(.DOWN),                 // nothing is focused yet: the first widget
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiIsFocused(&state.ctx, ui.UiIdPath("Menu", "Play")) }, "the first widget is focused"),
    kit.Tap(.UP),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiIsFocused(&state.ctx, ui.UiIdPath("Menu", "Play")) }, "up is blocked on the first widget"),
    kit.Tap(.ENTER),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return last == "play" }, "enter clicks the focused widget"),
    kit.Tap(.DOWN),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiIsFocused(&state.ctx, ui.UiIdPath("Menu", "Quit")) }, "the link jumped over Options"),
    kit.Tap(.UP),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiIsFocused(&state.ctx, ui.UiIdPath("Menu", "Volume")) }, "up goes to the nearest widget"),
    kit.Tap(.RIGHT),
    kit.Wait(2),
    kit.Tap(.RIGHT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(volume - 60) < 0.5 }, "the focused slider takes steps"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the frames had no problems"),
}
