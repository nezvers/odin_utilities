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
    alpha: u8,                  // 255 opaque: multiplies the alpha of the color of the palette (a fade of one glyph)
}

TEXT_VERTICES_PER_GLYPH :: 6
QUAD_MARGIN_PIXELS :: f32(1)

// The slot, the palette index and the alpha as four bytes (what a vertex color carries when a framework has no better place for it): the shaders read the slot back from the red and the
// green, the color from the palette by the blue and a fade of the glyph from the alpha
SlotColor :: proc(slot: u32, color: u8 = 0, alpha: u8 = 255) -> [4]u8 {
    return {u8(slot & 255), u8((slot >> 8) & 255), color, alpha}
}

TextOptions :: struct {
    wrap_width: f32,            // pixels: lines are broken at spaces to fit (0: only at new lines)
    line_spacing: f32,          // a factor of the line height of the font (0 is 1)
    tab_columns: int,           // a tab moves to a multiple of this many spaces (0 is 4)
    rotation: f32,              // radians, clockwise on the screen, around the origin of the text
    missing_color: [4]u8,       // the color of the box that a character the font does not have is drawn as (all zero: magenta); TextQuads gives it a palette color of its own
    face: u8,                   // the face of the family of the atlas (1 bold, 2 italic, 3 bold italic; AtlasAddFace); a face that is not there is the regular one
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
        glyph: int = FontResolve(font, character)
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
            glyph: int = FontResolve(font, character)
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

// The quads of a text into `out` (six vertices per glyph that has an outline), how many vertices, the position of the pen after the last character and how many characters the font does not have
// (each is drawn as a box with a cross in the color `options.missing_color`, magenta unless told otherwise, so that it cannot be missed). `color` is the index of the color in the palette of
// the atlas (AtlasColor). The glyphs are baked into the atlas as they are met (AtlasReserveText does it first, so that a full atlas is known before anything is drawn); when the atlas or
// `out` is full the text stops there and `complete` is false.
TextQuads :: proc(atlas: ^Atlas, text: string, origin: Vec2, pixels_per_em: f32, out: []TextVertex, options: TextOptions = {}, color: u8 = 0) -> (count: int, pen: Vec2, complete: bool, missing: int) {
    face: int = int(options.face) if options.face < ATLAS_FACES && atlas.faces[options.face] != nil else 0
    font: ^Font = AtlasFace(atlas, face)
    wrap: f32 = options.wrap_width / pixels_per_em if options.wrap_width > 0 else 0
    tab: int = options.tab_columns if options.tab_columns > 0 else 4
    spacing: f32 = options.line_spacing if options.line_spacing > 0 else 1
    line_height: f32 = FontLineHeight(font) * spacing
    space: f32 = FontAdvance(font, FontGlyph(font, ' '))
    x: f32                      // em units from the start of the line
    line: int
    previous: int
    complete = true
    turn: TextTurn = TextTurnMake(origin, options.rotation)
    snap: bool = options.snap_to_pixels && options.rotation == 0
    missing_index: u8 = color
    missing_known: bool
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
        glyph: int = FontResolve(font, character)
        if character == ' ' && wrap > 0 && x > 0 && x + space + wordWidth(font, text, i, glyph) > wrap {
            x, previous = 0, 0
            line += 1
            continue
        }
        if previous != 0 { x += FontKerning(font, previous, glyph) }
        previous = glyph
        instance: GlyphInstance = {glyph = glyph, face = u8(face), pixels_per_em = pixels_per_em, color = color, alpha = 255}
        baseline: f32 = f32(line) * line_height * pixels_per_em
        left: f32 = x * pixels_per_em
        if snap {
            baseline = math.round(origin.y + baseline) - origin.y
            left = math.round(origin.x + left) - origin.x
        }
        instance.position = {left, baseline}
        if glyph == GlyphMissing(font) {
            missing += 1
            if !missing_known {
                rgba: [4]u8 = options.missing_color if options.missing_color != {} else {255, 0, 255, 255}
                if index, ok := AtlasColor(atlas, rgba); ok { missing_index = index }
                missing_known = true
            }
            instance.color = missing_index
        }
        emitted, ok := EmitGlyph(atlas, instance, turn, out[count:])
        if !ok {
            complete = false
            break
        }
        count += emitted
        x += FontAdvance(font, glyph)
    }
    pen = TextTurnPoint(turn, {x * pixels_per_em, f32(line) * line_height * pixels_per_em})
    return
}

// For text that is placed by a box: `line_height` is the height of the box of a line in pixels (the ascent and the descent of the font, which is what a measured text is high), the size
// that user interfaces give a font. The pixels to the em that gives it, and how far the baseline is below the top of the box.
TextBox :: proc(font: ^Font, line_height: f32) -> (pixels_per_em: f32, baseline: f32) {
    box: f32 = font.ascent - font.descent
    pixels_per_em = line_height / box if box > 0 else line_height
    return pixels_per_em, font.ascent * pixels_per_em
}
