// A window with the same text drawn by the two methods of the font library, one above the other, at several sizes.
//     odin run font/tool/preview                 shows it (escape closes)
//     odin run font/tool/preview -- --shot out.png     saves a picture after a few frames and exits
package main

import "core:fmt"
import "core:math"
import "core:os"
import rl "vendor:raylib"
import font "../.."
import font_raylib "../../glue_raylib"

FIRA :: #load("../../../assets/fonts/FiraCode-Regular.ttf")

SAMPLE :: "Sphinx of black quartz, judge my vow 0123456789 @&{}[]"

main :: proc() {
    shot: string
    for i in 1 ..< len(os.args) {
        if os.args[i] == "--shot" && i + 1 < len(os.args) { shot = os.args[i + 1] }
    }
    rl.InitWindow(1100, 760, "font preview")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    face: font.Font
    if !font.FontInit(&face, FIRA) {
        fmt.eprintln("not a font")
        os.exit(1)
    }
    texels: []f32 = make([]f32, 4 * font.ATLAS_WIDTH * 32)
    slug_slots: []i32 = make([]i32, face.glyph_count)
    scanline_slots: []i32 = make([]i32, face.glyph_count)
    scanline_texels: []f32 = make([]f32, 4 * font.ATLAS_WIDTH * 32)
    slug: font.Atlas
    scanline: font.Atlas
    font.AtlasInit(&slug, &face, .SLUG, texels, slug_slots)
    font.AtlasInit(&scanline, &face, .SCANLINE, scanline_texels, scanline_slots)
    slug_renderer, scanline_renderer: font_raylib.Renderer
    if !font_raylib.RendererInit(&slug_renderer, &slug, make([]font.TextVertex, 6 * 2048)) || !font_raylib.RendererInit(&scanline_renderer, &scanline, make([]font.TextVertex, 6 * 2048)) {
        fmt.eprintln("no shader")
        os.exit(1)
    }
    defer {
        font_raylib.RendererDestroy(&slug_renderer)
        font_raylib.RendererDestroy(&scanline_renderer)
    }

    frame: int
    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground({24, 26, 32, 255})
        y: f32 = 30
        sizes: [5]f32 = {12, 16, 24, 40, 64}
        rl.DrawRectangle(0, 360, 1100, 2, {80, 80, 90, 255})
        for pass in 0 ..< 2 {
            renderer: ^font_raylib.Renderer = &slug_renderer if pass == 0 else &scanline_renderer
            y = 24 if pass == 0 else 384
            font_raylib.DrawText(renderer, "Slug" if pass == 0 else "Scanline sweeper", {10, y}, 16, {120, 190, 255, 255})
            y += 14
            for size in sizes {
                y += size * 1.05
                font_raylib.DrawText(renderer, SAMPLE, {10, y}, size, rl.WHITE, {snap_to_pixels = true})
            }
            // turned text, and a line with a color for every letter (one batch)
            font_raylib.DrawText(renderer, "rotated 20 degrees", {620, y - 40}, 26, rl.Color{255, 200, 120, 255}, {rotation = -0.35})
            font_raylib.DrawText(renderer, "rotated 90", {1040, y - 300}, 20, rl.Color{160, 255, 180, 255}, {rotation = 1.5707964})
            rainbow: string = "many colors in one batch"
            pen_x: f32 = 620
            for letter, i in rainbow {
                hue: f32 = f32(i) / f32(len(rainbow))
                tint: rl.Color = {u8(127 + 127 * math.sin(hue * 6.28)), u8(127 + 127 * math.sin(hue * 6.28 + 2.1)), u8(127 + 127 * math.sin(hue * 6.28 + 4.2)), 255}
                pen_x = font_raylib.DrawText(renderer, fmt.tprintf("%c", letter), {pen_x, y + 50}, 30, tint).x
            }
        }
        rl.EndDrawing()
        frame += 1
        if shot != "" && frame == 8 {
            rl.TakeScreenshot(fmt.ctprintf("%s", shot))
            break
        }
    }
}
