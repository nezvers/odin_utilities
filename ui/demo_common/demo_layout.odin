#+private file
package demo_common

// The layout of Clay in use: a toolbar that grows across the screen, columns by percent and by grow, a wrapped text, a scrolling list
// and a tooltip that floats at the pointer. The script scrolls the list and picks an item of it.

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_layout: kit.Demo = {
    name = "layout",
    init = init,
    draw = draw,
    script = script,
}

state: UiDemo
selected: int
file_clicks: int
tooltip_visible: bool
wrap: bool

init :: proc(ctx: ^kit.Context) {
    ui_demo_init(&state)
    selected = -1
    file_clicks = 0
    tooltip_visible = false
    wrap = true
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state, ctx)
    c: ^ui.Context = &state.ctx

    // a toolbar as wide as the screen: a spacer that grows pushes the last widgets to the right
    toolbar_layout: ui.Layout = {direction = .LEFT_TO_RIGHT, padding = ui.PaddingXY(8, 8), gap = 6, align = {y = .CENTER}}
    if ui.UiWindow(c, "Toolbar", {0, 0}, {ui.Grow(), ui.Fixed(44)}, toolbar_layout) {
        if ui.UiButton(c, "File") { file_clicks += 1 }
        tooltip_visible = ui.UiIsHovered(c, ui.UiId(c, "File"))
        ui.UiButton(c, "Edit")
        ui.UiSpacer(c)
        ui.UiLabelf(c, "selected: %d", selected)
        ui.UiButton(c, "Quit", disabled = true)
    }

    // a column: a row of two panels (30 percent and the rest), a toggle that decides if a text wraps
    if ui.UiWindow(c, "Sidebar", {0, 44}, {ui.Fixed(180), ui.Fixed(300)}) {
        if ui.UiRow(c, {size = {ui.Grow(), ui.Fixed(60)}}) {
            if ui.UiBox(c, {layout = {size = {ui.Percent(0.3), ui.Grow()}}, draw = {kind = .PANEL}}) {}
            if ui.UiBox(c, {layout = {size = {ui.Grow(), ui.Grow()}}, draw = {kind = .PANEL}}) {}
        }
        ui.UiSeparator(c)
        ui.UiToggle(c, "Wrap", &wrap)
        ui.UiLabel(c, "A text that is wider than the column wraps at its spaces.", .WORDS if wrap else .NONE)
    }

    // a list that scrolls: the window is 280 high, the list takes what is left of it
    if ui.UiWindow(c, "Items", {200, 60}, {ui.Fixed(300), ui.Fixed(280)}) {
        if ui.UiScroll(c, "list", {ui.Grow(), ui.Grow()}) {
            for i in 0 ..< 40 {
                if ui.UiButton(c, ui.UiFormat(c, "Item %d##%d", i, i), {ui.Grow(), {}}) { selected = i }
            }
        }
    }

    // a tooltip: floating at the root, put next to the pointer, above everything
    if tooltip_visible {
        tooltip: ui.Decl = {
            layout = {padding = ui.PaddingAll(6)},
            floating = {attach_to = .ROOT, offset = ctx.input.mouse_position + {14, 18}, z_index = 300},
            draw = {kind = .PANEL},
        }
        if ui.UiBox(c, tooltip) {
            ui.UiLabel(c, "Open the file menu")
        }
    }
    ui_demo_end(&state)
}

script: []kit.Step = {
    kit.Wait(3),
    // the File button: the toolbar has 8 px of padding
    kit.MoveTo({20, 22}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tooltip_visible }, "the tooltip shows while the pointer is on the button"),
    kit.Click({20, 22}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return file_clicks == 1 }, "the button of the toolbar was clicked"),
    // the pointer leaves
    kit.MoveTo({600, 600}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !tooltip_visible }, "the tooltip is gone when the pointer leaves"),
    // the list: wheel over it scrolls it by 3 lines of 40 px
    kit.MoveTo({260, 200}),
    kit.Wait(3),
    kit.Scroll(-3),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        scrolled: f32 = ui.UiScrollGet(&state.ctx, ui.UiIdPath("Items", "list"))
        return abs(scrolled - 120) < 1
    }, "the wheel scrolled the list"),
    // items are 28 high, 6 apart, the first at y 80 before scrolling: the one at y 210 is the item 7
    kit.Click({260, 210}),
    kit.Wait(2),
    kit.Capture("layout_item_picked"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return selected == 7 }, "the item under the pointer was picked after the scroll"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the frames had no problems"),
}
