#+build !js
package font

// The parser of this library (sfnt.odin, truetype.odin, cff.odin) against stb_truetype, which it is a port of and which read the fonts before: every glyph of a font has to give the
// same curves to the last bit, the same advance and box, every character the same glyph, the pairs the same kerning. stb_truetype is only used here, the library does not need it.
//
// The fonts of the repository are TrueType. Other files (OpenType with CFF outlines, collections, big fonts) are compared when FONT_TEST_FILES names them, separated by `;`:
//     FONT_TEST_FILES=C:/Windows/Fonts/cambria.ttc;D:/fonts/NotoSansJP-Medium.otf odin test font

import "base:runtime"
import "core:c"
import "core:log"
import "core:os"
import "core:strings"
import "core:testing"
import stbtt "vendor:stb/truetype"

@(private = "file")
PARSER_FONTS := [?][]u8 {
    #load("../assets/fonts/FiraCode-Regular.ttf"),
    #load("../assets/fonts/font.ttf"),
    #load("../assets/fonts/pixellocale-v-1-4.ttf"),
    #load("../assets/fonts/jetbrains_mono/JetBrainsMono-Regular.ttf"),
    #load("../assets/fonts/jetbrains_mono/JetBrainsMono-BoldItalic.ttf"),
}

// The fontinfo of vendor:stb/truetype with room behind it. The C struct of stb_truetype 1.28 has two fields more (vhea, vmtx) than the Odin struct of the binding (Odin dev-2026-11), so
// InitFont writes 8 bytes past it: on the stack that broke whatever came next (a crash, or file reads that failed later). The fields up to `svg` are still at their place.
@(private)
StbInfo :: struct {
    info: stbtt.fontinfo,
    room: [64]u8,
}

// What FontGlyphCurves did when stb_truetype read the outline: its list of points turned into curves
@(private = "file")
stbCurves :: proc(info: ^stbtt.fontinfo, glyph: int, scale: f32, out: []Curve) -> (count: int, ok: bool) {
    vertices: [^]stbtt.vertex
    vertex_count: c.int = stbtt.GetGlyphShape(info, c.int(glyph), &vertices)
    if vertex_count <= 0 { return 0, true }
    defer stbtt.FreeShape(info, vertices)
    start, pen: Vec2
    add :: proc(out: []Curve, count: ^int, curve: Curve) -> bool {
        if count^ >= len(out) { return false }
        out[count^] = curve
        count^ += 1
        return true
    }
    close :: proc(out: []Curve, count: ^int, pen: Vec2, start: Vec2) -> bool {
        if pen == start { return true }
        return add(out, count, {pen, (pen + start) * 0.5, start})
    }
    ok = true
    for i in 0 ..< int(vertex_count) {
        v: stbtt.vertex = vertices[i]
        point: Vec2 = {f32(v.x), f32(v.y)} * scale
        #partial switch stbtt.vmove(v.type) {
        case .vmove:
            ok = close(out, &count, pen, start) && ok
            start, pen = point, point
        case .vline:
            ok = add(out, &count, {pen, (pen + point) * 0.5, point}) && ok
            pen = point
        case .vcurve:
            ok = add(out, &count, {pen, Vec2{f32(v.cx), f32(v.cy)} * scale, point}) && ok
            pen = point
        case .vcubic:
            ok = cubicToQuadratics(out, &count, pen, Vec2{f32(v.cx), f32(v.cy)} * scale, Vec2{f32(v.cx1), f32(v.cy1)} * scale, point, 0) && ok
            pen = point
        }
    }
    ok = close(out, &count, pen, start) && ok
    return
}

