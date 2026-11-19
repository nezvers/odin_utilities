package atlas_packer

// Glyph bitmaps of a font at one pixel height, for packing into an atlas. The font file is read by the font library of this repository (odin_utilities/font: TrueType and OpenType,
// pure Odin) and a glyph is drawn by its exact coverage rasterizer: the alpha of a pixel is the part of it that the outline covers. No C library, nothing is allocated.

import vector_font "../font"
import "core:math"
import "core:testing"

// The curves of one glyph that RenderGlyph has room for on its stack when the caller gives no room of its own: Latin, Greek and Cyrillic letters have 10 to 60
GLYPH_CURVES :: 256

// TTF / OTF font prepared for measuring and rendering glyphs at one pixel height.
// `data` is not copied, keep it alive while the Font is used.
Font :: struct {
    face: vector_font.Font,
    height: f32,
    pixels_per_em: f32,
    ascent: f32,            // scaled
    descent: f32,           // scaled
    line_gap: f32,          // scaled
    line_spacing: f32,      // distance between baselines
}

// One font character. After GetFontRects `rect_index` is the same index in the rectangle slice
Glyph :: struct {
    value: rune,
    index: int,             // glyph index in the font file
    offset: [2]f32,         // from top left of the line to top left of the glyph bitmap
    advance_x: f32,
    size: [2]i32,           // glyph bitmap size
}

// `height` is the pixels from the ascent to the descent of the font. `font_index` picks one font of a collection (.ttc).
FontInit :: proc(font: ^Font, data: []byte, height: f32, font_index: int = 0) -> (ok:bool) {
    font^ = {}
    if !vector_font.FontInit(&font.face, data, font_index) {
        return false
    }
    extent: f32 = font.face.ascent - font.face.descent
    if extent <= 0 {
        font^ = {}
        return false
    }

    font.height = height
    font.pixels_per_em = height / extent
    font.ascent = font.face.ascent * font.pixels_per_em
    font.descent = font.face.descent * font.pixels_per_em
    font.line_gap = font.face.line_gap * font.pixels_per_em
    font.line_spacing = font.ascent - font.descent + font.line_gap
    return true
}

// The pixels a glyph touches, around the pen on the baseline (y down): the box of the outline grown to whole pixels. All zero for a glyph without an outline.
@(private)
glyphPixelBox :: proc(font: ^Font, index: int) -> (x0: int, y0: int, x1: int, y1: int) {
    low, high, has_outline := vector_font.FontGlyphBox(&font.face, index)
    if !has_outline {
        return
    }
    x0 = int(math.floor(low.x * font.pixels_per_em))
    y0 = int(math.floor(-high.y * font.pixels_per_em))
    x1 = int(math.ceil(high.x * font.pixels_per_em))
    y1 = int(math.ceil(-low.y * font.pixels_per_em))
    return
}

// Measure glyphs. Characters that the font doesn't have are skipped.
// Fills `glyphs` and `rectangles` from the start, rectangle size is the glyph bitmap + padding on each side (zw).
// Returns how many letters were found, or ok=false if buffers are too small.
GetFontRects :: proc(font: ^Font, letters: []rune, rectangles: []rectf, glyphs: []Glyph, padding: f32 = 0)->(count:int, ok:bool) {
    assert(len(rectangles) >= len(letters))
    assert(len(glyphs) >= len(letters))

    for letter in letters {
        index: int = vector_font.FontGlyph(&font.face, letter)
        if index == 0 {
            continue
        }
        x0, y0, x1, y1 := glyphPixelBox(font, index)

        glyphs[count] = {
            value = letter,
            index = index,
            offset = {f32(x0), f32(y0) + font.ascent},
            advance_x = vector_font.FontAdvance(&font.face, index) * font.pixels_per_em,
            size = {i32(x1 - x0), i32(y1 - y0)},
        }
        rectangles[count] = {0, 0, f32(x1 - x0) + padding * 2, f32(y1 - y0) + padding * 2}
        count += 1
    }
    ok = true
    return
}

// Size of the alpha buffer that fits any of the glyphs
GlyphsMaxBytes :: proc(glyphs: []Glyph) -> (bytes:int) {
    for glyph in glyphs {
        bytes = max(bytes, int(glyph.size.x * glyph.size.y))
    }
    return
}

// Render glyph into `alpha`, 1 byte per pixel, glyph.size.x * glyph.size.y bytes. Returns false if a buffer is too small.
// `curves` is the room for the outline: a quarter of it for the curves of the glyph, the rest for their monotonic pieces (up to three per curve). Without it the room is on the
// stack and fits a glyph of GLYPH_CURVES curves; give your own for the glyphs that have more (CJK, ornaments).
RenderGlyph :: proc(font: ^Font, glyph: ^Glyph, alpha: []u8, curves: []vector_font.Curve = nil) -> (ok:bool) {
    if glyph.size.x <= 0 || glyph.size.y <= 0 {
        return true
    }
    if len(alpha) < int(glyph.size.x * glyph.size.y) {
        return false
    }
    stack_room: [GLYPH_CURVES * 4]vector_font.Curve = ---
    room: []vector_font.Curve = curves if len(curves) > 0 else stack_room[:]
    outline_room: int = len(room) / 4
    outline_count, outline_ok := vector_font.FontGlyphCurves(&font.face, glyph.index, room[:outline_room])
    if !outline_ok {
        return false
    }
    pieces: []vector_font.Curve = room[outline_room:]
    piece_count, pieces_ok := vector_font.CurvesMonotonic(room[:outline_count], pieces)
    if !pieces_ok {
        return false
    }
    // the same box as GetFontRects measured: its top left pixel is the first of the bitmap
    x0, y0, _, _ := glyphPixelBox(font, glyph.index)
    vector_font.CurvesRasterize(pieces[:piece_count], font.pixels_per_em, {f32(-x0), f32(-y0)}, alpha, int(glyph.size.x), int(glyph.size.y))
    return true
}

