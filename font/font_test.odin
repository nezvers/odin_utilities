#+build !js
#+build !arm64
package font

import "core:c"
import "core:testing"
import stbtt "vendor:stb/truetype"

FIRA :: #load("../assets/fonts/FiraCode-Regular.ttf")

@(private = "file")
loadFont :: proc() -> ^Font {
    font: ^Font = new(Font)
    assert(FontInit(font, FIRA))
    return font
}

@(test)
test_font_metrics_are_in_em_units :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    testing.expect(t, font.units_per_em >= 500 && font.units_per_em <= 4096)
    testing.expect(t, font.ascent > 0.5 && font.ascent < 1.5, "the ascent is a bit under or over an em")
    testing.expect(t, font.descent < 0 && font.descent > -0.6)
    glyph: int = FontGlyph(font, 'H')
    testing.expect(t, glyph > 0)
    testing.expect(t, FontGlyph(font, 'H') != FontGlyph(font, 'i'))
    advance: f32 = FontAdvance(font, glyph)
    testing.expect(t, advance > 0.4 && advance < 0.8, "a letter of a monospace font is about 0.6 em wide")
    testing.expect(t, abs(FontAdvance(font, FontGlyph(font, 'i')) - advance) < 0.001, "and every letter is as wide")
    low, high, ok := FontGlyphBox(font, glyph)
    testing.expect(t, ok && low.x >= 0 && high.x <= advance + 0.1 && high.y > 0.5 && high.y < 0.9, "the cap height")
    _, _, has_box := FontGlyphBox(font, FontGlyph(font, ' '))
    testing.expect(t, !has_box, "a space has no outline")
    testing.expect(t, FontLineHeight(font) > 1)
}

@(test)
test_the_curves_of_a_glyph_are_closed_contours_and_monotonic_pieces_keep_the_shape :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    curves: [256]Curve
    count, ok := FontGlyphCurves(font, FontGlyph(font, 'g'), curves[:])
    testing.expect(t, ok && count > 8)
    pieces: [768]Curve
    piece_count, pieces_ok := CurvesMonotonic(curves[:count], pieces[:])
    testing.expect(t, pieces_ok && piece_count >= count)
    for piece in pieces[:piece_count] {
        // one way along each axis: the control point is between the ends (up to a rounding)
        for axis in 0 ..< 2 {
            low: f32 = min(piece.p0[axis], piece.p2[axis]) - 0.0005
            high: f32 = max(piece.p0[axis], piece.p2[axis]) + 0.0005
            testing.expect(t, piece.p1[axis] >= low && piece.p1[axis] <= high, "monotonic")
        }
    }
    // the pieces end where the curve they come from ends
    testing.expect_value(t, pieces[0].p0, curves[0].p0)
    testing.expect_value(t, pieces[piece_count - 1].p2, curves[count - 1].p2)
    // a buffer that is too small is told
    small: [4]Curve
    _, small_ok := FontGlyphCurves(font, FontGlyph(font, 'g'), small[:])
    testing.expect(t, !small_ok)
    // no outline: no curves
    none, none_ok := FontGlyphCurves(font, FontGlyph(font, ' '), curves[:])
    testing.expect(t, none_ok && none == 0)
}

