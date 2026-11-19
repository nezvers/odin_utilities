package font

// Text to quads. A run of text becomes six vertices per visible glyph (two triangles) that a glue draws with the shader of the method; a vertex is a position in pixels (y down), the
// coordinates in the em square that the shader evaluates the outline at, and the slot of the glyph in the atlas. The quad is the box of the outline with a margin of one pixel around it, so
// the edge of the glyph has room for its anti-aliasing. Characters are placed by their advance and the kerning of the font; a new line is a line height down.
//
//     vertices: [4096]font.TextVertex
//     count := font.TextQuads(&atlas, "Hello", {20, 100}, 32, vertices[:])         // the baseline starts at (20, 100), 32 pixels to the em

import "core:unicode/utf8"

TextVertex :: struct {
    position: Vec2,             // pixels, y down
    uv: Vec2,                   // em units, y up, from the origin of the glyph
    slot: u32,                  // the slot of the glyph in the atlas
}

TEXT_VERTICES_PER_GLYPH :: 6
QUAD_MARGIN_PIXELS :: f32(1)

// The slot as four bytes (what a vertex color carries when a framework has no better place for it): the shaders read it back from the first two
SlotColor :: proc(slot: u32) -> [4]u8 {
    return {u8(slot & 255), u8((slot >> 8) & 255), 0, 255}
}

TextOptions :: struct {
    wrap_width: f32,            // pixels: lines are broken at spaces to fit (0: only at new lines)
    line_spacing: f32,          // a factor of the line height of the font (0 is 1)
    tab_columns: int,           // a tab moves to a multiple of this many spaces (0 is 4)
}

// The glyphs of a text one after the other: where each is (the pen position in em units of the line, the line) and its glyph number. `visit` gets every character that is drawn.
@(private)
LayoutStep :: struct {
    glyph: int,
    x: f32,             // em units from the start of the line
    line: int,
}

// A line break that fits: the width of the text from `from` to the next space or the end, in em units
@(private)
wordWidth :: proc(font: ^Font, text: string, from: int, previous_glyph: int) -> f32 {
    width: f32
    previous: int = previous_glyph
    i: int = from
    for i < len(text) {
        character, size := utf8.decode_rune_in_string(text[i:])
        if character == ' ' || character == '\n' || character == '\t' { break }
        glyph: int = FontGlyph(font, character)
        if previous != 0 { width += FontKerning(font, previous, glyph) }
        width += FontAdvance(font, glyph)
        previous = glyph
        i += size
    }
    return width
}

// The size of the text in pixels: the widest line, and the height of all lines
TextMeasure :: proc(font: ^Font, text: string, pixels_per_em: f32, options: TextOptions = {}) -> Vec2 {
    widest: f32
    lines: int = 1
    pen: f32
    previous: int
    wrap: f32 = options.wrap_width / pixels_per_em if options.wrap_width > 0 else 0
    tab: int = options.tab_columns if options.tab_columns > 0 else 4
    space: f32 = FontAdvance(font, FontGlyph(font, ' '))
    i: int
    for i < len(text) {
        character, size := utf8.decode_rune_in_string(text[i:])
        switch character {
        case '\n':
            widest = max(widest, pen)
            pen, previous = 0, 0
            lines += 1
        case '\t':
            columns: f32 = f32(tab) * space
            pen = (f32(int(pen / columns)) + 1) * columns
            previous = 0
        case:
            glyph: int = FontGlyph(font, character)
            if character == ' ' && wrap > 0 && pen > 0 && pen + space + wordWidth(font, text, i + size, glyph) > wrap {
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
    spacing: f32 = options.line_spacing if options.line_spacing > 0 else 1
    return {widest * pixels_per_em, (FontLineHeight(font) * spacing * f32(lines - 1) + font.ascent - font.descent) * pixels_per_em}
}

// The quads of a text into `out` (six vertices per glyph that has an outline), how many vertices, and the position of the pen after the last character. The glyphs are baked into the atlas
// as they are met; when the atlas or `out` is full the text stops there and `complete` is false.
TextQuads :: proc(atlas: ^Atlas, text: string, origin: Vec2, pixels_per_em: f32, out: []TextVertex, options: TextOptions = {}) -> (count: int, pen: Vec2, complete: bool) {
    font: ^Font = atlas.font
    margin: f32 = QUAD_MARGIN_PIXELS / pixels_per_em
    wrap: f32 = options.wrap_width / pixels_per_em if options.wrap_width > 0 else 0
    tab: int = options.tab_columns if options.tab_columns > 0 else 4
    spacing: f32 = options.line_spacing if options.line_spacing > 0 else 1
    line_height: f32 = FontLineHeight(font) * spacing
    space: f32 = FontAdvance(font, FontGlyph(font, ' '))
    x: f32                      // em units from the start of the line
    line: int
    previous: int
    complete = true
    i: int
    for i < len(text) {
        character, size := utf8.decode_rune_in_string(text[i:])
        i += size
        switch character {
        case '\n':
            x, previous = 0, 0
            line += 1
            continue
        case '\t':
            columns: f32 = f32(tab) * space
            x = (f32(int(x / columns)) + 1) * columns
            previous = 0
            continue
        }
        glyph: int = FontGlyph(font, character)
        if character == ' ' && wrap > 0 && x > 0 && x + space + wordWidth(font, text, i, glyph) > wrap {
            x, previous = 0, 0
            line += 1
            continue
        }
        if previous != 0 { x += FontKerning(font, previous, glyph) }
        previous = glyph
        low, high, has_box := FontGlyphBox(font, glyph)
        if has_box {
            slot, ok := AtlasGlyph(atlas, glyph)
            if !ok || count + TEXT_VERTICES_PER_GLYPH > len(out) {
                complete = false
                break
            }
            if slot >= 0 {
                corner_low: Vec2 = low - {margin, margin}
                corner_high: Vec2 = high + {margin, margin}
                baseline: f32 = origin.y + f32(line) * line_height * pixels_per_em
                left: f32 = origin.x + x * pixels_per_em
                // the corners: bottom left, bottom right, top right, top left (y goes up in the em square and down on the screen)
                place :: proc(em: Vec2, left: f32, baseline: f32, pixels_per_em: f32, slot: u32) -> TextVertex {
                    return {position = {left + em.x * pixels_per_em, baseline - em.y * pixels_per_em}, uv = em, slot = slot}
                }
                a: TextVertex = place({corner_low.x, corner_low.y}, left, baseline, pixels_per_em, u32(slot))
                b: TextVertex = place({corner_high.x, corner_low.y}, left, baseline, pixels_per_em, u32(slot))
                c: TextVertex = place({corner_high.x, corner_high.y}, left, baseline, pixels_per_em, u32(slot))
                d: TextVertex = place({corner_low.x, corner_high.y}, left, baseline, pixels_per_em, u32(slot))
                out[count + 0], out[count + 1], out[count + 2] = a, b, c
                out[count + 3], out[count + 4], out[count + 5] = a, c, d
                count += TEXT_VERTICES_PER_GLYPH
            }
        }
        x += FontAdvance(font, glyph)
    }
    pen = {origin.x + x * pixels_per_em, origin.y + f32(line) * line_height * pixels_per_em}
    return
}
