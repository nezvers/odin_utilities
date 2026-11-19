#+build !js
package font

import "core:testing"

@(private = "file")
loadFont :: proc() -> ^Font {
    font: ^Font = new(Font)
    assert(FontInit(font, FIRA))
    return font
}

@(test)
test_a_character_the_font_lacks_is_drawn_as_a_box_with_a_cross_in_its_own_color_and_counted :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    // a rune that Fira Code does not have
    lacking: rune = 0x16A0
    testing.expect(t, !FontHasGlyph(font, lacking) && FontHasGlyph(font, 'a'))
    testing.expect_value(t, FontCountMissing(font, "aᚠbᚠ\n"), 2)
    testing.expect_value(t, FontResolve(font, lacking), GlyphMissing(font))
    testing.expect(t, abs(FontAdvance(font, GlyphMissing(font)) - MISSING_ADVANCE) < 0.0001)
    texels: []f32 = make([]f32, 4 * ATLAS_WIDTH * 4)
    slots: []i32 = make([]i32, FontSlotCount(font))
    defer { delete(texels); delete(slots) }
    atlas: Atlas
    AtlasInit(&atlas, font, .SLUG, texels, slots)
    vertices: [64]TextVertex
    count, pen, complete, missing := TextQuads(&atlas, "aᚠ", {0, 0}, 20, vertices[:], {}, 3)
    testing.expect(t, complete)
    testing.expect_value(t, missing, 1)
    testing.expect_value(t, count, 2 * TEXT_VERTICES_PER_GLYPH)                    // the letter and the box
    testing.expect_value(t, vertices[0].color, u8(3))                               // the letter has the color it was asked for
    testing.expect(t, vertices[TEXT_VERTICES_PER_GLYPH].color != 3, "the box has a color of its own")
    magenta: [4]u8 = atlas.palette[vertices[TEXT_VERTICES_PER_GLYPH].color]
    testing.expect_value(t, magenta, [4]u8{255, 0, 255, 255})
    testing.expect(t, abs(pen.x - (FontAdvance(font, FontGlyph(font, 'a')) + MISSING_ADVANCE) * 20) < 0.01)
    // another color on request
    TextQuads(&atlas, "ᚠ", {0, 0}, 20, vertices[:], {missing_color = {255, 128, 0, 255}})
    testing.expect_value(t, atlas.palette[vertices[0].color], [4]u8{255, 128, 0, 255})
    // the box is a ring with a cross: its coverage says so
    slot, _ := AtlasGlyph(&atlas, GlyphMissing(font))
    ppem: Vec2 = {100, 100}
    testing.expect(t, SlugCoverage(&atlas, slot, {0.075, 0.36}, ppem) > 0.99, "the left side of the ring")
    testing.expect(t, SlugCoverage(&atlas, slot, {0.30, 0.36}, ppem) > 0.99, "where the strokes cross")
    testing.expect(t, SlugCoverage(&atlas, slot, {0.30, 0.10}, ppem) < 0.01, "the hole between the strokes")
    testing.expect(t, SlugCoverage(&atlas, slot, {0.70, 0.36}, ppem) < 0.01, "outside")
    // a text that the font can draw has none
    _, _, _, none := TextQuads(&atlas, "plain", {}, 20, vertices[:])
    testing.expect_value(t, none, 0)
}

@(test)
test_a_filled_rectangle_is_a_quad_of_the_solid_glyph :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    texels: []f32 = make([]f32, 4 * ATLAS_WIDTH * 4)
    slots: []i32 = make([]i32, FontSlotCount(font))
    defer { delete(texels); delete(slots) }
    atlas: Atlas
    AtlasInit(&atlas, font, .SCANLINE, texels, slots)
    vertices: [6]TextVertex
    count, ok := EmitRect(&atlas, {10, 20, 50, 2}, 4, 200, TextTurnMake({100, 100}, 0), vertices[:])
    testing.expect(t, ok && count == 6)
    low, high: Vec2 = {1e9, 1e9}, {-1e9, -1e9}
    for vertex in vertices {
        low = {min(low.x, vertex.position.x), min(low.y, vertex.position.y)}
        high = {max(high.x, vertex.position.x), max(high.y, vertex.position.y)}
        testing.expect(t, vertex.color == 4 && vertex.alpha == 200 && abs(vertex.uv.x) < SOLID_EXTENT && abs(vertex.uv.y) < SOLID_EXTENT)
    }
    testing.expect_value(t, low, Vec2{110, 120})
    testing.expect_value(t, high, Vec2{160, 122})
    // the glyph under the quad is covered everywhere in it
    slot, _ := AtlasGlyph(&atlas, GlyphSolid(font))
    testing.expect_value(t, ScanlineCoverage(&atlas, slot, {0.1, 0.01}, {0.005, 0.005}), 1)
    testing.expect_value(t, ScanlineCoverage(&atlas, slot, {-0.2, -0.01}, {0.005, 0.005}), 1)
}
