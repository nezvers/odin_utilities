#+private file
package demo_common

// Resizing by the pointer, with nothing for the program to keep: a window that is resized by its edges and corners (UiWindowResizable keeps its
// own position and size) with a split in it, side by side (a list and the rest), and a second split in the rest, stacked (details above a log).
// The splits keep their proportion when the window changes size and never let a section go below its minimum. The script drags a handle, the
// other one, pushes one past its limit, and drags the corner of the window.

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_resize: kit.Demo = {
    name = "resize",
    init = init,
    draw = draw,
    script = script,
}

state: UiDemo

init :: proc(ctx: ^kit.Context) {
    ui_demo_init(&state)
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state, ctx)
    c: ^ui.Context = &state.ctx
    if ui.UiWindowResizable(c, "Workspace", nil, nil, {260, 200}, initial_position = {60, 40}, initial_size = {520, 360}) {
        if ui.UiSplit(c, "main", .HORIZONTAL, 0.32, min_first = 80, min_second = 120) {
            if ui.UiSplitFirst(c) {
                if ui.UiPanel(c, "list", {size = {ui.Grow(), ui.Grow()}}) {
                    for i in 0 ..< 4 {
                        ui.UiButton(c, ui.UiFormat(c, "Item %d##%d", i, i), {ui.Grow(), {}})
                    }
                }
            }
            if ui.UiSplitSecond(c) {
                // a split in a section: three sections in all
                if ui.UiSplit(c, "side", .VERTICAL, 0.25) {
                    if ui.UiSplitFirst(c) {
                        if ui.UiPanel(c, "details", {size = {ui.Grow(), ui.Grow()}}) {
                            ui.UiLabelf(c, "list: %.0f %%", ui.UiSplitRatio(c, ui.UiIdPath("Workspace", "main")) * 100)
                        }
                    }
                    if ui.UiSplitSecond(c) {
                        if ui.UiPanel(c, "log", {size = {ui.Grow(), ui.Grow()}}) {
                            ui.UiLabelf(c, "details: %.0f %%", ui.UiSplitRatio(c, ui.UiIdPath("Workspace", "main", "side")) * 100)
                        }
                    }
                }
            }
        }
    }
    ui_demo_end(&state)
}

script: []kit.Step = {
    kit.Wait(3),
    // the body is padded by 10: the split is 500 x 312 at (70, 78), the list is 0.32 of it (160), its handle at x 230..236
    kit.MoveTo({233, 234}),
    kit.Wait(3),
    kit.Drag({233, 234}, {293, 234}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return abs(ui.UiSplitRatio(&state.ctx, ui.UiIdPath("Workspace", "main")) - 220.0 / 500) < 0.005
    }, "the handle moved the border by what the pointer moved"),
    // the section after the handle: x 296..570. Its split is 0.25 of 312 high: the handle at y 156..162
    kit.MoveTo({433, 159}),
    kit.Wait(3),
    kit.Drag({433, 159}, {433, 199}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return abs(ui.UiSplitRatio(&state.ctx, ui.UiIdPath("Workspace", "main", "side")) - 118.0 / 312) < 0.005
    }, "the stacked split moved up and down, the other one did not change"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return abs(ui.UiSplitRatio(&state.ctx, ui.UiIdPath("Workspace", "main")) - 220.0 / 500) < 0.005
    }, "the first split stayed"),
    // too far to the right: the list stops where the rest keeps its minimum width (120)
    kit.MoveTo({293, 234}),
    kit.Wait(3),
    kit.Drag({293, 234}, {700, 234}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        side, found := ui.UiElementRect(&state.ctx, ui.UiIdPath("Workspace", "main", "side"))
        return found && abs(side.z - 120) < 1
    }, "the other section kept its minimum width"),
    // the corner of the window: the bottom right at (580, 400), the grip is 14 wide
    kit.MoveTo({573, 393}),
    kit.Wait(3),
    kit.Drag({573, 393}, {633, 433}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        size: ui.Vec2 = ui.UiWindowSize(&state.ctx, "Workspace")
        return abs(size.x - 580) < 1 && abs(size.y - 400) < 1
    }, "the corner resized the window"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        main, found := ui.UiElementRect(&state.ctx, ui.UiIdPath("Workspace", "main"))
        side, _ := ui.UiElementRect(&state.ctx, ui.UiIdPath("Workspace", "main", "side"))
        return found && abs(main.z - 560) < 1 && side.z > 120.5
    }, "the splits took the room of the bigger window and kept their proportion"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the frames had no problems"),
}
