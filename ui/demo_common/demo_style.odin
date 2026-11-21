package demo_common

// The style of the ui demos: one style for all of them that stays between runs, and the style editor in every demo window. The saved styles are the files of odin_utilities/ui/styles
// (`dark.style`, `light.style` and the ones that are saved from the editor); `current.style` is the style that is in use, written every time the editor changes it and read when a demo starts.
// With a current style present every demo draws with it (`Apply` in the editor turns that off). The editor opens with the `Style` button at the bottom right or with F2; in its window
// `Pick element` covers the element under the pointer with a light veil (the colors of the veil are style fields too) and a press chooses it: the fields it is drawn with come first in the list.
//
// Nothing of this is in the headless tests or in the captured pictures (the scripts need the same look every time): see `demoStyleEnabled`.

import ui ".."
import ui_default "../default_style"
import kit "../../demo_kit"

STYLES_FOLDER :: #directory + "../styles"
CURRENT_STYLE :: "current"

@(private = "file")
Shared :: struct {
    editor: ui_default.StyleEditor,
    file_store: ui_default.FileStore,
    store: ui_default.StyleStore,
    ready: bool,
    open: bool,
    seeded: bool,       // the editor took the theme of the demo it was opened in
}

@(private = "file")
shared: Shared

// The editor and the saved style are for a person at a window: a test (`odin test`, the scripts of the demos played in a window with -define:DEMO_TEST) has none of it
@(private = "file")
demoStyleEnabled :: proc(kit_ctx: ^kit.Context) -> bool {
    when kit.DEMO_TEST {
        return false
    } else {
        return kit_ctx != nil && kit_ctx.backend != nil && kit_ctx.backend.name != "headless"
    }
}

@(private = "file")
demoStyleReady :: proc() {
    if shared.ready { return }
    shared.ready = true
    shared.store = ui_default.FileStyleStoreMake(&shared.file_store, STYLES_FOLDER)
    ui_default.StyleEditorInit(&shared.editor, ui_default.THEME_DARK, {40, 60})
    shared.editor.name_length = copy(shared.editor.name[:], "my style")
    loaded: ui_default.Theme = ui_default.THEME_DARK
    if shared.store.load(&shared.store, CURRENT_STYLE, &loaded) {
        shared.editor.theme = loaded
        shared.editor.apply = true
        shared.seeded = true
    }
}

// Before the frame of a demo's ui: the demo has set its own theme, the current style takes its place (and the ground behind the ui)
demoStyleBegin :: proc(painter: ^ui_default.Painter, kit_ctx: ^kit.Context) {
    if !demoStyleEnabled(kit_ctx) { return }
    demoStyleReady()
    if shared.editor.apply {
        painter.theme = shared.editor.theme
        kit_ctx.background = kit.Color(shared.editor.theme.background)
    }
}

// At the end of the frame, before UiEnd: the Style button and, when it is on, the editor
demoStyleEnd :: proc(ctx: ^ui.Context, painter: ^ui_default.Painter, kit_ctx: ^kit.Context) {
    if !demoStyleEnabled(kit_ctx) { return }
    demoStyleReady()
    if kit.KeyPressed(&kit_ctx.input, .F2) { shared.open = !shared.open }
    if ui.UiWindow(ctx, "##style_button", {ctx.screen.x - 96, ctx.screen.y - 44}, {ui.Fixed(86), {}}, {padding = ui.PaddingAll(4)}, 190) {
        ui.UiToggle(ctx, "Style", &shared.open)
    }
    if !shared.open {
        ui.UiEditMode(ctx, false)
        return
    }
    if !shared.seeded {
        // the first time: the editor starts from the look the demo has now
        shared.editor.theme = painter.theme
        shared.seeded = true
    }
    if ui_default.UiStyleEditor(ctx, &shared.editor, &shared.store) {
        shared.editor.apply = true
        shared.store.save(&shared.store, CURRENT_STYLE, &shared.editor.theme)
    }
}