// The bitmap of stb_truetype for a glyph, and ours at the same place: they agree up to the way the edges are filtered
@(private = "file")
compare :: proc(font: ^Font, character: rune, pixels_per_em: f32) -> (mean: f32, worst: int) {
    glyph: int = FontGlyph(font, character)
    // stb_truetype reads the file on its own: it is the second opinion here, the library does not use it
    padded: StbInfo                 // parser_test.odin: the struct of the binding is too short
    info: ^stbtt.fontinfo = &padded.info
    assert(bool(stbtt.InitFont(info, raw_data(font.data), 0)))
    scale: f32 = stbtt.ScaleForMappingEmToPixels(info, pixels_per_em)
    x0, y0, x1, y1: c.int
    stbtt.GetGlyphBitmapBox(info, c.int(glyph), scale, scale, &x0, &y0, &x1, &y1)
    width, height: int = int(x1 - x0), int(y1 - y0)
    reference: [64 * 64]u8
    stbtt.MakeGlyphBitmap(info, raw_data(reference[:]), c.int(width), c.int(height), c.int(width), scale, scale, c.int(glyph))
    curves: [256]Curve
    count, _ := FontGlyphCurves(font, glyph, curves[:])
    pieces: [768]Curve
    piece_count, _ := CurvesMonotonic(curves[:count], pieces[:])
    ours: [64 * 64]u8
    CurvesRasterize(pieces[:piece_count], pixels_per_em, {f32(-x0), f32(-y0)}, ours[:], width, height)
    sum: int
    for i in 0 ..< width * height {
        difference: int = abs(int(ours[i]) - int(reference[i]))
        sum += difference
        worst = max(worst, difference)
    }
    return f32(sum) / f32(width * height), worst
}

@(test)
test_the_exact_coverage_matches_the_bitmap_of_stb_truetype :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    for character in ([?]rune{'H', 'o', 'g', 'e', '@', 'W', 'i', '8'}) {
        mean, worst := compare(font, character, 28)
        // stb_truetype flattens the curves to 0.35 of a pixel, so the two are close and not the same: the difference is the proof that the size, the place and the direction are right
        testing.expectf(t, mean < 14, "%c: the mean difference is %v of 255", character, mean)
        testing.expectf(t, worst < 120, "%c: the worst pixel is off by %v", character, worst)
    }
}

@(test)
test_a_window_inside_and_outside_of_a_shape_is_full_and_empty :: proc(t: ^testing.T) {
    // a square from 0.2 to 0.8, clockwise
    square: [4]Curve = {
        {{0.2, 0.2}, {0.2, 0.5}, {0.2, 0.8}},
        {{0.2, 0.8}, {0.5, 0.8}, {0.8, 0.8}},
        {{0.8, 0.8}, {0.8, 0.5}, {0.8, 0.2}},
        {{0.8, 0.2}, {0.5, 0.2}, {0.2, 0.2}},
    }
    testing.expect_value(t, CurvesCoverage(square[:], {0.4, 0.4}, {0.5, 0.5}), 1)
    testing.expect(t, abs(CurvesCoverage(square[:], {0.9, 0.4}, {0.95, 0.5})) < 1e-5, "right of the shape: the two sides cancel")
    testing.expect_value(t, CurvesCoverage(square[:], {0.0, 0.0}, {0.1, 0.1}), 0)
    // half of the window is over the edge
    half: f32 = CurvesCoverage(square[:], {0.15, 0.4}, {0.25, 0.5})
    testing.expect(t, abs(half - 0.5) < 0.001, "an edge in the middle covers half")
    corner: f32 = CurvesCoverage(square[:], {0.15, 0.15}, {0.25, 0.25})
    testing.expect(t, abs(corner - 0.25) < 0.001, "a corner covers a quarter")
    // the same square the other way round
    reverse: [4]Curve
    for i in 0 ..< 4 {
        curve: Curve = square[3 - i]
        reverse[i] = {curve.p2, curve.p1, curve.p0}
    }
    testing.expect(t, abs(CurvesCoverage(reverse[:], {0.15, 0.4}, {0.25, 0.5}) - 0.5) < 0.001, "the direction of the contour does not matter")
}

