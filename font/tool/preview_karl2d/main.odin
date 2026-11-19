// The same window as font/tool/preview, on Karl2D (the Direct3D 11 backend on Windows, OpenGL elsewhere).
//     odin run font/tool/preview_karl2d                  shows it (escape closes)
//     odin run font/tool/preview_karl2d -- --shot out.png     saves a picture after a few frames and exits
package main

import "core:fmt"
import "core:math"
import "core:os"
import k2 "../../../karl2d"
import kit "../../../demo_kit"
import font "../.."
import font_karl2d "../../glue_karl2d"

FIRA :: #load("../../../assets/fonts/FiraCode-Regular.ttf")

SAMPLE :: "Sphinx of black quartz, judge my vow 0123456789 @&{}[]"

main :: proc() {
    shot: string
    for i in 1 ..< len(os.args) {
        if os.args[i] == "--shot" && i + 1 < len(os.args) { shot = os.args[i + 1] }
    }
    k2.init(1100, 760, "font preview", options = {window_mode = .Windowed, depth_test = true})
    defer k2.shutdown()
    if shot != "" { k2.r3d_init() }

    face: font.Font
    if !font.FontInit(&face, FIRA) {
        fmt.eprintln("not a font")
        os.exit(1)
    }
    slug_texels: []f32 = make([]f32, 4 * font.ATLAS_WIDTH * 32)
    scanline_texels: []f32 = make([]f32, 4 * font.ATLAS_WIDTH * 32)
    slug_slots: []i32 = make([]i32, face.glyph_count)
    scanline_slots: []i32 = make([]i32, face.glyph_count)
    slug: font.Atlas
    scanline: font.Atlas
    font.AtlasInit(&slug, &face, .SLUG, slug_texels, slug_slots)
    font.AtlasInit(&scanline, &face, .SCANLINE, scanline_texels, scanline_slots)
    slug_renderer, scanline_renderer: font_karl2d.Renderer
    if !font_karl2d.RendererInit(&slug_renderer, &slug, make([]font.TextVertex, 6 * 2048)) || !font_karl2d.RendererInit(&scanline_renderer, &scanline, make([]font.TextVertex, 6 * 2048)) {
        fmt.eprintln("no shader")
        os.exit(1)
    }
    defer {
        font_karl2d.RendererDestroy(&slug_renderer)
        font_karl2d.RendererDestroy(&scanline_renderer)
    }

    frame: int
    for k2.update() {
        k2.clear({24, 26, 32, 255})
        sizes: [5]f32 = {12, 16, 24, 40, 64}
        k2.draw_rect({0, 360, 1100, 2}, {80, 80, 90, 255})
        for pass in 0 ..< 2 {
            renderer: ^font_karl2d.Renderer = &slug_renderer if pass == 0 else &scanline_renderer
            y: f32 = 24 if pass == 0 else 384
            font_karl2d.DrawText(renderer, "Slug" if pass == 0 else "Scanline sweeper", {10, y}, 16, {120, 190, 255, 255})
            y += 14
            for size in sizes {
                y += size * 1.05
                font_karl2d.DrawText(renderer, SAMPLE, {10, y}, size, k2.WHITE, {snap_to_pixels = true})
            }
            // turned text, and a line with a color for every letter (one batch)
            font_karl2d.DrawText(renderer, "rotated 20 degrees", {620, y - 40}, 26, k2.Color{255, 200, 120, 255}, {rotation = -0.35})
            font_karl2d.DrawText(renderer, "rotated 90", {1040, y - 300}, 20, k2.Color{160, 255, 180, 255}, {rotation = 1.5707964})
            rainbow: string = "many colors in one batch"
            pen_x: f32 = 620
            for letter, i in rainbow {
                hue: f32 = f32(i) / f32(len(rainbow))
                tint: k2.Color = {u8(127 + 127 * math.sin(hue * 6.28)), u8(127 + 127 * math.sin(hue * 6.28 + 2.1)), u8(127 + 127 * math.sin(hue * 6.28 + 4.2)), 255}
                pen_x = font_karl2d.DrawText(renderer, fmt.tprintf("%c", letter), {pen_x, y + 50}, 30, tint).x
            }
        }
        k2.draw_current_batch()
        frame += 1
        if shot != "" && frame == 8 {
            pixels, width, height, ok := k2.r3d_read_pixels({}, context.allocator)
            if ok { kit.PngWrite(shot, width, height, pixels) }
            break
        }
        k2.present()
    }
}
