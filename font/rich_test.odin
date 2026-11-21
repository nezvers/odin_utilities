#+build !js
#+build !arm64
package font

import "core:testing"

@(private = "file")
Rig :: struct {
    font: Font,
    glyphs: [256]RichGlyph,
    styles: [64]RichStyle,
    lines: [32]RichLine,
    rich: RichText,
    texels: []f32,
    slots: []i32,
    atlas: Atlas,
    vertices: [4096]TextVertex,
}

@(private = "file")
makeRig :: proc(custom: []RichCustomEffect = nil) -> ^Rig {
    rig: ^Rig = new(Rig)
    assert(FontInit(&rig.font, FIRA))
    rig.texels = make([]f32, 4 * ATLAS_WIDTH * 8)
    rig.slots = make([]i32, FontSlotCount(&rig.font))
    AtlasInit(&rig.atlas, &rig.font, .SLUG, rig.texels, rig.slots)
    RichInit(&rig.rich, rig.glyphs[:], rig.styles[:], rig.lines[:], custom)
    return rig
}

@(private = "file")
freeRig :: proc(rig: ^Rig) {
    delete(rig.texels)
    delete(rig.slots)
    free(rig)
}

@(test)
test_tags_become_styles_of_the_glyphs_they_enclose_and_nest :: proc(t: ^testing.T) {
    rig: ^Rig = makeRig()
    defer freeRig(rig)
    ok: bool = RichParse(&rig.rich, "a[b]b[i]c[/i]d[/b][color=#ff8000]e[/color][size=30]f[/size]g")
    testing.expect(t, ok)
    testing.expect_value(t, rig.rich.glyph_count, 7)
    testing.expect_value(t, rig.rich.unknown_tags, 0)
    style :: proc(rig: ^Rig, index: int) -> RichStyle { return rig.styles[rig.glyphs[index].style] }
    testing.expect(t, !style(rig, 0).bold && !style(rig, 0).italic)
    testing.expect(t, style(rig, 1).bold && !style(rig, 1).italic, "b is bold")
    testing.expect(t, style(rig, 2).bold && style(rig, 2).italic, "c is bold and italic")
    testing.expect(t, style(rig, 3).bold && !style(rig, 3).italic, "after the closing i")
    testing.expect(t, !style(rig, 4).bold, "e is plain")
    testing.expect_value(t, style(rig, 4).color, [4]u8{255, 128, 0, 255})
    testing.expect_value(t, style(rig, 5).size, 30)
    testing.expect_value(t, style(rig, 6).size, 0)
    testing.expect_value(t, style(rig, 6).color, [4]u8{255, 255, 255, 255})
    // a glyph that follows another with the same style shares its entry
    testing.expect_value(t, rig.glyphs[0].style, rig.glyphs[0].style)
    RichParse(&rig.rich, "abc")
    testing.expect_value(t, rig.rich.style_count, 1)
}

@(test)
test_tags_that_are_not_known_or_not_closed_are_shown_and_counted :: proc(t: ^testing.T) {
    rig: ^Rig = makeRig()
    defer freeRig(rig)
    RichParse(&rig.rich, "x[nope]y[/b]z[lb]w[color=pink]q")
    testing.expect_value(t, rig.rich.unknown_tags, 2)                              // [nope], and [/b] without an open b ([color=pink] is a color tag with a value that is not a color: the color stays)
    text: [64]u8
    for i in 0 ..< rig.rich.glyph_count { text[i] = u8(rig.glyphs[i].character) }
    testing.expect_value(t, string(text[:rig.rich.glyph_count]), "x[nope]y[/b]z[wq")
}

