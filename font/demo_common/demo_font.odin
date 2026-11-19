#+private file
package demo_common

// The two methods of the font library side by side: the Slug method on the left and the Scanline Sweeper on the right, the same lines at six sizes. Up and down scale all the sizes (the text
// is the outline of the font at any size, not a picture of it), the script does that and checks the measure of the text.

import "core:fmt"
import kit "../../demo_kit"
import font "../"

FIRA :: #load("../../assets/fonts/FiraCode-Regular.ttf")
SAMPLE :: "Sphinx of black"
SIZES :: [?]f32{8, 11, 16, 24, 34, 44}
COLUMN_WIDTH :: 620

@(private="package")
demo_font: kit.Demo = {
    name = "font",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

face: font.Font
loaded: bool
scale: f32
requests: [MAX_TEXT_REQUESTS]TextRequest

init :: proc(ctx: ^kit.Context) {
    loaded = font.FontInit(&face, FIRA)
    scale = 1
    ctx.background = {24, 26, 32, 255}
}

update :: proc(ctx: ^kit.Context) {
    if kit.KeyPressed(&ctx.input, .UP) { scale = min(scale * 1.25, 1.5) }
    if kit.KeyPressed(&ctx.input, .DOWN) { scale = max(scale / 1.25, 0.5) }
}

draw :: proc(ctx: ^kit.Context) {
    kit.DrawRect(ctx, {ctx.screen.x * 0.5 - 1, 10, 2, ctx.screen.y - 20}, {70, 74, 86, 255})
    kit.DrawText(ctx, "Up / Down: scale the sizes", {20, 14}, 16, {150, 156, 170, 255})
    kit.DrawText(ctx, fmt.tprintf("scale %.2f", scale), {ctx.screen.x - 140, 14}, 16, {150, 156, 170, 255})
    if !loaded { return }
    count: int
    sizes: [6]f32 = SIZES
    for method in font.Method {
        x: f32 = 20 if method == .SLUG else ctx.screen.x * 0.5 + 20
        requests[count] = {"Slug" if method == .SLUG else "Scanline sweeper", {x, 70}, 22, {120, 190, 255, 255}, method}
        count += 1
        y: f32 = 70
        for size in sizes {
            y += size * scale * 1.25 + 14
            requests[count] = {SAMPLE, {x, y}, size * scale, {235, 238, 245, 255}, method}
            count += 1
        }
    }
    if text_drawer != nil { text_drawer(ctx, &face, requests[:count]) }
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return loaded && face.glyph_count > 100 }, "the font is parsed"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        measured: font.Vec2 = font.TextMeasure(&face, SAMPLE, 40)
        advance: f32 = font.FontAdvance(&face, font.FontGlyph(&face, 'S'))
        return abs(measured.x - f32(len(SAMPLE)) * advance * 40) < 0.01 && measured.x < COLUMN_WIDTH
    }, "the text fits a column and is as wide as its characters"),
    kit.Capture("font_start"),
    kit.Wait(1),
    kit.Tap(.UP),
    kit.Tap(.UP),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(scale - 1.5) < 0.001 }, "up scales the sizes, to 1.5 at most"),
    kit.Capture("font_large"),
    kit.Wait(1),
    kit.Tap(.DOWN),
    kit.Tap(.DOWN),
    kit.Tap(.DOWN),
    kit.Tap(.DOWN),
    kit.Tap(.DOWN),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(scale - 0.5) < 0.001 }, "down scales them, to 0.5 at least"),
    kit.Capture("font_small"),
    kit.Wait(1),
}
