package font

// Vector fonts that are drawn from their outlines at any size, by the GPU (the Slug method and the Scanline Sweeper) or by the CPU (an exact coverage rasterizer that is also the reference the
// GPU methods are tested against). This file is the font itself: the file is parsed by stb_truetype (TrueType and OpenType, kept in the bytes the caller provides, nothing is copied), and every
// length is in em units (the em square is 1 by 1, y goes up, the baseline is at 0), so a size is a single multiplication.
//
//     font: font.Font
//     font.FontInit(&font, #load("Roboto.ttf"))
//     glyph := font.FontGlyph(&font, 'g')
//     width := font.FontAdvance(&font, glyph)               // em units
//
// `Method` is the choice of the algorithm for the GPU: `.SLUG` (curves in bands, one ray per pixel direction, exact at any scale) or `.SCANLINE` (the area that the curves sweep in the pixel).

import "core:c"
import stbtt "vendor:stb/truetype"

Vec2 :: [2]f32

Font :: struct {
    info: stbtt.fontinfo,
    data: []u8,                 // the file: it has to live as long as the font
    units_per_em: f32,
    ascent: f32,                // em units: above the baseline (positive)
    descent: f32,               // below the baseline (negative)
    line_gap: f32,              // the room between the descent of a line and the ascent of the next one
    glyph_count: int,
}

// Parses the font. `index` picks one font of a collection (.ttc), 0 for a plain file. False when the bytes are not a font.
FontInit :: proc(font: ^Font, data: []u8, index: int = 0) -> bool {
    font^ = {}
    offset: c.int = stbtt.GetFontOffsetForIndex(raw_data(data), c.int(index))
    if offset < 0 || !stbtt.InitFont(&font.info, raw_data(data), offset) { return false }
    font.data = data
    font.units_per_em = 1 / stbtt.ScaleForMappingEmToPixels(&font.info, 1)
    ascent, descent, line_gap: c.int
    stbtt.GetFontVMetrics(&font.info, &ascent, &descent, &line_gap)
    font.ascent = f32(ascent) / font.units_per_em
    font.descent = f32(descent) / font.units_per_em
    font.line_gap = f32(line_gap) / font.units_per_em
    font.glyph_count = int(font.info.numGlyphs)
    return true
}

// The glyph for a character (0, the "missing glyph", when the font has none)
FontGlyph :: proc(font: ^Font, character: rune) -> int {
    return int(stbtt.FindGlyphIndex(&font.info, character))
}

// How far the pen moves after the glyph, in em units
FontAdvance :: proc(font: ^Font, glyph: int) -> f32 {
    advance, bearing: c.int
    stbtt.GetGlyphHMetrics(&font.info, c.int(glyph), &advance, &bearing)
    return f32(advance) / font.units_per_em
}

// The extra move between two glyphs that fit together (em units, mostly negative), 0 when the font has no pair
FontKerning :: proc(font: ^Font, first: int, second: int) -> f32 {
    return f32(stbtt.GetGlyphKernAdvance(&font.info, c.int(first), c.int(second))) / font.units_per_em
}

// The height of a line of text (em units): from the ascent to the descent and the gap
FontLineHeight :: proc(font: ^Font) -> f32 {
    return font.ascent - font.descent + font.line_gap
}

// The box around the outline of a glyph in em units, false for a glyph with no outline (a space)
FontGlyphBox :: proc(font: ^Font, glyph: int) -> (low: Vec2, high: Vec2, ok: bool) {
    x0, y0, x1, y1: c.int
    if stbtt.GetGlyphBox(&font.info, c.int(glyph), &x0, &y0, &x1, &y1) == 0 { return }
    if x1 <= x0 || y1 <= y0 { return }
    low = {f32(x0), f32(y0)} / font.units_per_em
    high = {f32(x1), f32(y1)} / font.units_per_em
    return low, high, true
}

// Which algorithm draws on the GPU
Method :: enum u8 {
    SLUG,               // Eric Lengyel's Slug: the curves of a glyph are sorted into bands, a pixel looks at the curves of its band and counts the crossings of a ray in two directions
    SCANLINE,           // The Scanline Sweeper (Rook & Possum): a pixel adds up the signed area that every curve sweeps inside of it
}
