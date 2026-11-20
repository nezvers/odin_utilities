#+private file
package demo_common

// Navigation with the default actions of Godot (ui_accept, ui_cancel, ui_focus_next, ui_up ... ui_home, ui_page_down), no mouse:
//   Enter / Space  ui_accept   click the focused widget (a button, a toggle, a dropdown opens)
//   Escape         ui_cancel   close a dropdown, leave a text field, and the program closes its dialog (UiCancelled)
//   Tab / Shift+Tab ui_focus_next / ui_focus_prev   the order of the layout, around the end
//   arrows         ui_up ... ui_right   the nearest widget that way; a slider takes left and right as steps; a text field keeps them for its caret
//   Home / End     the first and the last widget       Page up / Page down   a page of the list
// The keys become actions in the glue (ui/kit, ui/glue_raylib, ui/glue_karl2d: a gamepad too), the ui applies them in UiBegin. This file
// only reads what is left for a program: UiCancelled. "Play" sends down to "Quit" (a link), going up from "Play" is blocked.

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
difficulty: int
difficulties: [3]string = {"Easy", "Normal", "Hard"}
options_open: bool
music: bool
name_buffer: [24]u8
name_length: int
refocus: bool                   // the dialog closed: the focus goes back to the button that opened it

init :: proc(ctx: ^kit.Context) {
    ui_demo_init(&state)
    last = "nothing"
    volume = 50
    difficulty = 1
    options_open = false
    music = false
    name_length = 0
    refocus = false
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state, ctx)
    c: ^ui.Context = &state.ctx
    wide: ui.Size = {ui.Fixed(220), {}}

    // while the dialog is open only the dialog is declared: the focus cannot leave it
    if !options_open {
        if ui.UiWindow(c, "Menu", {40, 40}, {ui.Fixed(240), {}}) {
            if ui.UiButton(c, "Play", wide) { last = "play" }
            ui.UiNavLink(c, .DOWN, ui.UiId(c, "Quit"))
            ui.UiNavBlock(c, .UP)
            if ui.UiButton(c, "Options", wide) { options_open = true }
            if refocus {
                ui.UiFocus(c, ui.UiId(c, "Options"))
                refocus = false
            }
            ui.UiSlider(c, "Volume", &volume, 0, 100, wide, "%.0f")
            ui.UiDropdown(c, "Difficulty", difficulties[:], &difficulty, wide)
            if ui.UiButton(c, "Quit", wide) { last = "quit" }
        }
        if ui.UiWindow(c, "List", {300, 40}, {ui.Fixed(200), {}}) {
            if ui.UiScroll(c, "list", {ui.Grow(), ui.Fixed(200)}) {
                for i in 0 ..< 30 {
                    if ui.UiButton(c, ui.UiFormat(c, "Item %d##%d", i, i), {ui.Grow(), {}}) { last = "item" }
                }
            }
        }
        if ui.UiWindow(c, "Keys", {40, 270}, {ui.Fixed(460), {}}) {
            ui.UiLabel(c, "Enter / Space: accept    Escape: cancel    Tab, Shift+Tab: next, previous")
            ui.UiLabel(c, "Arrows: nearest widget    Home, End: first, last    Page up, Page down: a page")
            ui.UiLabelf(c, "last: %s    volume %.0f    difficulty %s", last, volume, difficulties[difficulty])
        }
    } else {
        if ui.UiWindow(c, "Options", {300, 300}, {ui.Fixed(240), {}}) {
            ui.UiToggle(c, "Music", &music, wide)
            ui.UiTextField(c, "Name", name_buffer[:], &name_length, wide)
            if ui.UiButton(c, "Back", wide) { options_open = false; refocus = true }
            // the first widget gets the focus when the dialog opens
            if c.focus == 0 { ui.UiFocus(c, ui.UiId(c, "Music")) }
            // Escape that no widget of the dialog took (a text field that has the focus lets go of it first) closes the dialog
            if ui.UiCancelled(c) { options_open = false; refocus = true }
        }
    }
    ui_demo_end(&state)
}