// A slow and plain second opinion: the curves cut into small straight pieces and a grid of points per pixel with the nonzero winding rule
@(private = "file")
supersample :: proc(curves: []Curve, pixels_per_em: f32, origin: Vec2, width: int, height: int, out: []u8) {
    segments: [dynamic][2]Vec2
    defer delete(segments)
    for curve in curves {
        previous: Vec2 = curve.p0
        for i in 1 ..= 24 {
            current: Vec2 = CurveAt(curve, f32(i) / 24)
            append(&segments, [2]Vec2{previous, current})
            previous = current
        }
    }
    samples :: 8
    for row in 0 ..< height {
        for column in 0 ..< width {
            inside: int
            for sy in 0 ..< samples {
                for sx in 0 ..< samples {
                    point: Vec2 = {(f32(column) + (f32(sx) + 0.5) / samples - origin.x) / pixels_per_em, (origin.y - (f32(row) + (f32(sy) + 0.5) / samples)) / pixels_per_em}
                    winding: int
                    for segment in segments {
                        a, b: Vec2 = segment[0], segment[1]
                        if (a.y <= point.y) != (b.y <= point.y) {
                            x: f32 = a.x + (point.y - a.y) / (b.y - a.y) * (b.x - a.x)
                            if x > point.x { winding += 1 if b.y > a.y else -1 }
                        }
                    }
                    if winding != 0 { inside += 1 }
                }
            }
            out[row * width + column] = u8(inside * 255 / (samples * samples))
        }
    }
}

@(test)
test_the_exact_coverage_matches_a_grid_of_points_on_the_flattened_curves :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    for character in ([?]rune{'o', 'g', 'e', '@', '8', 'S', 'R'}) {
        glyph: int = FontGlyph(font, character)
        curves: [256]Curve
        count, _ := FontGlyphCurves(font, glyph, curves[:])
        pieces: [768]Curve
        piece_count, _ := CurvesMonotonic(curves[:count], pieces[:])
        width, height: int = 24, 32
        origin: Vec2 = {3, 22}
        exact: [24 * 32]u8
        grid: [24 * 32]u8
        CurvesRasterize(pieces[:piece_count], 28, origin, exact[:], width, height)
        supersample(curves[:count], 28, origin, width, height, grid[:])
        sum: int
        for i in 0 ..< width * height { sum += abs(int(exact[i]) - int(grid[i])) }
        mean: f32 = f32(sum) / f32(width * height)
        testing.expectf(t, mean < 2.5, "%c: the mean difference to the grid is %v of 255", character, mean)
    }
}

// The data that is made for the GPU, read back by the CPU model of each shader, against the exact coverage of the outline
@(private = "file")
compareAtlas :: proc(font: ^Font, character: rune, method: Method, pixels_per_em: f32) -> (mean: f32, worst: int) {
    texels: []f32 = make([]f32, 4 * ATLAS_WIDTH * 8)
    slots: []i32 = make([]i32, FontSlotCount(font))
    defer { delete(texels); delete(slots) }
    atlas: Atlas
    AtlasInit(&atlas, font, method, texels, slots)
    glyph: int = FontGlyph(font, character)
    slot, ok := AtlasGlyph(&atlas, glyph)
    assert(ok && slot >= 0)
    curves: [256]Curve
    count, _ := FontGlyphCurves(font, glyph, curves[:])
    pieces: [768]Curve
    piece_count, _ := CurvesMonotonic(curves[:count], pieces[:])
    width, height: int = 24, 32
    origin: Vec2 = {3, 22}
    exact: [24 * 32]u8
    CurvesRasterize(pieces[:piece_count], pixels_per_em, origin, exact[:], width, height)
    sum: int
    for row in 0 ..< height {
        for column in 0 ..< width {
            center: Vec2 = {(f32(column) + 0.5 - origin.x) / pixels_per_em, (origin.y - (f32(row) + 0.5)) / pixels_per_em}
            value: f32
            switch method {
            case .SLUG: value = SlugCoverage(&atlas, slot, center, {pixels_per_em, pixels_per_em})
            case .SCANLINE: value = ScanlineCoverage(&atlas, slot, center, {0.5, 0.5} / pixels_per_em)
            }
            difference: int = abs(int(value * 255 + 0.5) - int(exact[row * width + column]))
            sum += difference
            worst = max(worst, difference)
        }
    }
    return f32(sum) / f32(width * height), worst
}

@(test)
test_the_slug_data_read_by_the_slug_model_matches_the_exact_coverage :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    for character in ([?]rune{'H', 'o', 'g', 'e', '@', '8', 'S', 'R', 'W', 'a'}) {
        mean, worst := compareAtlas(font, character, .SLUG, 28)
        testing.expectf(t, mean < 4, "%c: the mean difference is %v of 255", character, mean)
        testing.expectf(t, worst < 140, "%c: the worst pixel is off by %v", character, worst)
    }
}

