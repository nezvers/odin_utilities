package font

// Two glyphs that the library draws itself, numbered after the glyphs of the font:
//  - GlyphMissing: what is drawn for a character that the font does not have. It is a box with a cross in it, so that a missing character cannot be taken for a space or for the empty "missing
//    glyph" that some fonts have, and a test (or a person) sees it at once. The layout colors it with `TextOptions.missing_color` (magenta unless told otherwise) and counts them.
//  - GlyphSolid: a square much bigger than any text. A quad of it with em coordinates that fit its size is a filled rectangle with anti-aliased edges, drawn by the same shader in the same batch:
//    underlines, strike-through and backgrounds of rich text are made of it.

SPECIAL_GLYPHS :: 2

GlyphMissing :: proc(font: ^Font) -> int {
    return font.glyph_count
}

GlyphSolid :: proc(font: ^Font) -> int {
    return font.glyph_count + 1
}

// The number of entries the table of slots of an atlas needs: the glyphs of the font and the two special ones
FontSlotCount :: proc(font: ^Font) -> int {
    return font.glyph_count + SPECIAL_GLYPHS
}

MISSING_ADVANCE :: f32(0.6)
SOLID_EXTENT :: f32(100)        // em units: the solid square goes from minus this to plus this on both axes

// The glyph for a character: the glyph of the font, or GlyphMissing when the font has none
FontResolve :: proc(font: ^Font, character: rune) -> int {
    glyph: int = FontGlyph(font, character)
    if glyph == 0 { return GlyphMissing(font) }
    return glyph
}

// Does the font have a glyph for the character?
FontHasGlyph :: proc(font: ^Font, character: rune) -> bool {
    return FontGlyph(font, character) != 0
}

// How many characters of a text the font cannot draw
FontCountMissing :: proc(font: ^Font, text: string) -> (count: int) {
    i: int
    for i < len(text) {
        character, size := fontNext(text, i)
        if character != '\n' && character != '\t' && !FontHasGlyph(font, character) { count += 1 }
        i += size
    }
    return
}

@(private)
specialBox :: proc(font: ^Font, glyph: int) -> (low: Vec2, high: Vec2, ok: bool) {
    if glyph == GlyphMissing(font) { return {0.05, 0}, {0.55, 0.72}, true }
    if glyph == GlyphSolid(font) { return {-SOLID_EXTENT, -SOLID_EXTENT}, {SOLID_EXTENT, SOLID_EXTENT}, true }
    return
}

@(private)
polygonCurves :: proc(out: []Curve, count: ^int, points: []Vec2) -> bool {
    for i in 0 ..< len(points) {
        if count^ >= len(out) { return false }
        a: Vec2 = points[i]
        b: Vec2 = points[(i + 1) % len(points)]
        out[count^] = {a, (a + b) * 0.5, b}
        count^ += 1
    }
    return true
}

// The curves of a special glyph (clockwise outer contours, a hole the other way round)
@(private)
specialCurves :: proc(font: ^Font, glyph: int, out: []Curve) -> (count: int, ok: bool) {
    if glyph == GlyphSolid(font) {
        e: f32 = SOLID_EXTENT
        ok = polygonCurves(out, &count, {{-e, -e}, {-e, e}, {e, e}, {e, -e}})
        return
    }
    // the box (a ring) and the two strokes of the cross
    ok = polygonCurves(out, &count, {{0.05, 0}, {0.05, 0.72}, {0.55, 0.72}, {0.55, 0}})
    ok = polygonCurves(out, &count, {{0.10, 0.05}, {0.50, 0.05}, {0.50, 0.67}, {0.10, 0.67}}) && ok
    ok = polygonCurves(out, &count, {{0.10, 0.05}, {0.43, 0.67}, {0.50, 0.67}, {0.17, 0.05}}) && ok
    ok = polygonCurves(out, &count, {{0.43, 0.05}, {0.10, 0.67}, {0.17, 0.67}, {0.50, 0.05}}) && ok
    return
}
