#+private file
package demo_common

// The style editor as an application would embed it (default_style/style_editor.odin): a page with a few widgets, the editor window next to it, a store of styles in memory (an application
// without files; the other demos keep theirs in odin_utilities/ui/styles, see demo_style.odin) and the page drawn with the style that is edited. Pick element covers what is under the pointer
// with a light veil and a press chooses it. This demo does not use ui_demo_begin / ui_demo_end: those add the shared editor of the demo window, which is this one here.

import ui ".."
import ui_default "../default_style"
import ui_kit "../kit"
import kit "../../demo_kit"

@(private = "package")
demo_styleeditor: kit.Demo = {
    name = "style editor",
    init = init,
    draw = draw,
    script = script,
}

State :: struct {
    storage: ui.Storage(1024, 2048, 256, 16384),
    ctx: ui.Context,
    painter: ui_default.Painter,
    style: ui.Style,
    editor: ui_default.StyleEditor,
    memory: ui_default.MemoryStyles,
    store: ui_default.StyleStore,
    name: [24]u8,
    length: int,
    volume: f32,
    on: bool,
    clicks: int,
    changes: int,
}

state: State
target: kit.Rect
point: kit.Vec2

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_kit.PainterInit(&state.painter)
    state.style = ui_default.StyleMake()
    ui.UiInit(&state.ctx, &state.storage, ui_default.Measure, &state.painter)
    state.store = ui_default.MemoryStyleStoreMake(&state.memory)
    dark, light: ui_default.Theme = ui_default.THEME_DARK, ui_default.THEME_LIGHT
    state.store.save(&state.store, "dark", &dark)
    state.store.save(&state.store, "light", &light)
    ui_default.StyleEditorInit(&state.editor, ui_default.THEME_DARK, {620, 30})
    state.editor.apply = true
    state.editor.name_length = copy(state.editor.name[:], "mine")
    state.volume, state.on = 0.4, true
}

draw :: proc(ctx: ^kit.Context) {
    // the page has the style that is edited
    state.painter.theme = state.editor.theme
    ctx.background = kit.Color(state.painter.theme.background)
    ui_kit.Begin(&state.ctx, &state.painter, &state.style, ctx)
    c: ^ui.Context = &state.ctx
    if ui.UiWindow(c, "page", {30, 30}, {ui.Fixed(540), {}}, {direction = .TOP_TO_BOTTOM, gap = 10, padding = ui.PaddingAll(16)}) {
        ui.UiTitle(c, "A page to restyle", 1.3)
        ui.UiLabelDim(c, "Turn on Pick element in the editor, point at something and press.", .WORDS)
        ui.ElementOpen(c, {layout = {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 8}})
        if ui.UiButton(c, "Plain") { state.clicks += 1 }
        ui.UiTagged(c, "primary")
        if ui.UiButton(c, "Primary") { state.clicks += 1 }
        ui.UiPopTag(c)
        ui.UiTagged(c, "danger")
        if ui.UiButton(c, "Danger") { state.clicks += 1 }
        ui.UiPopTag(c)
        ui.ElementClose(c)
        ui.UiSlider(c, "Volume", &state.volume, 0, 1, {ui.Grow(), {}})
        ui.UiToggle(c, "Notifications", &state.on)
        ui.UiTextField(c, "##name", state.name[:], &state.length, {ui.Grow(), {}})
        ui.UiLabel(c, ui.UiFormat(c, "clicks: %d", state.clicks))
    }
    if ui_default.UiStyleEditor(c, &state.editor, &state.store) {
        state.changes += 1
    }
    ui.UiEnd(c)
    ui.UiRender(c)
}

// ---- the script -------------------------------------------------------------------------------------------------------------------------------------------------------

aim :: proc(path: ..string) -> bool {
    rect, found := ui.UiElementRect(&state.ctx, ui.UiIdPath(..path))
    point = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    return found && rect.z > 0
}

// The rectangle of a button of the page, a margin around it, for a masked capture
frameOf :: proc(path: ..string) -> bool {
    rect, found := ui.UiElementRect(&state.ctx, ui.UiIdPath(..path))
    target = {rect.x - 3, rect.y - 3, rect.z + 6, rect.w + 6}
    return found && rect.z > 0
}

script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui_default.STYLE_EDITOR_TITLE, "Pick element") }, "the Pick element switch"),
    kit.ClickAt(&point),
    kit.MoveTo({20, 700}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.editor.pick && state.ctx.edit.on }, "edit mode is on"),
    // the element under the pointer is covered: the masked picture holds only the button and its veil (the veil is the white of `edit_overlay`, 0.05 of it)
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim("page", "Plain") && frameOf("page", "Plain") }, "the Plain button"),
    kit.MoveAt(&point),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        hover, hovering := ui.UiEditHover(&state.ctx)
        return hovering && hover.kind == .BUTTON && ui.EditTargetName(&hover) == "Plain"
    }, "the hovered element is the button"),
    kit.CaptureAt("style_editor_hover", &target),
    kit.Wait(1),
    // a press picks it and the button does not take it
    kit.MouseDownStep(),
    kit.Wait(2),
    kit.MouseUpStep(),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        picked, found := ui.UiEditPicked(&state.ctx)
        return found && picked.kind == .BUTTON && state.clicks == 0
    }, "the press picked the button and was not a click on it"),
    kit.MoveTo({20, 700}),
    kit.Wait(3),
    kit.Capture("style_editor_picked"),
    kit.Wait(2),
    // the style is saved under a name and listed
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui_default.STYLE_EDITOR_TITLE, "Save") }, "the Save button"),
    kit.ClickAt(&point),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.memory.count == 3 }, "the style was saved: dark, light and mine"),
    // the page works again with edit mode off
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim(ui_default.STYLE_EDITOR_TITLE, "Pick element") }, "the Pick element switch again"),
    kit.ClickAt(&point),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !state.editor.pick && !state.ctx.edit.on }, "edit mode is off"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return aim("page", "Plain") }, "the Plain button again"),
    kit.ClickAt(&point),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.clicks == 1 }, "a click goes to the button when edit mode is off"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.ctx) == {} }, "no problems"),
}
