package demo_common

// What every demo of this library needs: a ui context with its storage, the painter that draws through the kit and the default style.
// Every demo owns one (so the state of a widget does not leak from a demo to the next one).

import ui ".."
import ui_default "../default_style"
import ui_kit "../kit"
import kit "../../demo_kit"

UiDemo :: struct {
    storage: ui.Storage(512, 1024, 128, 8192),
    ctx: ui.Context,
    painter: ui_default.Painter,
    style: ui.Style,
}

ui_demo_init :: proc(demo: ^UiDemo) {
    ui_kit.PainterInit(&demo.painter)
    demo.style = ui_default.StyleMake()
    ui.UiInit(&demo.ctx, &demo.storage, ui_default.Measure, &demo.painter)
}

// The frame of the ui: begin, the widgets of the demo, then end (layout and drawing in the batch of the kit)
ui_demo_begin :: proc(demo: ^UiDemo, kit_ctx: ^kit.Context) {
    ui_kit.Begin(&demo.ctx, &demo.painter, &demo.style, kit_ctx)
}

ui_demo_end :: proc(demo: ^UiDemo) {
    ui.UiEnd(&demo.ctx)
    ui.UiRender(&demo.ctx)
}