@(test)
test_the_scanline_data_read_by_the_scanline_model_matches_the_exact_coverage :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    for character in ([?]rune{'H', 'o', 'g', 'e', '@', '8', 'S', 'R', 'W', 'a'}) {
        mean, worst := compareAtlas(font, character, .SCANLINE, 28)
        testing.expectf(t, mean < 0.5, "%c: the mean difference is %v of 255", character, mean)
        testing.expectf(t, worst < 6, "%c: the worst pixel is off by %v", character, worst)
    }
    // small text: a pixel reaches over the border of two stripes
    for character in ([?]rune{'o', 'g', 'e', '@'}) {
        mean, worst := compareAtlas(font, character, .SCANLINE, 7)
        testing.expectf(t, mean < 0.5 && worst < 6, "%c at 7 pixels: %v, %v", character, mean, worst)
    }
}

@(test)
test_an_atlas_bakes_a_glyph_once_says_when_it_is_full_and_has_nothing_for_a_space :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    texels: []f32 = make([]f32, 4 * ATLAS_WIDTH * 4)
    slots: []i32 = make([]i32, FontSlotCount(font))
    defer { delete(texels); delete(slots) }
    atlas: Atlas
    AtlasInit(&atlas, font, .SLUG, texels, slots)
    a, ok := AtlasGlyph(&atlas, FontGlyph(font, 'a'))
    testing.expect(t, ok && a == 0)
    again, _ := AtlasGlyph(&atlas, FontGlyph(font, 'a'))
    testing.expect_value(t, again, 0)
    used: int = atlas.used
    AtlasGlyph(&atlas, FontGlyph(font, 'a'))
    testing.expect_value(t, atlas.used, used)                    // baked once
    space, space_ok := AtlasGlyph(&atlas, FontGlyph(font, ' '))
    testing.expect(t, space_ok && space == -1)
    dirty := AtlasTakeDirty(&atlas)
    testing.expect(t, dirty[0] == RowRange{0, 1}, "the table")
    testing.expect(t, dirty[1] == RowRange{1, 1}, "the palette (it starts dirty)")
    testing.expect(t, dirty[2].first == 2 && dirty[2].count >= 1, "and the data")
    none := AtlasTakeDirty(&atlas)
    testing.expect(t, none[0].count == 0 && none[1].count == 0 && none[2].count == 0, "nothing changed since")
    AtlasGlyph(&atlas, FontGlyph(font, 'b'))
    later := AtlasTakeDirty(&atlas)
    testing.expect(t, later[0].count == 1 && later[2].count >= 1, "a new glyph writes a slot of the table too")
    // an atlas that is full: the glyphs that fit are in, the others are told
    failed: bool
    for glyph in 0 ..< 400 {
        _, glyph_ok := AtlasGlyph(&atlas, glyph)
        if !glyph_ok { failed = true; break }
    }
    testing.expect(t, failed, "two rows of data cannot hold four hundred glyphs")
    // clearing starts again: the glyphs are baked anew, the slots from 0
    AtlasClear(&atlas)
    again_slot, again_ok := AtlasGlyph(&atlas, FontGlyph(font, 'x'))
    testing.expect(t, again_ok && again_slot == 0)
    testing.expect(t, AtlasReserveText(&atlas, "abc"))
}

