#+build !js
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
    scale: f32 = stbtt.ScaleForMappingEmToPixels(&font.info, pixels_per_em)
    x0, y0, x1, y1: c.int
    stbtt.GetGlyphBitmapBox(&font.info, c.int(glyph), scale, scale, &x0, &y0, &x1, &y1)
    width, height: int = int(x1 - x0), int(y1 - y0)
    reference: [64 * 64]u8
    stbtt.MakeGlyphBitmap(&font.info, raw_data(reference[:]), c.int(width), c.int(height), c.int(width), scale, scale, c.int(glyph))
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
    slots: []i32 = make([]i32, font.glyph_count)
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
    texels: []f32 = make([]f32, 4 * ATLAS_WIDTH * 2)
    slots: []i32 = make([]i32, font.glyph_count)
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
    first, rows := AtlasTakeDirty(&atlas)
    testing.expect(t, rows >= 1 && first == 0)
    _, none := AtlasTakeDirty(&atlas)
    testing.expect_value(t, none, 0)
    // an atlas that is full: the glyphs that fit are in, the others are told
    failed: bool
    for glyph in 0 ..< 400 {
        _, glyph_ok := AtlasGlyph(&atlas, glyph)
        if !glyph_ok { failed = true; break }
    }
    testing.expect(t, failed, "two rows of texels cannot hold four hundred glyphs")
}
