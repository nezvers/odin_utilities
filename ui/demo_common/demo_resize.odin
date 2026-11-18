#+private file
package demo_common

// Resizing by the pointer: a window that is resized by its edges and corners (UiWindowResizable), and splitters between its sections, side by
// side (a list and the rest) and stacked (details above a log). The section before a splitter has a fixed size that the program keeps, the one
// after it is Grow(): it takes what is left, so a bigger window gives the room to the sections that grow. The script drags a splitter, the
// other one, and the corner of the window.

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
window_position: ui.Vec2
window_size: ui.Vec2
list_width: f32
details_height: f32

init :: proc(ctx: ^kit.Context) {
    ui_demo_init(&state)
    window_position = {60, 40}
    window_size = {520, 360}
    list_width = 160
    details_height = 100
    ctx.background = {24, 26, 32, 255}
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state, ctx)
    c: ^ui.Context = &state.ctx
    if ui.UiWindowResizable(c, "Workspace", &window_position, &window_size, {260, 200}) {
        // two sections side by side with a splitter between them: the container has a name, so the splitter knows how far it may go
        if ui.UiPanel(c, "area", {size = {ui.Grow(), ui.Grow()}, direction = .LEFT_TO_RIGHT, gap = 6}) {
            if ui.UiPanel(c, "list", {size = {ui.Fixed(list_width), ui.Grow()}}) {
                for i in 0 ..< 4 {
                    ui.UiButton(c, ui.UiFormat(c, "Item %d##%d", i, i), {ui.Grow(), {}})
                }
            }
            ui.UiSplitter(c, "list splitter", &list_width, .HORIZONTAL, 80, 120)
            // the other section: details above a log, with a splitter that moves up and down
            if ui.UiPanel(c, "right", {size = {ui.Grow(), ui.Grow()}, gap = 6}) {
                if ui.UiPanel(c, "details", {size = {ui.Grow(), ui.Fixed(details_height)}}) {
                    ui.UiLabelf(c, "list %.0f px", list_width)
                }
                ui.UiSplitter(c, "details splitter", &details_height, .VERTICAL, 40, 40)
                if ui.UiPanel(c, "log", {size = {ui.Grow(), ui.Grow()}}) {
                    ui.UiLabelf(c, "details %.0f px", details_height)
                }
            }
        }
    }
    ui_demo_end(&state)
}

script: []kit.Step = {
    kit.Wait(3),
    // the splitter of the list: at x 236..242 (the body is padded by 10, the list is 160 wide), in the middle of the height
    kit.MoveTo({239, 234}),
    kit.Wait(3),
    kit.Drag({239, 234}, {299, 234}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(list_width - 220) < 1 }, "the splitter moved the border by what the pointer moved"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        right, found := ui.UiElementRect(&state.ctx, ui.UiIdPath("Workspace", "area", "right"))
        return found && abs(right.x - 308) < 1 && abs(right.z - 262) < 1
    }, "the section after it took the rest"),
    // the splitter between details and log: the right section starts at x 308 and is 262 wide, details are 100 high from y 78
    kit.MoveTo({439, 187}),
    kit.Wait(3),
    kit.Drag({439, 187}, {439, 227}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(details_height - 140) < 1 }, "the stacked splitter moved up and down"),
    // too far to the right: the list stops where the other section keeps its minimum
    kit.MoveTo({296 + 3, 234}),
    kit.Wait(3),
    kit.Drag({299, 234}, {700, 234}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        right, found := ui.UiElementRect(&state.ctx, ui.UiIdPath("Workspace", "area", "right"))
        return found && right.z >= 119
    }, "the other section kept its minimum width"),
    // the corner of the window: the bottom right at (580, 400), the grip is 14 wide
    kit.MoveTo({573, 393}),
    kit.Wait(3),
    kit.Drag({573, 393}, {633, 433}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(window_size.x - 580) < 1 && abs(window_size.y - 400) < 1 }, "the corner resized the window"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        area, found := ui.UiElementRect(&state.ctx, ui.UiIdPath("Workspace", "area"))
        return found && area.z > 500
    }, "what grows inside took the room of the bigger window"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the frames had no problems"),
}
