#+private file
package demo_common

// Editing text: a click focuses a field, typing goes in at the cursor, Shift and the arrows select, Ctrl + A selects all, Ctrl + C / X / V use the clipboard (the system's
// when the glue connects it, else one inside of the program), a double click takes a word and dragging selects. The script types in the first field, selects all,
// copies, and pastes into the second one.

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_text: kit.Demo = {
    name = "text",
    init = init,
    draw = draw,
    script = script,
}

State :: struct {
    app: UiDemo,
    first: [64]u8,
    first_length: int,
    second: [64]u8,
    second_length: int,
    notes: [256]u8,
    notes_length: int,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_demo_init(&state.app)
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "text demo", {size = {ui.Fixed(260), ui.Fit()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 8}) {
        ui.UiTextField(c, "Type here", state.first[:], &state.first_length, {ui.Fixed(240), {}})
        ui.UiTextField(c, "Paste here", state.second[:], &state.second_length, {ui.Fixed(240), {}})
        ui.UiTextArea(c, "Notes: several lines, wrapped", state.notes[:], &state.notes_length, {ui.Fixed(240), ui.Fixed(100)})
    }
    ui_demo_end(&state.app)
}

// the fields are at (10, 10) and (10, 46), 240 x 28, the area at (10, 82), 240 x 100
script: []kit.Step = {
    kit.Wait(4),
    kit.Click({60, 24}),
    kit.Wait(2),
    kit.Type("hello big world"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.first[:state.first_length]) == "hello big world" }, "the text was typed at the cursor"),
    // shift + ctrl + left twice: the last two words
    kit.KeyDownStep(.LEFT_SHIFT),
    kit.KeyDownStep(.LEFT_CTRL),
    kit.Wait(1),
    kit.Tap(.LEFT),
    kit.Wait(1),
    kit.Tap(.LEFT),
    kit.Wait(1),
    kit.KeyUpStep(.LEFT_CTRL),
    kit.KeyUpStep(.LEFT_SHIFT),
    kit.Wait(2),
    kit.Capture("text_selection"),
    kit.KeyDownStep(.LEFT_CTRL),
    kit.Wait(1),
    kit.Tap(.C),
    kit.Wait(1),
    kit.KeyUpStep(.LEFT_CTRL),
    kit.Click({60, 60}),
    kit.Wait(2),
    kit.KeyDownStep(.LEFT_CTRL),
    kit.Wait(1),
    kit.Tap(.V),
    kit.Wait(1),
    kit.KeyUpStep(.LEFT_CTRL),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.second[:state.second_length]) == "big world" }, "the selected words were copied and pasted into the other field"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.first[:state.first_length]) == "hello big world" }, "copy leaves the text"),
    // the text area: two lines, up and down, a selection over the line break, wrapping of a long line
    kit.Click({60, 100}),
    kit.Wait(2),
    kit.Type("first line"),
    kit.Tap(.ENTER),
    kit.Type("second, a longer"),
    kit.Wait(1),
    kit.Type(" line that wraps"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.notes[:state.notes_length]) == "first line\nsecond, a longer line that wraps" }, "new lines are typed into the area"),
    kit.Tap(.UP),
    kit.Wait(2),
    kit.Tap(.UP),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        cursor, _, found := ui.UiTextCursor(&state.app.ctx, ui.UiIdPath("text demo", "Notes: several lines, wrapped"))
        return found && cursor <= 10        // on the first row now
    }, "up went over the wrapped row to the first line"),
    kit.KeyDownStep(.LEFT_SHIFT),
    kit.Wait(1),
    kit.Tap(.DOWN),
    kit.Wait(1),
    kit.Tap(.DOWN),
    kit.Wait(1),
    kit.KeyUpStep(.LEFT_SHIFT),
    kit.Wait(2),
    kit.Capture("text_area"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