@(test)
test_a_text_is_laid_out_in_lines_that_wrap_align_and_measure :: proc(t: ^testing.T) {
    rig: ^Rig = makeRig()
    defer freeRig(rig)
    advance: f32 = FontAdvance(&rig.font, FontGlyph(&rig.font, 'a'))
    RichParse(&rig.rich, "aaaa bbbb cc\nd")
    testing.expect(t, RichLayout(&rig.rich, &rig.atlas.faces, 10, 0))
    testing.expect_value(t, rig.rich.line_count, 2)
    testing.expect(t, abs(rig.rich.size.x - 12 * advance * 10) < 0.01, "the widest line")
    testing.expect(t, rig.rich.size.y > 2 * 10, "two lines are taller than two ems")
    testing.expect(t, rig.glyphs[rig.rich.lines[1].first].baseline > rig.glyphs[0].baseline, "the second line is lower")
    // wrapped at 5.5 characters: three lines of words, and a fourth for the last line
    RichLayout(&rig.rich, &rig.atlas.faces, 10, 5.5 * advance * 10)
    testing.expect_value(t, rig.rich.line_count, 4)
    testing.expect(t, rig.rich.size.x <= 5.5 * advance * 10 + 0.01)
    // alignment: a centered line is in the middle of the room
    RichParse(&rig.rich, "[center]ab[/center]")
    RichLayout(&rig.rich, &rig.atlas.faces, 10, 100)
    testing.expect(t, abs(rig.glyphs[0].x - (100 - 2 * advance * 10) * 0.5) < 0.01)
    RichParse(&rig.rich, "[right]ab[/right]")
    RichLayout(&rig.rich, &rig.atlas.faces, 10, 100)
    testing.expect(t, abs(rig.glyphs[0].x - (100 - 2 * advance * 10)) < 0.01)
    // glyphs of another size sit on the same baseline and make the line taller
    RichParse(&rig.rich, "a[size=30]b[/size]c")
    RichLayout(&rig.rich, &rig.atlas.faces, 10)
    testing.expect_value(t, rig.glyphs[0].baseline, rig.glyphs[1].baseline)
    testing.expect(t, rig.rich.size.y > 30)
    // the characters that the font lacks are counted
    RichParse(&rig.rich, "aᚠb")
    RichLayout(&rig.rich, &rig.atlas.faces, 10)
    testing.expect_value(t, rig.rich.missing, 1)
}