@(test)
test_text_becomes_quads_that_sit_on_the_baseline_and_advance_by_the_font :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    texels: []f32 = make([]f32, 4 * ATLAS_WIDTH * 8)
    slots: []i32 = make([]i32, FontSlotCount(font))
    defer { delete(texels); delete(slots) }
    atlas: Atlas
    AtlasInit(&atlas, font, .SLUG, texels, slots)
    vertices: [256]TextVertex
    count, pen, complete, _ := TextQuads(&atlas, "Hi i", {100, 200}, 50, vertices[:])
    testing.expect(t, complete)
    testing.expect_value(t, count, 3 * TEXT_VERTICES_PER_GLYPH)                // the space has no outline
    advance: f32 = FontAdvance(font, FontGlyph(font, 'H'))
    testing.expect(t, abs(pen.x - (100 + 4 * advance * 50)) < 0.01, "four characters of a monospace font")
    testing.expect_value(t, pen.y, 200)
    // the top of an H is above the baseline (smaller y on the screen), the bottom is on it (a margin below)
    top: f32 = 1e9
    bottom: f32 = -1e9
    for vertex in vertices[:TEXT_VERTICES_PER_GLYPH] {
        top = min(top, vertex.position.y)
        bottom = max(bottom, vertex.position.y)
        testing.expect_value(t, vertex.slot, u32(0))
    }
    testing.expect(t, top < 200 - 0.5 * 50 && bottom > 200 && bottom < 202, "above the baseline, one pixel of margin under it")
    // the em coordinates of the corners and the pixels agree: a point at the baseline is at em 0
    for vertex in vertices[:TEXT_VERTICES_PER_GLYPH] {
        testing.expect(t, abs((200 - vertex.position.y) / 50 - vertex.uv.y) < 0.0001)
    }
    // the second letter has its own slot, the third (an i after the space) is the third glyph
    testing.expect_value(t, vertices[TEXT_VERTICES_PER_GLYPH].slot, u32(1))
    // a new line moves the baseline down by a line height
    _, pen_after, _, _ := TextQuads(&atlas, "a\nb", {0, 0}, 10, vertices[:])
    testing.expect(t, abs(pen_after.y - FontLineHeight(font) * 10) < 0.001)
    // not enough room: the text stops and says so
    small: [TEXT_VERTICES_PER_GLYPH]TextVertex
    _, _, fit, _ := TextQuads(&atlas, "abc", {}, 10, small[:])
    testing.expect(t, !fit)
    testing.expect_value(t, SlotColor(0x0203), [4]u8{3, 2, 0, 255})
    testing.expect_value(t, SlotColor(0x0203, 7), [4]u8{3, 2, 7, 255})
}

@(test)
test_text_is_measured_and_wrapped_at_spaces :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    advance: f32 = FontAdvance(font, FontGlyph(font, 'x'))
    one: Vec2 = TextMeasure(font, "abcd", 10)
    testing.expect(t, abs(one.x - 4 * advance * 10) < 0.01)
    testing.expect(t, abs(one.y - (font.ascent - font.descent) * 10) < 0.01)
    two: Vec2 = TextMeasure(font, "ab\ncdef", 10)
    testing.expect(t, abs(two.x - 4 * advance * 10) < 0.01 && two.y > one.y, "the widest line, two lines")
    // "aaaa bbbb cc" in 5.5 characters of room: the words are on lines of their own
    room: f32 = 5.5 * advance * 10
    wrapped: Vec2 = TextMeasure(font, "aaaa bbbb cc", 10, {wrap_width = room})
    testing.expect(t, wrapped.x <= room + 0.01)
    testing.expect(t, abs(wrapped.y - (FontLineHeight(font) * 2 + font.ascent - font.descent) * 10) < 0.01, "three lines")
    texels: []f32 = make([]f32, 4 * ATLAS_WIDTH * 4)
    slots: []i32 = make([]i32, FontSlotCount(font))
    defer { delete(texels); delete(slots) }
    atlas: Atlas
    AtlasInit(&atlas, font, .SCANLINE, texels, slots)
    vertices: [256]TextVertex
    _, pen, _, _ := TextQuads(&atlas, "aaaa bbbb cc", {0, 0}, 10, vertices[:], {wrap_width = room})
    testing.expect(t, abs(pen.y - FontLineHeight(font) * 2 * 10) < 0.001, "the same lines as the measure says")
    tab: Vec2 = TextMeasure(font, "a\tb", 10)
    testing.expect(t, abs(tab.x - 5 * advance * 10) < 0.01, "a tab goes to the next multiple of four columns")
}

