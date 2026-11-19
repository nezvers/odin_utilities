package font

// Vector fonts that are drawn from their outlines at any size, by the GPU (the Slug method and the Scanline Sweeper) or by the CPU (an exact coverage rasterizer that is also the reference the
// GPU methods are tested against). This file is the font itself: TrueType and OpenType files and collections, read in the bytes the caller provides by the parser of this library (sfnt.odin,
// truetype.odin, cff.odin: nothing is copied, nothing is allocated, no C library), and every length is in em units (the em square is 1 by 1, y goes up, the baseline is at 0), so a size is a
// single multiplication.
//
//     font: font.Font
//     font.FontInit(&font, #load("Roboto.ttf"))
//     glyph := font.FontGlyph(&font, 'g')
//     width := font.FontAdvance(&font, glyph)               // em units
//
// `Method` is the choice of the algorithm for the GPU: `.SLUG` (curves in bands, one ray per pixel direction, exact at any scale) or `.SCANLINE` (the area that the curves sweep in the pixel).

Vec2 :: [2]f32

Font :: struct {
    data: []u8,                 // the file: it has to live as long as the font
    units_per_em: f32,
    ascent: f32,                // em units: above the baseline (positive)
    descent: f32,               // below the baseline (negative)
    line_gap: f32,              // the room between the descent of a line and the ascent of the next one
    glyph_count: int,
    // The tables, views into `data` (sfnt.odin)
    character_map: []u8,        // the subtable of cmap that maps Unicode
    advances: []u8,             // hmtx
    advance_count: int,         // the glyphs after this many all have the last advance (a monospace font stores one)
    kern: []u8,                 // the old table of kerning pairs, empty when the font has none
    gpos: []u8,                 // the lookup list of GPOS, where newer fonts keep their kerning
    // The outlines: TrueType (glyf, truetype.odin) or PostScript (CFF, cff.odin)
    is_cff: bool,
    glyf: []u8,
    loca: []u8,                 // where each glyph is in glyf
    loca_long: bool,            // 32 bit places, else 16 bit halves
    cff: FontCff,
}

// Parses the font. `index` picks one font of a collection (.ttc), 0 for a plain file. False when the bytes are not a font.
FontInit :: proc(font: ^Font, data: []u8, index: int = 0) -> bool {
    font^ = {}
    start, found := sfntStart(data, index)
    if !found { return false }
    cmap: []u8 = sfntTable(data, start, "cmap")
    head: []u8 = sfntTable(data, start, "head")
    hhea: []u8 = sfntTable(data, start, "hhea")
    hmtx: []u8 = sfntTable(data, start, "hmtx")
    if len(cmap) < 4 || len(head) < 54 || len(hhea) < 36 || len(hmtx) == 0 { return false }
    units: int = readU16(head, 18)
    if units == 0 { return false }

    glyf: []u8 = sfntTable(data, start, "glyf")
    loca: []u8 = sfntTable(data, start, "loca")
    if len(glyf) > 0 && len(loca) > 0 {
        format: int = readU16(head, 50)
        if format > 1 { return false }
        font.glyf, font.loca, font.loca_long = glyf, loca, format == 1
    } else {
        cff, cff_ok := cffLoad(sfntTable(data, start, "CFF "))
        if !cff_ok { return false }
        font.cff, font.is_cff = cff, true
    }
    font.character_map = sfntCharacterMap(cmap)
    if len(font.character_map) == 0 {
        font^ = {}
        return false
    }

    font.data = data
    font.units_per_em = f32(units)
    font.ascent = f32(readI16(hhea, 4)) / font.units_per_em
    font.descent = f32(readI16(hhea, 6)) / font.units_per_em
    font.line_gap = f32(readI16(hhea, 8)) / font.units_per_em
    font.advances = hmtx
    font.advance_count = readU16(hhea, 34)
    maxp: []u8 = sfntTable(data, start, "maxp")
    font.glyph_count = readU16(maxp, 4) if len(maxp) >= 6 else 0xffff

    gpos: []u8 = sfntTable(data, start, "GPOS")
    if len(gpos) >= 10 && readU16(gpos, 0) == 1 && readU16(gpos, 2) <= 1 && readU16(gpos, 8) <= len(gpos) { font.gpos = gpos[readU16(gpos, 8):] }
    kern: []u8 = sfntTable(data, start, "kern")
    if len(kern) >= 10 && readU16(kern, 2) >= 1 && readU16(kern, 8) == 1 { font.kern = kern }
    return true
}

// The glyph for a character (0, the "missing glyph", when the font has none)
FontGlyph :: proc(font: ^Font, character: rune) -> int {
    return sfntGlyphIndex(font.character_map, character)
}

// How far the pen moves after the glyph, in em units
FontAdvance :: proc(font: ^Font, glyph: int) -> f32 {
    if glyph >= font.glyph_count { return MISSING_ADVANCE if glyph == GlyphMissing(font) else 0 }
    if font.advance_count <= 0 { return 0 }
    return f32(readI16(font.advances, 4 * min(glyph, font.advance_count - 1))) / font.units_per_em
}

// The extra move between two glyphs that fit together (em units, mostly negative), 0 when the font has no pair
FontKerning :: proc(font: ^Font, first: int, second: int) -> f32 {
    if first >= font.glyph_count || second >= font.glyph_count { return 0 }
    return f32(sfntKerning(font, first, second)) / font.units_per_em
}

// The height of a line of text (em units): from the ascent to the descent and the gap
FontLineHeight :: proc(font: ^Font) -> f32 {
    return font.ascent - font.descent + font.line_gap
}

// The box around the outline of a glyph in em units, false for a glyph with no outline (a space)
FontGlyphBox :: proc(font: ^Font, glyph: int) -> (low: Vec2, high: Vec2, ok: bool) {
    if glyph >= font.glyph_count { return specialBox(font, glyph) }
    x0, y0, x1, y1: int
    if font.is_cff {
        // a CFF glyph does not store its box: its program is run once only to see how far the points go
        sink: OutlineSink = {measure = true}
        if !cffGlyphOutline(&font.cff, glyph, &sink) { return }
        x0, y0, x1, y1 = sink.low.x, sink.low.y, sink.high.x, sink.high.y
    } else {
        data: []u8 = ttGlyphData(font, glyph)
        if len(data) == 0 { return }
        x0, y0, x1, y1 = readI16(data, 2), readI16(data, 4), readI16(data, 6), readI16(data, 8)
    }
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