@(test)
test_effects_move_and_color_glyphs_with_the_time :: proc(t: ^testing.T) {
    rig: ^Rig = makeRig()
    defer freeRig(rig)
    RichParse(&rig.rich, "ab[wave amp=10 freq=2]cdef[/wave][fade start=1 length=2]ghij[/fade][tornado radius=5 freq=1]k[/tornado]")
    RichLayout(&rig.rich, &rig.atlas.faces, 20)
    // wave: the offset follows a sine of the time, a little different for each glyph
    first: RichGlyphState = RichGlyphStateAt(&rig.rich, 2, 0)
    testing.expect(t, abs(first.offset.y) < 0.0001)
    later: RichGlyphState = RichGlyphStateAt(&rig.rich, 2, 0.25)
    testing.expect(t, abs(later.offset.y - 10 * 0.479426) < 0.01, "sin(0.5) times the amplitude")
    next: RichGlyphState = RichGlyphStateAt(&rig.rich, 3, 0)
    testing.expect(t, next.offset.y > 3 && next.offset.y < 7, "the next glyph is a step ahead in the wave")
    testing.expect_value(t, RichGlyphStateAt(&rig.rich, 0, 1).offset, Vec2{})      // glyphs outside of a tag are not moved
    // fade: the second glyph of the tag (run 1) is still whole, then it falls to nothing over two glyphs
    testing.expect_value(t, RichGlyphStateAt(&rig.rich, 6, 0).alpha, 1)
    testing.expect_value(t, RichGlyphStateAt(&rig.rich, 7, 0).alpha, 1)
    testing.expect(t, abs(RichGlyphStateAt(&rig.rich, 8, 0).alpha - 0.5) < 0.001)
    testing.expect_value(t, RichGlyphStateAt(&rig.rich, 9, 0).alpha, 0)
    // tornado: a circle of the radius
    for time in ([?]f32{0, 0.3, 0.7}) {
        state: RichGlyphState = RichGlyphStateAt(&rig.rich, 10, time)
        testing.expect(t, abs(state.offset.x * state.offset.x + state.offset.y * state.offset.y - 25) < 0.01)
    }
    // shake: the same at one time, another at the next tick
    RichParse(&rig.rich, "[shake rate=10 level=4]xyz[/shake]")
    RichLayout(&rig.rich, &rig.atlas.faces, 20)
    testing.expect_value(t, RichGlyphStateAt(&rig.rich, 1, 0.01).offset, RichGlyphStateAt(&rig.rich, 1, 0.05).offset)
    testing.expect(t, RichGlyphStateAt(&rig.rich, 1, 0.01).offset != RichGlyphStateAt(&rig.rich, 1, 0.15).offset)
    state: RichGlyphState = RichGlyphStateAt(&rig.rich, 2, 0.5)
    testing.expect(t, abs(state.offset.x) <= 4 && abs(state.offset.y) <= 4)
    // rainbow: a color that moves with the time, and only a few different ones
    RichParse(&rig.rich, "[rainbow freq=1]abcdefgh[/rainbow]")
    RichLayout(&rig.rich, &rig.atlas.faces, 20)
    testing.expect(t, RichGlyphStateAt(&rig.rich, 0, 0).color != RichGlyphStateAt(&rig.rich, 0, 0.3).color)
    testing.expect(t, RichGlyphStateAt(&rig.rich, 0, 0).color != RichGlyphStateAt(&rig.rich, 4, 0).color)
    // pulse: the color goes to the pulse color and back
    RichParse(&rig.rich, "[pulse freq=1 color=#000000ff]a[/pulse]")
    RichLayout(&rig.rich, &rig.atlas.faces, 20)
    testing.expect_value(t, RichGlyphStateAt(&rig.rich, 0, 0.25).color, [4]u8{0, 0, 0, 255})
    testing.expect_value(t, RichGlyphStateAt(&rig.rich, 0, 0.75).color, [4]u8{255, 255, 255, 255})
}

@(test)
test_a_custom_effect_is_called_with_the_run_and_the_numbers_of_its_tag :: proc(t: ^testing.T) {
    @(static) seen_run: int
    @(static) seen_param: f32
    seen_run, seen_param = -1, 0
    custom: [1]RichCustomEffect = {{name = "bounce", apply = proc(state: ^RichGlyphState, index: int, run_index: int, time: f32, params: [4]f32, user: rawptr) {
        seen_run = run_index
        seen_param = params[0]
        state.offset.y -= params[0] * time
        state.scale = 1.5
    }}}
    rig: ^Rig = makeRig(custom[:])
    defer freeRig(rig)
    RichParse(&rig.rich, "a[bounce a=3]bc[/bounce]")
    RichLayout(&rig.rich, &rig.atlas.faces, 20)
    state: RichGlyphState = RichGlyphStateAt(&rig.rich, 2, 2)
    testing.expect_value(t, seen_run, 1)
    testing.expect_value(t, seen_param, 3)
    testing.expect(t, abs(state.offset.y + 6) < 0.001 && state.scale == 1.5)
}

