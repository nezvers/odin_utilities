package demo_common

// What every demo of this library needs: a ui context with room for the tables of a report (a cell is two to four elements), the painter that draws
// through the kit and the default style. Every demo owns one, so the state of a widget does not leak from a demo to the next one.

import ui "../../ui"
import ui_default "../../ui/default_style"
import ui_kit "../../ui/kit"
import kit "../../demo_kit"

Screen :: struct {
    storage: ui.Storage(6144, 12288, 1024, 65536),
    ctx: ui.Context,
    painter: ui_default.Painter,
    style: ui.Style,
}

screen_init :: proc(screen: ^Screen) {
    ui_kit.PainterInit(&screen.painter)
    screen.style = ui_default.StyleMake()
    ui.UiInit(&screen.ctx, &screen.storage, ui_default.Measure, &screen.painter)
}

screen_begin :: proc(screen: ^Screen, kit_ctx: ^kit.Context) {
    ui_kit.Begin(&screen.ctx, &screen.painter, &screen.style, kit_ctx)
}

screen_end :: proc(screen: ^Screen) {
    ui.UiEnd(&screen.ctx)
    ui.UiRender(&screen.ctx)
}