// One font of a file through both parsers. `name` is for the messages.
@(private = "file")
compareWithStb :: proc(t: ^testing.T, name: string, data: []u8, index: int) {
    offset: c.int = stbtt.GetFontOffsetForIndex(raw_data(data), c.int(index))
    padded: StbInfo
    info: ^stbtt.fontinfo = &padded.info
    theirs_ok: bool = offset >= 0 && bool(stbtt.InitFont(info, raw_data(data), offset))
    font: ^Font = new(Font)
    defer free(font)
    ours_ok: bool = FontInit(font, data, index)
    testing.expectf(t, ours_ok == theirs_ok, "%s #%d: FontInit says %v, stb_truetype %v", name, index, ours_ok, theirs_ok)
    if !ours_ok || !theirs_ok {
        log.infof("%s #%d: not a font for both", name, index)
        return
    }

    testing.expectf(t, int(info.numGlyphs) == font.glyph_count, "%s: %d glyphs, stb_truetype %d", name, font.glyph_count, info.numGlyphs)
    // stb_truetype only gives the scale of a size: one over it is the units of the em up to a rounding (1999.9999 for 2000), ours is the whole number of the file
    testing.expect(t, abs(font.units_per_em - 1 / stbtt.ScaleForMappingEmToPixels(info, 1)) < 0.01 && font.units_per_em == f32(int(font.units_per_em)))
    ascent, descent, line_gap: c.int
    stbtt.GetFontVMetrics(info, &ascent, &descent, &line_gap)
    testing.expect_value(t, font.ascent, f32(ascent) / font.units_per_em)
    testing.expect_value(t, font.descent, f32(descent) / font.units_per_em)
    testing.expect_value(t, font.line_gap, f32(line_gap) / font.units_per_em)

    // every character of the planes fonts use (a step of 1 up to the end of the basic plane, then samples)
    wrong_glyphs: int
    for code := 0; code < 0x30000; code += 1 if code < 0x10000 else 7 {
        if FontGlyph(font, rune(code)) != int(stbtt.FindGlyphIndex(info, rune(code))) {
            wrong_glyphs += 1
            if wrong_glyphs < 4 { testing.expectf(t, false, "%s: U+%04X is glyph %d, stb_truetype %d", name, code, FontGlyph(font, rune(code)), stbtt.FindGlyphIndex(info, rune(code))) }
        }
    }
    testing.expectf(t, wrong_glyphs == 0, "%s: %d characters map to another glyph", name, wrong_glyphs)

    // every glyph: advance, box, curves
    CURVES :: 16384
    ours: []Curve = make([]Curve, CURVES)
    theirs: []Curve = make([]Curve, CURVES)
    defer delete(ours)
    defer delete(theirs)
    scale: f32 = 1 / font.units_per_em
    wrong_advances, wrong_boxes, wrong_outlines, curve_total: int
    for glyph in 0 ..< font.glyph_count {
        advance, bearing: c.int
        stbtt.GetGlyphHMetrics(info, c.int(glyph), &advance, &bearing)
        if FontAdvance(font, glyph) != f32(advance) / font.units_per_em { wrong_advances += 1 }

        x0, y0, x1, y1: c.int
        their_low, their_high: Vec2
        their_box: bool = stbtt.GetGlyphBox(info, c.int(glyph), &x0, &y0, &x1, &y1) != 0 && x1 > x0 && y1 > y0
        if their_box {
            their_low = Vec2{f32(x0), f32(y0)} / font.units_per_em
            their_high = Vec2{f32(x1), f32(y1)} / font.units_per_em
        }
        low, high, box := FontGlyphBox(font, glyph)
        if box != their_box || low != their_low || high != their_high {
            wrong_boxes += 1
            if wrong_boxes < 4 { testing.expectf(t, false, "%s: the box of glyph %d is %v %v %v, stb_truetype %v %v %v", name, glyph, box, low, high, their_box, their_low, their_high) }
        }

        count, ok := FontGlyphCurves(font, glyph, ours)
        their_count, their_ok := stbCurves(info, glyph, scale, theirs)
        same: bool = count == their_count && ok == their_ok
        if same {
            for i in 0 ..< count {
                if ours[i] != theirs[i] {
                    same = false
                    break
                }
            }
        }
        curve_total += count
        if !same {
            wrong_outlines += 1
            if wrong_outlines < 4 { testing.expectf(t, false, "%s: glyph %d has %d curves (%v), stb_truetype %d (%v), or other ones", name, glyph, count, ok, their_count, their_ok) }
        }
    }
    testing.expectf(t, wrong_advances == 0, "%s: %d glyphs have another advance", name, wrong_advances)
    testing.expectf(t, wrong_boxes == 0, "%s: %d glyphs have another box", name, wrong_boxes)
    testing.expectf(t, wrong_outlines == 0, "%s: %d of %d glyphs have another outline", name, wrong_outlines, font.glyph_count)
    testing.expectf(t, curve_total > 0, "%s: no glyph has an outline", name)

    // kerning: the letters and signs of text against each other, and glyphs spread over the font
    wrong_kerning, pairs: int
    for a in 0x20 ..< 0x250 {
        first: int = FontGlyph(font, rune(a))
        if first == 0 { continue }
        for b in 0x20 ..< 0x250 {
            second: int = FontGlyph(font, rune(b))
            if second == 0 { continue }
            their_kerning: f32 = f32(stbtt.GetGlyphKernAdvance(info, c.int(first), c.int(second))) / font.units_per_em
            if their_kerning != 0 { pairs += 1 }
            if FontKerning(font, first, second) != their_kerning {
                wrong_kerning += 1
                if wrong_kerning < 4 { testing.expectf(t, false, "%s: the kerning of %c%c is %v, stb_truetype %v", name, rune(a), rune(b), FontKerning(font, first, second), their_kerning) }
            }
        }
    }
    step: int = max(1, font.glyph_count / 300)
    for first := 0; first < font.glyph_count; first += step {
        for second := 0; second < font.glyph_count; second += step {
            if FontKerning(font, first, second) != f32(stbtt.GetGlyphKernAdvance(info, c.int(first), c.int(second))) / font.units_per_em { wrong_kerning += 1 }
        }
    }
    testing.expectf(t, wrong_kerning == 0, "%s: %d pairs have another kerning (%d pairs of letters are kerned)", name, wrong_kerning, pairs)
}