@(test)
test_rich_text_is_drawn_with_a_typewriter_decorations_outline_and_the_missing_box :: proc(t: ^testing.T) {
    rig: ^Rig = makeRig()
    defer freeRig(rig)
    count_for :: proc(rig: ^Rig, markup: string, options: RichDrawOptions = {}) -> RichDrawResult {
        RichParse(&rig.rich, markup)
        RichLayout(&rig.rich, &rig.atlas.faces, 20)
        return RichDraw(&rig.atlas, &rig.rich, {10, 10}, 0, rig.vertices[:], options)
    }
    plain := count_for(rig, "abc")
    testing.expect(t, plain.complete)
    testing.expect_value(t, plain.count, 3 * TEXT_VERTICES_PER_GLYPH)
    testing.expect_value(t, count_for(rig, "abc", {typewriter = true, visible_characters = 2}).count, 2 * TEXT_VERTICES_PER_GLYPH)
    testing.expect_value(t, count_for(rig, "abc", {typewriter = true, visible_characters = 0}).count, 0)
    testing.expect_value(t, count_for(rig, "[b]ab[/b]").count, 4 * TEXT_VERTICES_PER_GLYPH)               // bold: struck twice
    testing.expect_value(t, count_for(rig, "[u]ab[/u]").count, 4 * TEXT_VERTICES_PER_GLYPH)               // a rectangle under each
    testing.expect_value(t, count_for(rig, "[s]ab[/s]").count, 4 * TEXT_VERTICES_PER_GLYPH)
    testing.expect_value(t, count_for(rig, "[outline size=1]a[/outline]").count, 9 * TEXT_VERTICES_PER_GLYPH)  // eight around it and the glyph
    testing.expect_value(t, count_for(rig, "[shadow]a[/shadow]").count, 2 * TEXT_VERTICES_PER_GLYPH)
    testing.expect_value(t, count_for(rig, "[bgcolor=red]a[/bgcolor]").count, 2 * TEXT_VERTICES_PER_GLYPH)
    // the italic is a slant: the top of the quad is to the right of its bottom
    count_for(rig, "[i]H[/i]")
    testing.expect(t, rig.vertices[2].position.x - rig.vertices[1].position.x > 2, "the top right corner is right of the bottom right one")
    count_for(rig, "H")
    testing.expect(t, abs(rig.vertices[2].position.x - rig.vertices[1].position.x) < 0.01)
    // the fade goes into the vertices, the effect offset moves the quad
    count_for(rig, "[fade start=0 length=2]ab[/fade]")
    testing.expect_value(t, rig.vertices[0].alpha, u8(255))
    testing.expect_value(t, rig.vertices[TEXT_VERTICES_PER_GLYPH].alpha, u8(128))
    // a character the font lacks: the box, magenta, and counted by the layout
    count_for(rig, "aᚠ")
    testing.expect_value(t, rig.rich.missing, 1)
    testing.expect_value(t, rig.atlas.palette[rig.vertices[TEXT_VERTICES_PER_GLYPH].color], [4]u8{255, 0, 255, 255})
    // not enough room: the glyphs that were drawn are whole and it says it is not complete
    small: [8]TextVertex
    RichParse(&rig.rich, "abcdefg")
    RichLayout(&rig.rich, &rig.atlas.faces, 20)
    cut := RichDraw(&rig.atlas, &rig.rich, {}, 0, small[:])
    testing.expect(t, !cut.complete)
}

@(test)
test_a_rainbow_uses_a_few_colors_of_the_palette_and_a_full_palette_is_told :: proc(t: ^testing.T) {
    rig: ^Rig = makeRig()
    defer freeRig(rig)
    RichParse(&rig.rich, "[rainbow]abcdefghijklmnopqrstuvwxyzabcdefghijklmnop[/rainbow]")
    RichLayout(&rig.rich, &rig.atlas.faces, 20)
    for frame in 0 ..< 20 {
        result := RichDraw(&rig.atlas, &rig.rich, {}, f32(frame) * 0.07, rig.vertices[:])
        testing.expect(t, result.complete)
    }
    testing.expect(t, rig.atlas.palette_count <= 24, "the hues are quantized")
    // a palette that is full: the draw stops and says why
    for i in 0 ..< ATLAS_PALETTE { AtlasColor(&rig.atlas, {u8(i), 9, 9, 9}) }
    RichParse(&rig.rich, "[color=#123456]abc")
    RichLayout(&rig.rich, &rig.atlas.faces, 20)
    result := RichDraw(&rig.atlas, &rig.rich, {}, 1.234, rig.vertices[:])
    testing.expect(t, !result.complete && result.palette_full)
}
