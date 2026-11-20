package font

// What the layout loops ask for most: the glyph and the advance of an ASCII character, and the kerning of a pair of them. A text of a user interface is almost all ASCII, and the
// plain answer (a binary search of the cmap, a read of hmtx, a lookup of the pair in GPOS) is 50 to 70 ns a character; these are tables that FontInit fills (the glyph and the advance of
// the 128 characters) and a table of the kerning of the pairs, 128 x 128 numbers in font units, made a row at a time the first time the left character is used (a row is 128 lookups,
// 6 microseconds). The values are the ones of the plain procedures (FontResolve, FontAdvance, FontKerning), bit for bit: a test compares every pair.
//
// Limits: the kerning rows are filled when first used and the Font is written then, so a Font that several threads measure at once should be warmed up first (`FontKerningWarm`) or
//     kept to one thread; the tables are made from the font the first time (FontInit), not updated if the bytes change.

import "base:intrinsics"
import su "../simd"

// Called at the end of FontInit
@(private)
fontFillAscii :: proc(font: ^Font) {
    for code in 0 ..< 128 {
        glyph: int = FontResolve(font, rune(code))
        font.ascii_glyph[code] = u32(glyph)
        font.ascii_advance[code] = FontAdvance(font, glyph)
    }
}

// The kerning of a pair of ASCII characters in em units: FontKerning of their glyphs
FontKerningAscii :: proc(font: ^Font, left: u8, right: u8) -> f32 {
    row: int = int(left & 0x7f)
    if intrinsics.atomic_load_explicit(&font.ascii_kern_row[row], .Acquire) == 0 { fontKernRow(font, row) }
    return f32(font.ascii_kern[row * 128 + int(right & 0x7f)]) / font.units_per_em
}

// Fills the rows of the kerning table that the text of a program will use (all of them: 128 rows, under a millisecond), so that no thread writes the font later
FontKerningWarm :: proc(font: ^Font) {
    for row in 0 ..< 128 {
        if intrinsics.atomic_load_explicit(&font.ascii_kern_row[row], .Acquire) == 0 { fontKernRow(font, row) }
    }
}

@(private)
fontKernRow :: proc(font: ^Font, row: int) {
    first: int = int(font.ascii_glyph[row])
    for right in 0 ..< 128 {
        second: int = int(font.ascii_glyph[right])
        value: int
        if first < font.glyph_count && second < font.glyph_count { value = sfntKerning(font, first, second) }
        font.ascii_kern[row * 128 + right] = i16(clamp(value, -32768, 32767))
    }
    intrinsics.atomic_store_explicit(&font.ascii_kern_row[row], 1, .Release)
}

// The glyph a character resolves to and its advance (em units): from the tables for ASCII
@(private)
fontMetrics :: #force_inline proc(font: ^Font, character: rune) -> (glyph: int, advance: f32) {
    if u32(character) < 128 { return int(font.ascii_glyph[character]), font.ascii_advance[character] }
    glyph = FontResolve(font, character)
    return glyph, FontAdvance(font, glyph)
}

// The kerning between the glyph of the character before and the glyph of this one (the tables for a pair of ASCII characters)
@(private)
fontPairKerning :: #force_inline proc(font: ^Font, previous_character: rune, previous: int, character: rune, glyph: int) -> f32 {
    if u32(previous_character) < 128 && u32(character) < 128 { return FontKerningAscii(font, u8(previous_character), u8(character)) }
    return FontKerning(font, previous, glyph)
}

// The next character of a text at byte `at` and its size: ASCII without a call, the rest by the rule of the standard for bad bytes (one RUNE_ERROR for the maximal subpart,
// which the layout draws as the missing glyph: one box for one bad part)
@(private)
fontNext :: #force_inline proc(text: string, at: int) -> (character: rune, size: int) {
    b: u8 = text[at]
    if b < 0x80 { return rune(b), 1 }
    bytes: []u8 = transmute([]u8)text
    return su.Utf8Next(bytes, at)
}

