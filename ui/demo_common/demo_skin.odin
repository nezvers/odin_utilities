#+private file
package demo_common

// A skin with fonts (ui/default_style/skin.odin): the script names a font file for the regular and the strong face, reads the files and tells the kit to draw in them, then names none and the built in
// fonts come back. The pictures are the same page in both looks.

import ui ".."
import ui_default "../default_style"
import ui_kit "../kit"
import kit "../../demo_kit"

@(private="package")
demo_skin: kit.Demo = {
    name = "skin",
    init = init,
    finit = finit,
    draw = draw,
    script = script,
}

FONTS_FOLDER :: #directory + "../../assets/fonts"

State :: struct {
    app: UiDemo,
    fonts: ui_default.SkinFonts,
    bytes: ui_default.SkinFontBytes,
    value: f32,
    on: bool,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {value = 0.4, on = true}
    ui_demo_init(&state.app)
    ctx.background = {17, 19, 21, 255}
}

finit :: proc(ctx: ^kit.Context) {
    // the next demo gets the built in fonts again
    ui_kit.UseSkinFonts(nil)
    ui_default.SkinFontBytesFree(&state.bytes)
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "skin", {size = {ui.Fixed(420), ui.Fixed(230)}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(12), gap = 8}) {
        ui.UiTitle(c, "A page in a skin")
        ui.UiLabel(c, "The quick brown fox jumps over the lazy dog 0123456789", .WORDS)
        ui.UiLabelDim(c, ui.UiFormat(c, "regular: %s, strong: %s", file_or_built_in(.REGULAR), file_or_built_in(.STRONG)))
        ui.UiButton(c, "A button in the strong face")
        ui.UiSlider(c, "Volume", &state.value, 0, 1, {ui.Grow(), {}})
        ui.UiToggle(c, "Notifications", &state.on)
    }
    ui_demo_end(&state.app)
}

file_or_built_in :: proc(face: ui_default.Face) -> string {
    file: string = ui_default.SkinFontFile(&state.fonts, face)
    return file if file != "" else "built in"
}

use :: proc() {
    ui_default.SkinFontsRead(&state.fonts, FONTS_FOLDER, &state.bytes)
    ui_kit.UseSkinFonts(&state.bytes)
}

script: []kit.Step = {
    kit.Wait(4),
    kit.Capture("skin_built_in"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        ui_default.SkinFontSet(&state.fonts, .REGULAR, "FiraCode-Regular.ttf")
        ui_default.SkinFontSet(&state.fonts, .STRONG, "FiraCode-Regular.ttf")
        use()
        return state.bytes[.REGULAR] != nil && state.bytes[.STRONG] != nil && state.bytes[.MONO] == nil
    }, "the files of two faces were read"),
    kit.Wait(4),
    kit.Capture("skin_fira"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        ui_default.SkinFontSet(&state.fonts, .REGULAR, "")
        ui_default.SkinFontSet(&state.fonts, .STRONG, "no such font.ttf")
        use()
        return state.bytes[.REGULAR] == nil && state.bytes[.STRONG] == nil
    }, "no file and a missing file: the built in fonts"),
    kit.Wait(4),
}
