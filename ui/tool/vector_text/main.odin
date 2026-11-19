// The ui of the library on raylib with its text drawn by the font library through PainterUseVectorText (batched: one draw call for a run of labels). It checks what the kit demos cannot: the
// order of text and shapes with the batch, clipping, a popup over text. `odin run ui/tool/vector_text` shows it, `-- --shot out.png` saves a picture and exits; `-- --scanline` uses the other
// method.
package main

import "core:fmt"
import "core:os"
import rl "vendor:raylib"
import ui "../.."
import ui_default "../../default_style"
import ui_raylib "../../glue_raylib"
import font "../../../font"
import font_raylib "../../../font/glue_raylib"

FIRA :: #load("../../../assets/fonts/FiraCode-Regular.ttf")

main :: proc() {
    shot: string
    method: font.Method = .SLUG
    for i in 1 ..< len(os.args) {
        if os.args[i] == "--shot" && i + 1 < len(os.args) { shot = os.args[i + 1] }
        if os.args[i] == "--scanline" { method = .SCANLINE }
    }
    rl.InitWindow(900, 620, "ui with vector text")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    system: font_raylib.TextSystem
    if !font_raylib.TextSystemInit(&system, FIRA, method) {
        fmt.eprintln("no text system")
        os.exit(1)
    }
    painter: ui_default.Painter
    ui_raylib.PainterInit(&painter)
    ui_raylib.PainterUseVectorText(&painter, &system)
    style: ui.Style = ui_default.StyleMake()
    storage: ^ui.Storage(512, 1024, 128, 8192) = new(ui.Storage(512, 1024, 128, 8192))
    ctx: ^ui.Context = new(ui.Context)
    ui.UiInit(ctx, storage, ui_default.Measure, &painter)

    choice: int
    slider: f32 = 0.4
    toggle: bool = true
    open_popup: bool
    options: []string = {"First option", "Second option", "Third option"}
    frame: int
    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground({24, 26, 32, 255})
        ui.UiBegin(ctx, ui_raylib.InputPoll(), rl.GetFrameTime(), ui_raylib.ScreenSize(), &style)
        if ui.UiWindow(ctx, "Settings", {30, 30}, {ui.Fixed(420), {}}) {
            ui.UiLabel(ctx, "A label above everything")
            ui.UiButton(ctx, "Button")
            ui.UiToggle(ctx, "Toggle", &toggle)
            ui.UiSlider(ctx, "Volume", &slider)
            ui.UiDropdown(ctx, "Choice", options, &choice)
            ui.UiLabel(ctx, "A label below the dropdown that the list covers")
            ui.UiLabel(ctx, "And another line of text under it")
            if ui.UiScroll(ctx, "Scroll area", {ui.Fixed(380), ui.Fixed(120)}) {
                for i in 0 ..< 20 { ui.UiLabelf(ctx, "A row of a scrolling list, number %d", i) }
            }
        }
        if ui.UiWindow(ctx, "Second", {480, 90}, {ui.Fixed(380), {}}) {
            for i in 0 ..< 8 { ui.UiLabelf(ctx, "Line %d of the second window", i) }
        }
        ui.UiEnd(ctx)
        ui.UiRender(ctx)
        rl.EndDrawing()
        frame += 1
        _ = open_popup
        if shot != "" && frame == 10 {
            rl.TakeScreenshot(fmt.ctprintf("%s", shot))
            break
        }
    }
}