// --- Tests ---

@(test)
test_font_init_rejects_garbage :: proc(t: ^testing.T) {
    font: Font
    garbage: [64]byte
    testing.expect(t, !FontInit(&font, garbage[:], 16), "not a font")
}

@(test)
test_font_glyph_helpers :: proc(t: ^testing.T) {
    @(static) font_data := #load("../assets/fonts/font.ttf")
    font: Font
    testing.expect(t, FontInit(&font, font_data, 24))
    testing.expect(t, font.ascent > 0 && font.descent < 0, "ascent above the baseline, descent below")
    testing.expect(t, font.line_spacing >= font.ascent - font.descent)

    // a code point in the private use area is missing from the font and is skipped
    letters: []rune = {'A', 0xE000, 'g'}
    rects: [3]rectf
    glyphs: [3]Glyph
    count, ok := GetFontRects(&font, letters, rects[:], glyphs[:], 2)
    testing.expect(t, ok)
    testing.expect_value(t, count, 2)
    testing.expect_value(t, glyphs[0].value, 'A')
    testing.expect_value(t, glyphs[1].value, 'g')
    testing.expect_value(t, rects[0].z, f32(glyphs[0].size.x) + 4)                         // padding on both sides
    testing.expect_value(t, rects[0].w, f32(glyphs[0].size.y) + 4)
    testing.expect(t, glyphs[0].advance_x > 0)

    biggest: int = GlyphsMaxBytes(glyphs[:count])
    testing.expect(t, biggest >= int(glyphs[0].size.x * glyphs[0].size.y))
    testing.expect(t, biggest >= int(glyphs[1].size.x * glyphs[1].size.y))

    small: [1]u8
    testing.expect(t, !RenderGlyph(&font, &glyphs[0], small[:]), "the buffer is too small for the bitmap")
    alpha := make([]u8, biggest)
    defer delete(alpha)
    testing.expect(t, RenderGlyph(&font, &glyphs[0], alpha))
    any_ink: bool
    for value in alpha[:glyphs[0].size.x * glyphs[0].size.y] { any_ink = any_ink || value > 0 }
    testing.expect(t, any_ink, "the glyph draws something")
}

@(test)
test_glyph_bitmap_is_the_shape_of_the_letter :: proc(t: ^testing.T) {
    @(static) font_data := #load("../assets/fonts/FiraCode-Regular.ttf")
    font: Font
    testing.expect(t, FontInit(&font, font_data, 48))
    letters: []rune = {'I', 'O', 'T'}
    rects: [3]rectf
    glyphs: [3]Glyph
    count, _ := GetFontRects(&font, letters, rects[:], glyphs[:])
    testing.expect_value(t, count, 3)
    alpha: [64 * 64]u8
    // the pixel at a place of the bitmap given as parts of its width and height
    at :: proc(alpha: []u8, glyph: ^Glyph, x: f32, y: f32) -> u8 {
        return alpha[int(y * f32(glyph.size.y - 1)) * int(glyph.size.x) + int(x * f32(glyph.size.x - 1))]
    }
    // every bitmap touches all four sides of its box (the box is the outline grown to whole pixels) and is not wider than the advance of the monospace font
    for &glyph in glyphs[:count] {
        testing.expect(t, RenderGlyph(&font, &glyph, alpha[:]))
        width, height: int = int(glyph.size.x), int(glyph.size.y)
        testing.expect(t, width > 4 && height > 20 && f32(width) <= glyph.advance_x + 2)
        left, right, top, bottom: bool
        for y in 0 ..< height {
            left = left || alpha[y * width] > 0
            right = right || alpha[y * width + width - 1] > 0
        }
        for x in 0 ..< width {
            top = top || alpha[x] > 0
            bottom = bottom || alpha[(height - 1) * width + x] > 0
        }
        testing.expectf(t, left && right && top && bottom, "%c: ink on every side of the box", glyph.value)
        // capital letters stand on the baseline: the bitmap ends there (the O goes a little under it)
        under: f32 = glyph.offset.y + f32(height) - font.ascent
        testing.expectf(t, under >= 0 && under <= 2, "%c: ends %v pixels under the baseline", glyph.value, under)
    }
    // O: a ring, empty in the middle and solid on its left stroke. T: the bar on top is solid, under it only the stem in the middle
    testing.expect(t, RenderGlyph(&font, &glyphs[1], alpha[:]))
    testing.expect_value(t, at(alpha[:], &glyphs[1], 0.5, 0.5), 0)
    testing.expect(t, at(alpha[:], &glyphs[1], 0.1, 0.5) > 200)
    testing.expect(t, RenderGlyph(&font, &glyphs[2], alpha[:]))
    testing.expect(t, at(alpha[:], &glyphs[2], 0.1, 0.05) > 200 && at(alpha[:], &glyphs[2], 0.9, 0.05) > 200)
    testing.expect(t, at(alpha[:], &glyphs[2], 0.5, 0.8) > 200)
    testing.expect_value(t, at(alpha[:], &glyphs[2], 0.1, 0.8), 0)

    // room for the curves that is too small is told, room of the caller is used
    small: [8]vector_font.Curve
    testing.expect(t, !RenderGlyph(&font, &glyphs[1], alpha[:], small[:]), "an O has more than two curves")
    own: [512]vector_font.Curve
    testing.expect(t, RenderGlyph(&font, &glyphs[1], alpha[:], own[:]))
    testing.expect_value(t, at(alpha[:], &glyphs[1], 0.5, 0.5), 0)
}