@(test)
test_the_parser_reads_every_glyph_as_stb_truetype_does :: proc(t: ^testing.T) {
    names: [len(PARSER_FONTS)]string = {"FiraCode-Regular", "font.ttf", "pixellocale", "JetBrainsMono-Regular", "JetBrainsMono-BoldItalic"}
    for data, i in PARSER_FONTS {
        compareWithStb(t, names[i], data, 0)
    }
}

// The fonts of FONT_TEST_FILES (see the top of the file): every font of a collection
@(test)
test_the_parser_reads_the_fonts_of_the_environment_as_stb_truetype_does :: proc(t: ^testing.T) {
    list: string = os.get_env("FONT_TEST_FILES", context.temp_allocator)
    for path in strings.split_iterator(&list, ";") {
        // the heap, not the allocator of the test runner: a font file can be tens of megabytes
        data, read_error := os.read_entire_file(path, runtime.heap_allocator())
        if !testing.expectf(t, read_error == nil, "cannot read %s: %v", path, read_error) { continue }
        defer delete(data, runtime.heap_allocator())
        font_count: int = max(1, int(stbtt.GetNumberOfFonts(raw_data(data))))
        log.infof("%s: %d bytes, %d font(s)", path, len(data), font_count)
        for index in 0 ..< font_count {
            compareWithStb(t, path, data, index)
        }
        // one past the last font of the file is no font
        font: ^Font = new(Font)
        testing.expectf(t, !FontInit(font, data, font_count), "%s has no font #%d", path, font_count)
        free(font)
    }
}

@(test)
test_bytes_that_are_not_a_font_are_refused_and_a_cut_file_reads_nothing_outside :: proc(t: ^testing.T) {
    font: ^Font = new(Font)
    defer free(font)
    testing.expect(t, !FontInit(font, nil))
    testing.expect(t, !FontInit(font, {1, 2, 3}))
    text: string = "this is a text file and not a font, however long it is"
    testing.expect(t, !FontInit(font, transmute([]u8)text))
    testing.expect(t, !FontInit(font, PARSER_FONTS[0], 1), "a plain file has only the font 0")

    // a file that ends too early, at many places: the font is refused or its glyphs are read without leaving the bytes (the bounds checks of the test build would stop the test)
    whole: []u8 = PARSER_FONTS[0]
    curves: []Curve = make([]Curve, 4096)
    defer delete(curves)
    for cut := 16; cut < len(whole); cut += len(whole) / 97 {
        if !FontInit(font, whole[:cut]) { continue }
        for glyph := 0; glyph < font.glyph_count; glyph += 13 {
            FontGlyphCurves(font, glyph, curves)
            FontGlyphBox(font, glyph)
            FontAdvance(font, glyph)
            FontKerning(font, glyph, (glyph * 7) % font.glyph_count)
        }
        for code in 0x20 ..< 0x400 {
            FontGlyph(font, rune(code))
        }
    }
    // and with bytes changed all over the file
    damaged: []u8 = make([]u8, len(whole))
    defer delete(damaged)
    for round in 0 ..< 24 {
        copy(damaged, whole)
        for i := round * 3 + 12; i < len(damaged); i += 211 + round * 17 {
            damaged[i] ~= u8(0x55 + round)
        }
        if !FontInit(font, damaged) { continue }
        for glyph := 0; glyph < min(font.glyph_count, 4000); glyph += 7 {
            FontGlyphCurves(font, glyph, curves)
            FontGlyphBox(font, glyph)
            FontAdvance(font, glyph)
        }
        for code in 0x20 ..< 0x400 {
            FontGlyph(font, rune(code))
        }
    }
}