@(test)
test_the_palette_names_colors_by_index_and_says_when_it_is_full :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    texels: []f32 = make([]f32, 4 * ATLAS_WIDTH * 4)
    slots: []i32 = make([]i32, FontSlotCount(font))
    defer { delete(texels); delete(slots) }
    atlas: Atlas
    AtlasInit(&atlas, font, .SCANLINE, texels, slots)
    red, ok := AtlasColor(&atlas, {255, 0, 0, 255})
    testing.expect(t, ok && red == 0)
    green, _ := AtlasColor(&atlas, {0, 255, 0, 128})
    testing.expect_value(t, green, u8(1))
    again, _ := AtlasColor(&atlas, {255, 0, 0, 255})
    testing.expect_value(t, again, red)
    texel: []f32 = atlasTexel(&atlas, ATLAS_PALETTE_START + 1)
    testing.expect(t, texel[1] == 1 && abs(texel[3] - 128.0 / 255) < 0.001, "the color is in the texture")
    for i in 2 ..< ATLAS_PALETTE { AtlasColor(&atlas, {u8(i), 1, 2, 3}) }
    _, full_ok := AtlasColor(&atlas, {9, 9, 9, 9})
    testing.expect(t, !full_ok)
    AtlasClearColors(&atlas)
    fresh, fresh_ok := AtlasColor(&atlas, {9, 9, 9, 9})
    testing.expect(t, fresh_ok && fresh == 0)
}

@(test)
test_text_is_rotated_around_its_origin_and_snapped_to_whole_pixels :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    texels: []f32 = make([]f32, 4 * ATLAS_WIDTH * 4)
    slots: []i32 = make([]i32, FontSlotCount(font))
    defer { delete(texels); delete(slots) }
    atlas: Atlas
    AtlasInit(&atlas, font, .SLUG, texels, slots)
    vertices: [64]TextVertex
    advance: f32 = FontAdvance(font, FontGlyph(font, 'a'))
    // a quarter turn clockwise: the line that went right goes down
    _, pen, _, _ := TextQuads(&atlas, "aaaa", {100, 100}, 10, vertices[:], {rotation = 1.5707964})
    testing.expect(t, abs(pen.x - 100) < 0.01 && abs(pen.y - (100 + 4 * advance * 10)) < 0.01, "the pen moved down")
    // a vertex of a glyph keeps its em coordinates, whatever the turn
    plain: [64]TextVertex
    TextQuads(&atlas, "a", {0, 0}, 10, plain[:])
    turned: [64]TextVertex
    TextQuads(&atlas, "a", {0, 0}, 10, turned[:], {rotation = 1.5707964})
    for i in 0 ..< TEXT_VERTICES_PER_GLYPH {
        testing.expect_value(t, turned[i].uv, plain[i].uv)
        testing.expect(t, abs(turned[i].position.x + plain[i].position.y) < 0.001 && abs(turned[i].position.y - plain[i].position.x) < 0.001, "x and y turned a quarter")
    }
    // snapped: the baseline and the left edge of the quads are whole pixels away from a whole origin
    TextQuads(&atlas, "ab", {10.4, 20.7}, 13, vertices[:], {snap_to_pixels = true})
    for i in 0 ..< TEXT_VERTICES_PER_GLYPH {
        em_y: f32 = vertices[i].uv.y
        baseline: f32 = vertices[i].position.y + em_y * 13
        testing.expect(t, abs(baseline - 21) < 0.001, "the baseline is on pixel 21")
    }
    // a color index goes into every vertex
    TextQuads(&atlas, "a", {}, 10, vertices[:], {}, 5)
    testing.expect_value(t, vertices[0].color, u8(5))
}

@(test)
test_a_box_of_a_line_gives_the_em_and_the_baseline_and_measures_as_high_as_it_is :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    ppem, baseline := TextBox(font, 20)
    testing.expect(t, abs(TextMeasure(font, "Hello", ppem).y - 20) < 0.001, "a line is as high as the box")
    testing.expect(t, abs(baseline - font.ascent * ppem) < 0.001 && baseline > 10 && baseline < 20)
    testing.expect(t, ppem < 20, "the em is smaller than the box: the box holds the descent too")
}
