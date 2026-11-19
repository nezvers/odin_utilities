#+private file
package demo_common

// Rich text with effects (the tags of font/rich.odin), the Slug method on the left and the Scanline Sweeper on the right: styles, outline and shadow, wave, shake, rainbow, pulse, tornado and fade,
// a typewriter, a custom effect and the box that a missing character is drawn as. Space pauses the time. The script checks the parse, the layout and the effects at a few times.

import "core:fmt"
import "core:math"
import kit "../../demo_kit"
import font "../"

FIRA :: #load("../../assets/fonts/FiraCode-Regular.ttf")

TITLE :: "[b]Rich[/b] [i]text[/i] [color=#ffb347]with[/color] [outline size=1 color=#000000][color=#8be9fd]effects[/color][/outline]"
BODY :: "[u]underline[/u]  [s]strike[/s]  [bgcolor=#44558899]background[/bgcolor]  [shadow x=2 y=2]shadow[/shadow]\n" +
    "[wave amp=5 freq=4]wavy words[/wave]  [shake rate=15 level=1]shaking[/shake]  [tornado radius=4 freq=1]tornado[/tornado]\n" +
    "[rainbow freq=0.5]rainbow colors go round[/rainbow]  [pulse freq=1 color=#ff3366ff]pulse[/pulse]\n" +
    "[fade start=2 length=10]this text fades out toward its end[/fade]\n" +
    "[size=30]big[/size] and [size=12]small[/size] on one line, [bounce a=6]a custom bounce[/bounce]\n" +
    "[center]centered[/center]\n" +
    "Missing: ᚠ ☃ (boxes with a cross)"
TYPEWRITER :: "[color=#a6e22e]A typewriter shows one letter at a time, then the rest.[/color]"

Block :: struct {
    glyphs: [768]font.RichGlyph,
    styles: [96]font.RichStyle,
    lines: [32]font.RichLine,
    rich: font.RichText,
}

@(private="package")
demo_rich: kit.Demo = {
    name = "rich",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

loaded: bool
face: font.Font
title, body, typewriter: Block
custom: [1]font.RichCustomEffect
paused: bool
clock: f32
requests: [6]RichRequest

bounce :: proc(state: ^font.RichGlyphState, index: int, run_index: int, time: f32, params: [4]f32, user: rawptr) {
    state.offset.y -= abs(math.sin(time * 3 + f32(run_index) * 0.5)) * params[0]
}

prepare :: proc(block: ^Block, markup: string, size: f32, wrap: f32) -> bool {
    font.RichInit(&block.rich, block.glyphs[:], block.styles[:], block.lines[:], custom[:])
    return font.RichParse(&block.rich, markup) && font.RichLayout(&block.rich, &face, size, wrap)
}

init :: proc(ctx: ^kit.Context) {
    ctx.background = {24, 26, 32, 255}
    loaded = font.FontInit(&face, FIRA)
    custom = {{name = "bounce", apply = bounce}}
    paused = false
    clock = 0
    if loaded {
        loaded = prepare(&title, TITLE, 26, 0) && prepare(&body, BODY, 16, 590) && prepare(&typewriter, TYPEWRITER, 16, 0)
    }
}

update :: proc(ctx: ^kit.Context) {
    if kit.KeyPressed(&ctx.input, .SPACE) { paused = !paused }
    if !paused { clock += 1.0 / 60 }
}

draw :: proc(ctx: ^kit.Context) {
    kit.DrawRect(ctx, {ctx.screen.x * 0.5 - 1, 10, 2, ctx.screen.y - 20}, {70, 74, 86, 255})
    kit.DrawText(ctx, fmt.tprintf("time %.2f   Space: pause", clock), {20, 12}, 14, {150, 156, 170, 255})
    if !loaded { return }
    count: int
    for method in font.Method {
        x: f32 = 20 if method == .SLUG else ctx.screen.x * 0.5 + 20
        requests[count] = {&title.rich, {x, 40}, clock, {}, method}
        count += 1
        requests[count] = {&body.rich, {x, 100}, clock, {}, method}
        count += 1
        requests[count] = {&typewriter.rich, {x, 400}, clock, {typewriter = true, visible_characters = int(clock * 14)}, method}
        count += 1
    }
    if rich_drawer != nil { rich_drawer(ctx, &face, requests[:count]) }
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return loaded && body.rich.unknown_tags == 0 && body.rich.line_count == 7 }, "the markup is parsed and laid out in seven lines"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return body.rich.missing == 2 }, "the two characters that the font lacks are counted"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return body.rich.size.x <= 590.01 && title.rich.size.x > 200 }, "the body wraps at its width"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        // the wave of the first letter of "wavy": moves with the time
        first: int
        for glyph, i in body.rich.glyphs[:body.rich.glyph_count] {
            if glyph.character == 'w' && body.rich.styles[glyph.style].effect_count > 0 && body.rich.styles[glyph.style].effects[0].kind == .WAVE { first = i; break }
        }
        return abs(font.RichGlyphStateAt(&body.rich, first, 0).offset.y) < 0.001 && abs(font.RichGlyphStateAt(&body.rich, first, 0.25).offset.y) > 1
    }, "the wave moves a glyph with the time"),
    kit.Wait(40),
    kit.Capture("rich_start"),
    kit.Wait(1),
    kit.Tap(.SPACE),
    kit.Wait(90),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return paused && clock < 3 }, "space pauses the time"),
    kit.Tap(.SPACE),
    kit.Wait(60),
    kit.Capture("rich_later"),
    kit.Wait(1),
}
