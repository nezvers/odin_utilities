#+private file
package demo_common

// The layout of the demo of Dear ImGui (references/imgui/imgui_demo.cpp, ShowDemoWindow), made with this library: a window with a title bar and a
// menu bar (Menu, Examples, Tools), a scrolling body of collapsing headers (Help, Configuration, Window options, Widgets, Layout & Scrolling,
// Popups & Modal windows, Tables, Inputs & Focus) and the tree nodes of Widgets (Basic, Trees, Collapsing Headers, Bullets, Text, Combo, List boxes,
// Selectables, Tabs, Plotting, Color, Drag and Sliders, Querying status). The widgets are the ones of widgets.odin and widgets_more.odin, the
// look is the default style. What this library does not have (multi-line text, tables with sorting, docking, drag and drop) is left out.
//
// The script uses the keyboard only (focus a widget, Enter, arrows, Escape) so it does not depend on where a font puts a pixel.

import "core:math"
import ui ".."
import ui_default "../default_style"
import ui_kit "../kit"
import kit "../../demo_kit"

@(private="package")
demo_imgui: kit.Demo = {
    name = "imgui demo",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

TITLE :: "Dear ImGui Demo"

// a bigger storage than the other demos: this window shows a few hundred widgets at once
Big :: struct {
    storage: ui.Storage(2048, 4096, 512, 32768),
    ctx: ui.Context,
    painter: ui_default.Painter,
    style: ui.Style,
}

state: Big

window_position: ui.Vec2
// menu
last_menu: string
show_main_menu_bar, show_metrics, option_enabled, option_check: bool = false, false, true, true
// window options
window_flags: [11]bool
// widgets
clicked, radio, counter: int
check: bool
text_buffer: [64]u8
text_length: int
input_int: int
input_float: f32
drag_int: int
drag_float: f32
slider_int: int
slider_float: f32
slider_angle: f32
color_a: [3]f32
combo_item: int
list_item: int
combo_items: [5]string = {"AAAA", "BBBB", "CCCC", "DDDD", "EEEE"}
list_items: [8]string = {"Apple", "Banana", "Cherry", "Kiwi", "Mango", "Orange", "Pineapple", "Strawberry"}
selection: [5]bool
tab: int
tab_names: [4]string = {"Avocado", "Broccoli", "Cucumber", "Dill"}
lines: [64]f32
histogram: [12]f32
progress: f32
show_second_header: bool
wrap_width: f32
scroll_to: f32
// popups
modal_open: bool
dont_ask: bool
popup_choice: string
// inputs
last_action: string
input_a, input_b, input_c: [24]u8
input_a_length, input_b_length, input_c_length: int
inputs_report: bool = true

init :: proc(ctx: ^kit.Context) {
    ui_kit.PainterInit(&state.painter)
    state.style = ui_default.StyleMake()
    ui.UiInit(&state.ctx, &state.storage, ui_default.Measure, &state.painter)
    window_position = {30, 20}
    last_menu = "nothing"
    show_main_menu_bar, show_metrics, option_enabled, option_check = false, false, true, true
    window_flags = {}
    clicked, radio, counter = 0, 0, 0
    check = true
    text_length = 0
    input_int, input_float = 123, 0.001
    drag_int, drag_float = 50, 0.5
    slider_int, slider_float, slider_angle = 7, 0.123, 0
    color_a = {0.4, 0.7, 0.0}
    combo_item, list_item = 0, 2
    selection = {false, true, false, false, false}
    tab = 0
    progress = 0.25
    show_second_header = false
    wrap_width = 260
    modal_open, dont_ask = false, false
    popup_choice = "nothing"
    last_action = "nothing"
    for i in 0 ..< len(histogram) { histogram[i] = f32(math.abs(math.sin(f64(i) * 0.9))) }
    ctx.background = {24, 26, 32, 255}
}

update :: proc(ctx: ^kit.Context) {
    // an animated line, like the plots of the demo
    for i in 0 ..< len(lines) {
        lines[i] = f32(math.sin(ctx.time * 2 + f64(i) * 0.25) * 0.5 + 0.5)
    }
    progress = f32(math.mod(ctx.time * 0.2, 1.0))
}

draw :: proc(ctx: ^kit.Context) {
    ui_kit.Begin(&state.ctx, &state.painter, &state.style, ctx)
    c: ^ui.Context = &state.ctx
    for action in ui.Action {
        if ui.UiActionPressed(c, action) { last_action = ui_action_names[action] }
    }

    if ui.UiWindowTitled(c, TITLE, &window_position, {ui.Fixed(640), ui.Fixed(680)}, {padding = ui.PaddingXY(6, 4), gap = 4}) {
        menu_bar(c)
        if ui.UiScroll(c, "scroll", {ui.Grow(), ui.Grow()}, {padding = ui.PaddingAll(8), gap = 4}) {
            ui.UiLabelf(c, "ui says hello. (after Dear ImGui, nezvers/odin_utilities/ui)")
            section_help(c)
            section_configuration(c)
            section_window_options(c)
            if ui.UiCollapsing(c, "Widgets", true) { section_widgets(c) }
            if ui.UiCollapsing(c, "Layout & Scrolling") { section_layout(c) }
            if ui.UiCollapsing(c, "Popups & Modal windows") { section_popups(c) }
            if ui.UiCollapsing(c, "Tables & Columns") { section_tables(c) }
            if ui.UiCollapsing(c, "Inputs & Focus") { section_inputs(c) }
        }
    }
    ui.UiEnd(&state.ctx)
    ui.UiRender(&state.ctx)
}

ui_action_names: [ui.Action]string = {
    .ACCEPT = "ui_accept", .SELECT = "ui_select", .CANCEL = "ui_cancel", .FOCUS_NEXT = "ui_focus_next", .FOCUS_PREV = "ui_focus_prev",
    .UP = "ui_up", .DOWN = "ui_down", .LEFT = "ui_left", .RIGHT = "ui_right", .PAGE_UP = "ui_page_up", .PAGE_DOWN = "ui_page_down",
    .HOME = "ui_home", .END = "ui_end",
}

// ------------------------------------------------------------------------------------------------------------------------

menu_bar :: proc(c: ^ui.Context) {
    if ui.UiMenuBar(c) {
        if ui.UiMenu(c, "Menu") {
            if ui.UiMenuItem(c, "New") { last_menu = "new" }
            if ui.UiMenuItem(c, "Open", "Ctrl+O") { last_menu = "open" }
            if ui.UiMenu(c, "Open Recent") {
                if ui.UiMenuItem(c, "fish_hat.c") { last_menu = "fish_hat.c" }
                if ui.UiMenuItem(c, "fish_hat.inl") { last_menu = "fish_hat.inl" }
                if ui.UiMenu(c, "More..") {
                    ui.UiMenuItem(c, "Hello")
                    ui.UiMenuItem(c, "Sailor")
                }
            }
            if ui.UiMenuItem(c, "Save", "Ctrl+S") { last_menu = "save" }
            if ui.UiMenuItem(c, "Save As..") { last_menu = "save as" }
            ui.UiSeparator(c)
            if ui.UiMenu(c, "Options") {
                ui.UiMenuItem(c, "Enabled", "", &option_enabled)
                ui.UiMenuItem(c, "Check me", "", &option_check, option_enabled)
            }
            if ui.UiMenuItem(c, "Quit", "Alt+F4") { last_menu = "quit" }
        }
        if ui.UiMenu(c, "Examples") {
            ui.UiMenuItem(c, "Main menu bar", "", &show_main_menu_bar)
            ui.UiSeparatorText(c, "Mini apps")
            ui.UiMenuItem(c, "Console")
            ui.UiMenuItem(c, "Log")
            ui.UiMenuItem(c, "Property editor")
            ui.UiSeparatorText(c, "Concepts")
            ui.UiMenuItem(c, "Auto-resizing window")
            ui.UiMenuItem(c, "Fullscreen window")
        }
        if ui.UiMenu(c, "Tools") {
            ui.UiMenuItem(c, "Metrics/Debugger", "", &show_metrics)
            ui.UiMenuItem(c, "Debug Log")
            ui.UiMenuItem(c, "ID Stack Tool")
        }
    }
}

section_help :: proc(c: ^ui.Context) {
    if ui.UiCollapsing(c, "Help") {
        ui.UiLabel(c, "ABOUT THIS DEMO:")
        ui.UiBullet(c, "Sections below are demonstrating many aspects of the library.")
        ui.UiBullet(c, "The \"Examples\" menu above leads to more demo contents.")
        ui.UiLabel(c, "USER GUIDE:")
        ui.UiBullet(c, "Click and drag on a number to change it; the arrow keys step it.")
        ui.UiBullet(c, "Enter / Space accept, Escape cancels, Tab and Shift+Tab move the focus.")
        ui.UiBullet(c, "Arrows move to the nearest widget, Home / End jump, Page up / down page.")
    }
}

section_configuration :: proc(c: ^ui.Context) {
    if ui.UiCollapsing(c, "Configuration") {
        ui.UiSeparatorText(c, "Navigation")
        keyboard, gamepad: bool = true, true
        ui.UiToggle(c, "Enable keyboard navigation", &keyboard)
        ui.UiToggle(c, "Enable gamepad navigation", &gamepad)
        ui.UiLabelColored(c, "(the ui reads whatever the glue puts in Input.actions)", {140, 144, 160, 255})
        ui.UiSeparatorText(c, "Style")
        ui.UiLabel(c, "The look is a Style: a table of procs, see demo \"styles\".")
    }
}

section_window_options :: proc(c: ^ui.Context) {
    if ui.UiCollapsing(c, "Window options") {
        names: [11]string = {
            "No titlebar", "No scrollbar", "No menu", "No move", "No resize", "No collapse", "No close", "No nav", "No background",
            "No bring to front", "Unsaved document",
        }
        for row in 0 ..< 4 {
            if ui.UiRow(c) {
                for column in 0 ..< 3 {
                    index: int = row * 3 + column
                    if index < len(names) { ui.UiToggle(c, names[index], &window_flags[index], {ui.Fixed(190), {}}) }
                }
            }
        }
    }
}

// ------------------------------------------------------------------------------------------------------------------------

section_widgets :: proc(c: ^ui.Context) {
    if ui.UiTreeNode(c, "Basic", true) {
        ui.UiSeparatorText(c, "General")
        if ui.UiRow(c) {
            if ui.UiButton(c, "Button") { clicked += 1 }
            if clicked & 1 == 1 { ui.UiLabel(c, "Thanks for clicking me!") }
        }
        ui.UiToggle(c, "checkbox", &check)
        if ui.UiRow(c) {
            ui.UiRadio(c, "radio a", &radio, 0)
            ui.UiRadio(c, "radio b", &radio, 1)
            ui.UiRadio(c, "radio c", &radio, 2)
        }
        if ui.UiRow(c, {gap = 4}) {
            for i in 0 ..< 7 {
                hue: f32 = f32(i) / 7
                ui.UiColorButton(c, ui.UiFormat(c, "Click##%d", i), hsv(hue, 0.6, 0.6))
            }
        }
        if ui.UiRow(c) {
            ui.UiLabel(c, "Hold to repeat:")
            if ui.UiArrowButton(c, "##left", .LEFT, true) { counter -= 1 }
            if ui.UiArrowButton(c, "##right", .RIGHT, true) { counter += 1 }
            ui.UiLabelf(c, "%d", counter)
        }
        ui.UiButton(c, "Tooltip")
        ui.UiTooltip(c, "I am a tooltip")
        ui.UiLabelText(c, "label", "Value")

        ui.UiSeparatorText(c, "Inputs")
        ui.UiTextField(c, "input text", text_buffer[:], &text_length)
        ui.UiInputInt(c, "input int", &input_int)
        ui.UiInputFloat(c, "input float", &input_float, 0.01, "%.3f")

        ui.UiSeparatorText(c, "Drags")
        ui.UiDragInt(c, "drag int", &drag_int, 0.2, 0, 100)
        ui.UiDrag(c, "drag float", &drag_float, 0.005, 0, 1, "%.3f")

        ui.UiSeparatorText(c, "Sliders")
        ui.UiSliderInt(c, "slider int", &slider_int, -1, 3)
        ui.UiSlider(c, "slider float", &slider_float, 0, 1, {}, "ratio = %.3f")
        ui.UiSliderAngle(c, "slider angle", &slider_angle)

        ui.UiSeparatorText(c, "Selectors/Pickers")
        ui.UiColorEdit3(c, "color 1", &color_a)
        ui.UiDropdown(c, "combo", combo_items[:], &combo_item, {ui.Fixed(150), {}})
        ui.UiListBox(c, "listbox", list_items[:], &list_item, 4)
    }
    if ui.UiTreeNode(c, "Trees") {
        if ui.UiTreeNode(c, "Basic trees") {
            for i in 0 ..< 5 {
                if ui.UiTreeNode(c, ui.UiFormat(c, "Child %d##%d", i, i), i == 0) {
                    ui.UiLabel(c, "blah blah")
                    ui.UiButton(c, ui.UiFormat(c, "button##b%d", i))
                }
            }
        }
        if ui.UiTreeNode(c, "Advanced, with Selectable nodes") {
            ui.UiLabelColored(c, "tree nodes nest as deep as the layout does", {140, 144, 160, 255})
        }
    }
    if ui.UiTreeNode(c, "Collapsing Headers") {
        ui.UiToggle(c, "Show 2nd header", &show_second_header)
        if ui.UiCollapsing(c, "Header") {
            for i in 0 ..< 5 { ui.UiLabelf(c, "More content %d", i) }
        }
        if show_second_header {
            if ui.UiCollapsing(c, "Second Header") { ui.UiLabel(c, "More content") }
        }
    }
    if ui.UiTreeNode(c, "Bullets") {
        ui.UiBullet(c, "Bullet point 1")
        ui.UiBullet(c, "Bullet point 2")
        if ui.UiRow(c) {
            ui.UiBullet(c, "Bullet point 3 (two calls)")
            ui.UiButton(c, "Button")
        }
    }
    if ui.UiTreeNode(c, "Text") {
        ui.UiSeparatorText(c, "Colored Text")
        ui.UiLabelColored(c, "Pink", {255, 0, 255, 255})
        ui.UiLabelColored(c, "Yellow", {255, 255, 0, 255})
        ui.UiLabelColored(c, "Disabled", {120, 124, 140, 255})
        ui.UiSeparatorText(c, "Word Wrapping")
        ui.UiSlider(c, "Wrap width", &wrap_width, 100, 460, {}, "%.0f")
        if ui.UiBox(c, {layout = {size = {ui.Fixed(wrap_width), {}}}}) {
            ui.UiLabel(c, "This text should automatically wrap on the edge of the box that is as wide as the slider says. It is the wrap of the layout.", .WORDS)
        }
    }
    if ui.UiTreeNode(c, "Combo") {
        ui.UiDropdown(c, "combo 1", combo_items[:], &combo_item, {ui.Fixed(170), {}})
        ui.UiLabelf(c, "Selected: %s", combo_items[combo_item])
    }
    if ui.UiTreeNode(c, "Selectables") {
        for i in 0 ..< 5 {
            if ui.UiSelectable(c, ui.UiFormat(c, "Selectable %d##s%d", i + 1, i), selection[i]) { selection[i] = !selection[i] }
        }
    }
    if ui.UiTreeNode(c, "Tabs") {
        ui.UiTabBar(c, "MyTabBar", tab_names[:], &tab)
        ui.UiLabelf(c, "This is the %s tab!", tab_names[tab])
        ui.UiLabelf(c, "blah blah blah blah blah")
    }
    if ui.UiTreeNode(c, "Plotting") {
        ui.UiPlotLines(c, "Lines", lines[:], "animated", 0, 1)
        ui.UiPlotHistogram(c, "Histogram", histogram[:], "", 0, 1)
        ui.UiProgress(c, "Progress Bar", progress, 0, 1, {ui.Fixed(260), {}}, "%.2f")
    }
    if ui.UiTreeNode(c, "Color/Picker Widgets") {
        ui.UiColorEdit3(c, "MyColor", &color_a)
        if ui.UiRow(c) {
            ui.UiColorButton(c, "swatch", color_a, 40)
            ui.UiLabel(c, "ColorButton (simple)")
        }
    }
    if ui.UiTreeNode(c, "Multi-component Widgets") {
        ui.UiDrag(c, "drag float 1", &color_a[0], 0.005, 0, 1, "%.3f")
        ui.UiDrag(c, "drag float 2", &color_a[1], 0.005, 0, 1, "%.3f")
        ui.UiDrag(c, "drag float 3", &color_a[2], 0.005, 0, 1, "%.3f")
    }
    if ui.UiTreeNode(c, "Querying Item Status (Edited, Active, Hovered etc.)") {
        ui.UiButton(c, "Hover me")
        ui.UiLabelf(c, "is hovered: %v    pointer over the ui: %v", ui.UiIsHovered(c, c.last_id), ui.UiPointerOverUi(c))
    }
}

section_layout :: proc(c: ^ui.Context) {
    ui.UiSeparatorText(c, "Child windows")
    if ui.UiScroll(c, "child", {ui.Fixed(300), ui.Fixed(110)}, {padding = ui.PaddingAll(4), gap = 2}) {
        for i in 0 ..< 30 { ui.UiLabelf(c, "%04d: scrollable region", i) }
    }
    ui.UiSeparatorText(c, "Basic Horizontal Layout")
    if ui.UiRow(c) {
        ui.UiLabel(c, "Two items:")
        ui.UiButton(c, "Hello")
        ui.UiButton(c, "World")
    }
    ui.UiSeparatorText(c, "Scrolling")
    if ui.UiRow(c) {
        if ui.UiButton(c, "Scroll to top") { ui.UiScrollSet(c, ui.UiIdPath(TITLE, "scroll"), 0) }
        if ui.UiButton(c, "Scroll to 300") { ui.UiScrollSet(c, ui.UiIdPath(TITLE, "scroll"), 300) }
    }
}

section_popups :: proc(c: ^ui.Context) {
    ui.UiSeparatorText(c, "Popups")
    if ui.UiRow(c) {
        if ui.UiMenu(c, "Select..") {
            for name in ([?]string{"Bream", "Haddock", "Mackerel", "Pollock", "Tilefish"}) {
                if ui.UiMenuItem(c, name) { popup_choice = name }
            }
        }
        ui.UiLabelf(c, "%s", popup_choice)
    }
    ui.UiSeparatorText(c, "Modals")
    if ui.UiButton(c, "Delete..") { modal_open = true }
    if ui.UiModal(c, "Delete?", &modal_open) {
        ui.UiLabel(c, "All those beautiful files will be deleted.")
        ui.UiLabel(c, "This operation cannot be undone!")
        ui.UiSeparator(c)
        ui.UiToggle(c, "Don't ask me next time", &dont_ask)
        if ui.UiRow(c) {
            if ui.UiButton(c, "OK", {ui.Fixed(120), {}}) { modal_open = false }
            if ui.UiButton(c, "Cancel", {ui.Fixed(120), {}}) { modal_open = false }
        }
    }
    ui.UiLabelf(c, "last menu item: %s", last_menu)
}

section_tables :: proc(c: ^ui.Context) {
    ui.UiLabel(c, "A table is rows of columns of a fixed width here (no sorting, no resizing).")
    names: [3]string = {"One", "Two", "Three"}
    if ui.UiRow(c) {
        for name in names { ui.UiLabelColored(c, name, {140, 144, 160, 255}) }
    }
    for row in 0 ..< 3 {
        if ui.UiRow(c) {
            for column in 0 ..< 3 {
                ui.UiSelectable(c, ui.UiFormat(c, "Hello %d,%d##t%d%d", row, column, row, column), (row + column) % 2 == 0, {ui.Fixed(130), {}})
            }
        }
    }
}

section_inputs :: proc(c: ^ui.Context) {
    ui.UiSeparatorText(c, "Mouse State")
    ui.UiLabelf(c, "Mouse pos: (%.0f, %.0f)", c.input.mouse_position.x, c.input.mouse_position.y)
    ui.UiLabelf(c, "Mouse down: %v", c.input.mouse_down)
    ui.UiSeparatorText(c, "Keyboard, Gamepad & Navigation State")
    ui.UiLabelf(c, "Last action: %s", last_action)
    ui.UiLabelf(c, "Focused id: %d", u32(ui.UiFocused(c)))
    ui.UiSeparatorText(c, "Tabbing")
    ui.UiLabel(c, "Use Tab and Shift+Tab to cycle through these widgets:")
    ui.UiTextField(c, "1", input_a[:], &input_a_length)
    ui.UiTextField(c, "2", input_b[:], &input_b_length)
    ui.UiTextField(c, "3", input_c[:], &input_c_length)
    ui.UiToggle(c, "Pointer over the ui is reported to the game", &inputs_report)
    if ui.UiRow(c) {
        if ui.UiButton(c, "Clear the fields") { input_a_length, input_b_length, input_c_length = 0, 0, 0 }
        ui.UiLabelf(c, "over the ui: %v", ui.UiPointerOverUi(c))
    }
}

hsv :: proc(h: f32, s: f32, v: f32) -> [3]f32 {
    i: int = int(h * 6) % 6
    f: f32 = h * 6 - f32(int(h * 6))
    p, q, t: f32 = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    switch i {
    case 0: return {v, t, p}
    case 1: return {q, v, p}
    case 2: return {p, v, t}
    case 3: return {p, q, v}
    case 4: return {t, p, v}
    }
    return {v, p, q}
}

// ------------------------------------------------------------------------------------------------------------------------
// The script: keyboard only. `focus` puts the focus on a widget by its path (names of the containers it is in, "#body" for the body of a
// header, "#menu" for the popup of a menu); the keys are then what a person would press.

path :: proc(names: ..string) -> ui.Id {
    id: ui.Id = ui.ROOT_ID
    for name in names {
        switch name {
        case "#body": id = ui.UiBodyId(id)
        case "#menu": id = ui.UiMenuPopupId(id)
        case: id = ui.IdFromString(name, id)
        }
    }
    return id
}

focus :: proc(names: ..string) -> bool {
    ui.UiFocus(&state.ctx, path(..names))
    return true
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Capture("imgui_start"),
    kit.Wait(1),

    // a header opens and closes with accept
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "scroll", "Help") }, ""),
    kit.Tap(.ENTER),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiIsOpen(&state.ctx, path(TITLE, "scroll", "Help")) }, "accept opened the Help header"),
    kit.Tap(.ENTER),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !ui.UiIsOpen(&state.ctx, path(TITLE, "scroll", "Help")) }, "and closed it again"),

    // the basic widgets
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "scroll", "Widgets", "#body", "Basic", "#body", "Button") }, ""),
    kit.Tap(.ENTER),
    kit.Wait(2),
    kit.Tap(.SPACE),
    kit.Wait(2),
    kit.Tap(.ENTER),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return clicked == 3 }, "the button was accepted three times"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "scroll", "Widgets", "#body", "Basic", "#body", "radio b") }, ""),
    kit.Tap(.ENTER),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return radio == 1 }, "the radio button was chosen"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "scroll", "Widgets", "#body", "Basic", "#body", "checkbox") }, ""),
    kit.Tap(.ENTER),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !check }, "the checkbox was flipped"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "scroll", "Widgets", "#body", "Basic", "#body", "##right") }, ""),
    kit.Tap(.ENTER),
    kit.Wait(2),
    kit.Tap(.ENTER),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return counter == 2 }, "the arrow button counted"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "scroll", "Widgets", "#body", "Basic", "#body", "drag float") }, ""),
    kit.Tap(.RIGHT),
    kit.Wait(2),
    kit.Tap(.RIGHT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(drag_float - 0.6) < 0.001 }, "right steps a drag value"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "scroll", "Widgets", "#body", "Basic", "#body", "slider int") }, ""),
    kit.Tap(.RIGHT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return slider_int == 3 }, "right steps a slider of whole numbers (to its end)"),
    kit.Wait(1),
    kit.Capture("imgui_basic"),
    kit.Wait(1),

    // tabs: the tree node opens with accept, a tab is chosen with accept
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "scroll", "Widgets", "#body", "Tabs") }, ""),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { ui.UiFocus(&state.ctx, ui.IdFromIndex(2, path(TITLE, "scroll", "Widgets", "#body", "Tabs", "#body", "MyTabBar"))); return true }, ""),
    kit.Tap(.ENTER),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tab == 2 }, "the third tab was chosen"),

    // the menu bar: accept opens a menu, down walks it, accept uses an item
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "Menu") }, ""),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.ctx.open_menu == path(TITLE, "Menu") }, "accept opened the menu"),
    kit.Capture("imgui_menu"),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "Menu", "#menu", "Save") }, ""),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return last_menu == "save" && state.ctx.open_menu == 0 }, "an item was used and the menu closed"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "Menu") }, ""),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Tap(.ESCAPE),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.ctx.open_menu == 0 }, "cancel closed the menu"),

    // a modal dialog: nothing else gets the focus, cancel closes it
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "scroll", "Popups & Modal windows") }, ""),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "scroll", "Popups & Modal windows", "#body", "Delete..") }, ""),
    kit.Tap(.ENTER),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return modal_open }, "accept opened the dialog"),
    kit.Capture("imgui_modal"),
    kit.Wait(1),
    kit.Tap(.TAB),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.ctx.modal_root != 0 }, "a dialog holds the focus"),
    kit.Tap(.ESCAPE),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !modal_open }, "cancel closed the dialog"),

    // the last header: opened from above with accept, the list scrolls to show what it opened, and down goes into its widgets
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focus(TITLE, "scroll", "Inputs & Focus") }, ""),
    kit.Tap(.ENTER),
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiIsOpen(&state.ctx, path(TITLE, "scroll", "Inputs & Focus")) }, "accept opened Inputs & Focus"),
    kit.Tap(.DOWN),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.ctx.focus != path(TITLE, "scroll", "Inputs & Focus") && state.ctx.focus != 0 }, "down leaves the header for what it opened"),
    kit.Capture("imgui_inputs"),
    kit.Wait(1),
    kit.Tap(.TAB),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return focused_in_inputs() }, "tab walks the widgets of the opened section"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "the frames had no problems"),
}

// the focus is on a widget of the body of "Inputs & Focus"
focused_in_inputs :: proc() -> bool {
    body: ui.Id = ui.UiBodyId(path(TITLE, "scroll", "Inputs & Focus"))
    for name in ([?]string{"1", "2", "3", "Pointer over the ui is reported to the game", "Clear the fields"}) {
        if ui.IdFromString(name, body) == state.ctx.focus { return true }
    }
    return false
}
