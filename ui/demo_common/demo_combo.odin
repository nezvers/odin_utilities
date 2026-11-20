#+private file
package demo_common

// A dropdown with a search: typing narrows the list. The script opens it, types a few letters, takes the highlighted match with Enter, then opens it again and picks a row.

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_combo: kit.Demo = {
    name = "combo",
    init = init,
    draw = draw,
    script = script,
}

state: UiDemo
selected: int
changed_count: int

FONTS: []string = {
    "Arial", "Courier New", "DejaVu Sans", "DejaVu Sans Mono", "Fira Code", "Fira Sans", "Georgia", "Helvetica", "Inter", "JetBrains Mono",
    "Liberation Mono", "Liberation Sans", "Noto Sans", "Noto Sans Mono", "Roboto", "Roboto Mono", "Source Code Pro", "Ubuntu", "Ubuntu Mono", "Verdana",
}

init :: proc(ctx: ^kit.Context) {
    ui_demo_init(&state)
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
    selected = 0
    changed_count = 0
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state, ctx)
    c: ^ui.Context = &state.ctx
    if ui.UiWindow(c, "Combo", {40, 40}, {ui.Fixed(260), {}}) {
        if ui.UiCombo(c, "Font", FONTS, &selected, {ui.Fixed(240), {}}, 6) { changed_count += 1 }
        ui.UiLabelf(c, "chosen: %s", FONTS[selected])
    }
    ui_demo_end(&state)
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Click({150, 64}),
    kit.Wait(3),
    kit.Type("mono"),
    kit.Wait(3),
    kit.Capture("combo_search"),
    kit.Tap(.DOWN),
    kit.Wait(2),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiMatchText(FONTS[selected], "mono") }, "enter took a match of the search"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return changed_count == 1 }, "the change was told once"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the frames had no problems"),
}