focused :: proc(path: ..string) -> bool {
    return ui.UiIsFocused(&state.ctx, ui.UiIdPath(..path))
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Tap(.DOWN),                 // nothing is focused: the first widget
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focused("Menu", "Play") }, "the first widget is focused"),
    kit.Tap(.UP),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focused("Menu", "Play") }, "up is blocked on the first widget"),
    kit.Tap(.ENTER),                // ui_accept
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return last == "play" }, "accept clicks the focused button"),
    kit.Tap(.TAB),                  // ui_focus_next
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focused("Menu", "Options") }, "tab goes to the next widget"),
    kit.KeyDownStep(.LEFT_SHIFT),
    kit.Tap(.TAB),                  // ui_focus_prev
    kit.Wait(2),
    kit.KeyUpStep(.LEFT_SHIFT),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focused("Menu", "Play") }, "shift tab goes back"),
    kit.Tap(.DOWN),                 // the link: over Options and the rest to Quit
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focused("Menu", "Quit") }, "the link jumped to Quit"),
    kit.Tap(.UP),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focused("Menu", "Difficulty") }, "up goes to the nearest widget"),

    // the dropdown: accept opens it on the chosen option, down walks the list, accept chooses, cancel closes it without choosing
    kit.Tap(.SPACE),                // ui_accept and ui_select
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.ctx.focus != 0 && !focused("Menu", "Difficulty") }, "the focus left the box for the list"),
    kit.Capture("navigation_dropdown_open"),
    kit.Wait(1),                    // the capture is the frame of this step: the next key must not be in it
    kit.Tap(.DOWN),
    kit.Wait(2),
    kit.Tap(.ENTER),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return difficulty == 2 }, "the option under the focus was chosen"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focused("Menu", "Difficulty") }, "the focus is back on the box"),
    kit.Tap(.ENTER),
    kit.Wait(2),
    kit.Tap(.UP),
    kit.Wait(2),
    kit.Tap(.ESCAPE),               // ui_cancel: closes the list, nothing is chosen
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return difficulty == 2 && focused("Menu", "Difficulty") }, "cancel closed the list and kept the choice"),

    // the slider takes left and right
    kit.Tap(.UP),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focused("Menu", "Volume") }, "up from the dropdown is the slider"),
    kit.Tap(.RIGHT),
    kit.Wait(2),
    kit.Tap(.RIGHT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(volume - 60) < 0.5 }, "right raises the slider by steps"),

    // the list: end, page up, home
    kit.Tap(.END),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focused("List", "list", "Item 29##29") }, "end focuses the last widget"),
    kit.Capture("navigation_list_end"),
    kit.Wait(1),                    // the capture is the frame of this step: the next key must not be in it
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiScrollGet(&state.ctx, ui.UiIdPath("List", "list")) > 100 }, "and the list scrolled to show it"),
    kit.Tap(.PAGE_UP),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !focused("List", "list", "Item 29##29") && !focused("List", "list", "Item 28##28") }, "page up jumps a page of widgets"),
    kit.Tap(.HOME),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focused("Menu", "Play") }, "home focuses the first widget"),

    // the dialog: accept opens it, its first widget is focused, cancel closes it (after a text field let go) and the focus goes back
    kit.Tap(.TAB),
    kit.Wait(2),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return options_open && focused("Options", "Music") }, "the dialog opened with its first widget focused"),
    kit.Capture("navigation_dialog"),
    kit.Wait(1),                    // the capture is the frame of this step: the next key must not be in it
    kit.Tap(.SPACE),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return music }, "space flipped the toggle"),
    kit.Tap(.TAB),
    kit.Wait(2),
    kit.Type("hi"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(name_buffer[:name_length]) == "hi" }, "a focused text field takes what is typed"),
    kit.Tap(.LEFT),                 // the caret, the focus stays
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focused("Options", "Name") }, "left belongs to the text field"),
    kit.Tap(.ESCAPE),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return options_open && !focused("Options", "Name") }, "the first cancel only leaves the text field"),
    kit.Tap(.ESCAPE),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !options_open }, "the second cancel reaches the program and closes the dialog"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focused("Menu", "Options") }, "the focus is back on the button that opened it"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the frames had no problems"),
}
