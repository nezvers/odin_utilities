package font

// Text to quads. A run of text becomes six vertices per visible glyph (two triangles) that a glue draws with the shader of the method; a vertex is a position in pixels (y down), the
// coordinates in the em square that the shader evaluates the outline at, and the slot of the glyph in the atlas. The quad is the box of the outline with a margin of one pixel around it, so
// the edge of the glyph has room for its anti-aliasing. Characters are placed by their advance and the kerning of the font; a new line is a line height down.
//
//     vertices: [4096]font.TextVertex
//     count := font.TextQuads(&atlas, "Hello", {20, 100}, 32, vertices[:])         // the baseline starts at (20, 100), 32 pixels to the em

import "core:math"
import "core:unicode/utf8"

TextVertex :: struct {
    position: Vec2,             // pixels, y down
    uv: Vec2,                   // em units, y up, from the origin of the glyph
    slot: u32,                  // the slot of the glyph in the atlas
    color: u8,                  // the index of the color in the palette of the atlas (AtlasColor)
}

TEXT_VERTICES_PER_GLYPH :: 6
QUAD_MARGIN_PIXELS :: f32(1)

// The slot and the palette index as four bytes (what a vertex color carries when a framework has no better place for it): the shaders read the slot back from the red and the green, the
// color from the palette by the blue
SlotColor :: proc(slot: u32, color: u8 = 0) -> [4]u8 {
    return {u8(slot & 255), u8((slot >> 8) & 255), color, 255}
}

TextOptions :: struct {
    wrap_width: f32,            // pixels: lines are broken at spaces to fit (0: only at new lines)
    line_spacing: f32,          // a factor of the line height of the font (0 is 1)
    tab_columns: int,           // a tab moves to a multiple of this many spaces (0 is 4)
    rotation: f32,              // radians, clockwise on the screen, around the origin of the text
    snap_to_pixels: bool,       // the baseline and each glyph start on a whole pixel (the outlines are not hinted: this keeps the stems of a line alike), not with a rotation
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

// The quads of a text into `out` (six vertices per glyph that has an outline), how many vertices, and the position of the pen after the last character. `color` is the index of the color in
// the palette of the atlas (AtlasColor). The glyphs are baked into the atlas as they are met (AtlasReserveText does it first, so that a full atlas is known before anything is drawn); when the
// atlas or `out` is full the text stops there and `complete` is false.
TextQuads :: proc(atlas: ^Atlas, text: string, origin: Vec2, pixels_per_em: f32, out: []TextVertex, options: TextOptions = {}, color: u8 = 0) -> (count: int, pen: Vec2, complete: bool) {
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
    cos_angle: f32 = 1
    sin_angle: f32 = 0
    if options.rotation != 0 {
        cos_angle, sin_angle = math.cos(options.rotation), math.sin(options.rotation)
    }
    snap: bool = options.snap_to_pixels && options.rotation == 0
    // a point of the text (pixels from the origin of the text, y down) on the screen
    turn :: proc(local: Vec2, origin: Vec2, cos_angle: f32, sin_angle: f32) -> Vec2 {
        return origin + Vec2{local.x * cos_angle - local.y * sin_angle, local.x * sin_angle + local.y * cos_angle}
    }
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
                baseline: f32 = f32(line) * line_height * pixels_per_em
                left: f32 = x * pixels_per_em
                if snap {
                    baseline = math.round(origin.y + baseline) - origin.y
                    left = math.round(origin.x + left) - origin.x
                }
                // the corners: bottom left, bottom right, top right, top left (y goes up in the em square and down on the screen)
                place :: proc(em: Vec2, left: f32, baseline: f32, pixels_per_em: f32, slot: u32, color: u8, origin: Vec2, cos_angle: f32, sin_angle: f32) -> TextVertex {
                    local: Vec2 = {left + em.x * pixels_per_em, baseline - em.y * pixels_per_em}
                    return {position = turn(local, origin, cos_angle, sin_angle), uv = em, slot = slot, color = color}
                }
                a: TextVertex = place({corner_low.x, corner_low.y}, left, baseline, pixels_per_em, u32(slot), color, origin, cos_angle, sin_angle)
                b: TextVertex = place({corner_high.x, corner_low.y}, left, baseline, pixels_per_em, u32(slot), color, origin, cos_angle, sin_angle)
                c: TextVertex = place({corner_high.x, corner_high.y}, left, baseline, pixels_per_em, u32(slot), color, origin, cos_angle, sin_angle)
                d: TextVertex = place({corner_low.x, corner_high.y}, left, baseline, pixels_per_em, u32(slot), color, origin, cos_angle, sin_angle)
                out[count + 0], out[count + 1], out[count + 2] = a, b, c
                out[count + 3], out[count + 4], out[count + 5] = a, c, d
                count += TEXT_VERTICES_PER_GLYPH
            }
        }
        x += FontAdvance(font, glyph)
    }
    pen = turn({x * pixels_per_em, f32(line) * line_height * pixels_per_em}, origin, cos_angle, sin_angle)
    return
}
