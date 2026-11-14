package atlas_packer

import "core:c"
import stbtt "vendor:stb/truetype"
import "core:testing"

// TTF font prepared for measuring and rendering glyphs at one pixel height.
// `data` is not copied, keep it alive while the Font is used.
Font :: struct {
    info: stbtt.fontinfo,
    height: f32,
    scale: f32,
    ascent: f32,            // scaled
    descent: f32,           // scaled
    line_gap: f32,          // scaled
    line_spacing: f32,      // distance between baselines
}

// One font character. After GetFontRects `rect_index` is the same index in the rectangle slice
Glyph :: struct {
    value: rune,
    index: int,             // stbtt glyph index
    offset: [2]f32,         // from top left of the line to top left of the glyph bitmap
    advance_x: f32,
    size: [2]i32,           // glyph bitmap size
}

FontInit :: proc(font: ^Font, data: []byte, height: f32, font_index: int = 0) -> (ok:bool) {
    font^ = {}
    font_offset: c.int = stbtt.GetFontOffsetForIndex(raw_data(data), cast(c.int)font_index)
    if font_offset < 0 {
        return false
    }
    if !stbtt.InitFont(&font.info, raw_data(data), font_offset) {
        return false
    }

    font.height = height
    font.scale = stbtt.ScaleForPixelHeight(&font.info, height)

    ascent, descent, line_gap: c.int
    stbtt.GetFontVMetrics(&font.info, &ascent, &descent, &line_gap)
    font.ascent = f32(ascent) * font.scale
    font.descent = f32(descent) * font.scale
    font.line_gap = f32(line_gap) * font.scale
    font.line_spacing = font.ascent - font.descent + font.line_gap
    return true
}

// Measure glyphs. Characters that the font doesn't have are skipped.
// Fills `glyphs` and `rectangles` from the start, rectangle size is the glyph bitmap + padding on each side (zw).
// Returns how many letters were found, or ok=false if buffers are too small.
GetFontRects :: proc(font: ^Font, letters: []rune, rectangles: []rectf, glyphs: []Glyph, padding: f32 = 0)->(count:int, ok:bool) {
    assert(len(rectangles) >= len(letters))
    assert(len(glyphs) >= len(letters))

    for letter in letters {
        index: c.int = stbtt.FindGlyphIndex(&font.info, letter)
        if index == 0 {
            continue
        }

        advance_x: c.int
        stbtt.GetGlyphHMetrics(&font.info, index, &advance_x, nil)

        x0, y0, x1, y1: c.int
        stbtt.GetGlyphBitmapBox(&font.info, index, font.scale, font.scale, &x0, &y0, &x1, &y1)

        glyphs[count] = {
            value = letter,
            index = int(index),
            offset = {f32(x0), f32(y0) + font.ascent},
            advance_x = f32(advance_x) * font.scale,
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

// Render glyph into `alpha`, 1 byte per pixel, glyph.size.x * glyph.size.y bytes. Returns false if buffer is too small
RenderGlyph :: proc(font: ^Font, glyph: ^Glyph, alpha: []u8) -> (ok:bool) {
    if glyph.size.x <= 0 || glyph.size.y <= 0 {
        return true
    }
    if len(alpha) < int(glyph.size.x * glyph.size.y) {
        return false
    }
    stbtt.MakeGlyphBitmap(&font.info, raw_data(alpha), glyph.size.x, glyph.size.y, glyph.size.x, font.scale, font.scale, cast(c.int)glyph.index)
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
    letters: []rune = {'A', '', 'g'}
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
