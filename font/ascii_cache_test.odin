#+build !js
package font

import "core:testing"
import su "../simd"

@(private = "file") INTER :: #load("../assets/fonts/inter/Inter-Regular.ttf")
@(private = "file") INTER_ITALIC :: #load("../assets/fonts/inter/Inter-Italic.ttf")
@(private = "file") FIRA_CODE :: #load("../assets/fonts/FiraCode-Regular.ttf")
@(private = "file") JETBRAINS :: #load("../assets/fonts/jetbrains_mono/JetBrainsMono-Regular.ttf")

@(private = "file")
fonts :: proc() -> (result: [4]^Font) {
    sources := [4][]u8{INTER, INTER_ITALIC, FIRA_CODE, JETBRAINS}
    for source, i in sources {
        result[i] = new(Font)
        assert(FontInit(result[i], source))
    }
    return
}

@(private = "file")
release :: proc(list: [4]^Font) {
    for font in list { free(font) }
}

// The tables give what the plain procedures give, for every character and every pair of ASCII characters, bit for bit
@(test)
test_the_ascii_tables_are_the_plain_answers :: proc(t: ^testing.T) {
    list := fonts()
    defer release(list)
    for font, f in list {
        for code in 0 ..< 128 {
            glyph: int = FontResolve(font, rune(code))
            testing.expectf(t, int(font.ascii_glyph[code]) == glyph, "font %d, glyph of %d", f, code)
            testing.expectf(t, font.ascii_advance[code] == FontAdvance(font, glyph), "font %d, advance of %d", f, code)
        }
        pairs_with_kerning: int
        for left in 0 ..< 128 {
            for right in 0 ..< 128 {
                first: int = FontResolve(font, rune(left))
                second: int = FontResolve(font, rune(right))
                expected: f32 = FontKerning(font, first, second)
                got: f32 = FontKerningAscii(font, u8(left), u8(right))
                if got != expected {
                    testing.expectf(t, false, "font %d, kerning of %d and %d: %v, expected %v", f, left, right, got, expected)
                    return
                }
                if expected != 0 { pairs_with_kerning += 1 }
            }
        }
        // Inter has pairs, the monospace fonts none that matter
        if f == 0 { testing.expect(t, pairs_with_kerning > 100, "Inter has kerning pairs") }
    }
}

// The text measure with the tables and the ASCII run is the plain per character measure (the code before the tables, written out here; the same rule for bad UTF-8), for text of all kinds, with and without a wrap
@(private = "file")
measureReference :: proc(font: ^Font, text: string, pixels_per_em: f32, wrap_width: f32) -> Vec2 {
    widest: f32
    lines: int = 1
    pen: f32
    previous: int
    wrap: f32 = wrap_width / pixels_per_em if wrap_width > 0 else 0
    space: f32 = FontAdvance(font, FontGlyph(font, ' '))
    word :: proc(font: ^Font, text: string, from: int, previous_glyph: int) -> f32 {
        width: f32
        before: int = previous_glyph
        i: int = from
        for i < len(text) {
            character, size := su.Utf8Next(transmute([]u8)text, i)
            if character == ' ' || character == '\n' || character == '\t' { break }
            glyph: int = FontResolve(font, character)
            if before != 0 { width += FontKerning(font, before, glyph) }
            width += FontAdvance(font, glyph)
            before = glyph
            i += size
        }
        return width
    }
    i: int
    for i < len(text) {
        character, size := su.Utf8Next(transmute([]u8)text, i)
        switch character {
        case '\n':
            widest = max(widest, pen)
            pen, previous = 0, 0
            lines += 1
        case '\t':
            columns: f32 = 4 * space
            pen = (f32(int(pen / columns)) + 1) * columns
            previous = 0
        case:
            glyph: int = FontResolve(font, character)
            if character == ' ' && wrap > 0 && pen > 0 && pen + space + word(font, text, i + size, glyph) > wrap {
                widest = max(widest, pen)
                pen, previous = 0, 0
                lines += 1
            } else {
                if previous != 0 { pen += FontKerning(font, previous, glyph) }
                pen += FontAdvance(font, glyph)
                previous = glyph
            }
        }
        i += size
    }
    widest = max(widest, pen)
    return {widest * pixels_per_em, (FontLineHeight(font) * f32(lines - 1) + font.ascent - font.descent) * pixels_per_em}
}

@(test)
test_the_text_measure_with_tables_is_the_plain_measure :: proc(t: ^testing.T) {
    list := fonts()
    defer release(list)
    pieces := [?]string{
        "The quick brown fox jumps over the lazy dog ", "AV To Wa Ty ", "fi fl ff ", "0123456789 ", "!@#$%^&*()_+-=[]{};:'\",.<>/?|\\~` ", "\n", "\t", "  ", "éè café ", "日本語 ",
        "\U0001F600 ", "\x80\xff", "\xE2\x82", "Waltz, nymph, for quick jigs vex Bud. ", "iiiiiiiiii", "WWWWWWWWWW", "ij ",
    }
    state: u32 = 3
    for round in 0 ..< 400 {
        text: [dynamic]u8
        defer delete(text)
        for _ in 0 ..< 1 + int(state % 12) {
            state = state * 1664525 + 1013904223
            append(&text, ..transmute([]u8)pieces[(state >> 8) % len(pieces)])
        }
        state = state * 1664525 + 1013904223
        wrap: f32 = 0 if round % 2 == 0 else f32(40 + (state >> 8) % 300)
        for font, f in list {
            got: Vec2 = TextMeasure(font, string(text[:]), 13, {wrap_width = wrap})
            expected: Vec2 = measureReference(font, string(text[:]), 13, wrap)
            if got != expected {
                testing.expectf(t, false, "font %d, round %d, wrap %v: %v, expected %v, text %q", f, round, wrap, got, expected, string(text[:]))
                return
            }
        }
    }
}

// The same quads from TextQuads on both paths is checked by the existing layout tests; here: bad UTF-8 is one missing glyph box per bad part
@(test)
test_a_bad_utf8_part_is_one_missing_character_in_the_layout :: proc(t: ^testing.T) {
    list := fonts()
    defer release(list)
    font: ^Font = list[0]
    one: Vec2 = TextMeasure(font, "a\xE2\x82z", 13)             // a cut euro sign: one part
    one_box: Vec2 = TextMeasure(font, "a\xFFz", 13)             // one stray byte: one part
    testing.expect_value(t, one.x, one_box.x)
    two: Vec2 = TextMeasure(font, "a\xFF\xFEz", 13)             // two stray bytes: two parts
    testing.expect(t, two.x > one_box.x)
    // the same text as plain characters of the missing glyph
    three: Vec2 = TextMeasure(font, "a\x80\x80\x80z", 13)
    testing.expect(t, three.x > two.x)
}
