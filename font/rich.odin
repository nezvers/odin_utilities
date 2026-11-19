package font

// Rich text with effects, in the manner of Godot's RichTextLabel: text with BBCode-like tags is parsed into glyphs and styles (RichParse), laid out into lines (RichLayout) and drawn with the
// effects at a point in time (RichDraw), which writes the quads into a buffer of the caller: the same vertices as plain text, so any renderer of the library draws them, batched with other text.
//
//     glyphs: [512]font.RichGlyph
//     styles: [64]font.RichStyle
//     lines: [32]font.RichLine
//     rich: font.RichText
//     font.RichInit(&rich, glyphs[:], styles[:], lines[:])
//     font.RichParse(&rich, "Hello [color=#ff8800]warm[/color] [wave amp=6 freq=4]world[/wave]!")
//     font.RichLayout(&rich, &face, 24, 400)                       // 24 pixels to the em, wrapped at 400 pixels
//     count, _ := font.RichDraw(&atlas, &rich, {20, 20}, seconds, vertices[:])         // every frame, with the time of the frame
//     font_raylib.RendererDraw(&renderer, vertices[:count])
//
// Tags (a closing tag `[/name]` ends the one that opened last with that name; `[lb]` is a `[`):
//   [b] [i] [u] [s]                              bold (the glyph is struck twice a little apart), italic (a slant), underline, strike-through
//   [color=#rrggbb] [color=name]                 #rgb, #rrggbb, #rrggbbaa or red, green, blue, yellow, orange, cyan, magenta, white, black, gray
//   [bgcolor=...]                                a filled box behind the glyphs
//   [size=28]                                    pixels to the em for the glyphs inside (the base size is the one given to RichLayout)
//   [outline size=2 color=#000000]               an outline of that width (the glyph is drawn around itself in eight places)
//   [shadow x=2 y=2 color=#00000080]             a copy under the glyph, moved by x and y
//   [center] [right]                             alignment of the lines whose first glyph is inside
//   effects (they move or color a glyph with the time):
//   [wave amp=6 freq=5]                          glyphs move up and down in a wave
//   [shake rate=20 level=3]                      glyphs jitter, `rate` times a second
//   [rainbow freq=1 sat=0.8 val=1]               the color goes round the hues
//   [fade start=4 length=14]                     glyphs from the `start`th of the tag fade out over `length` glyphs
//   [pulse freq=1 color=#ffffff40]               the color and the alpha move to `color` and back
//   [tornado radius=8 freq=1]                    glyphs go round in small circles
//   [name arg=...]                               your own effect, registered with RichCustomEffect
// A tag that is not known is shown as it was written and counted in `unknown_tags`. `visible_characters` (RichDrawOptions) shows only the first glyphs: a typewriter.

import "core:math"
import "core:unicode/utf8"

RICH_MAX_EFFECTS :: 4
RICH_MAX_DEPTH :: 24

RichEffectKind :: enum u8 {
    NONE,
    WAVE,
    SHAKE,
    RAINBOW,
    FADE,
    PULSE,
    TORNADO,
    CUSTOM,
}

RichEffect :: struct {
    kind: RichEffectKind,
    custom: u8,                 // CUSTOM: the index in the list of custom effects
    params: [4]f32,             // wave: amp, freq; shake: rate, level; rainbow: freq, sat, val; fade: start, length; pulse: freq; tornado: radius, freq; custom: its numbers a, b, c, d
    color: [4]u8,               // pulse
    first_glyph: int,           // the glyph where the tag opened: the position of a glyph inside of the effect is counted from it
}

RichAlign :: enum u8 {
    LEFT,
    CENTER,
    RIGHT,
}

RichStyle :: struct {
    color: [4]u8,
    background: [4]u8,          // alpha 0: none
    size: f32,                  // pixels to the em, 0: the base size
    bold, italic, underline, strike: bool,
    align: RichAlign,
    outline_size: f32,
    outline_color: [4]u8,
    shadow: Vec2,
    shadow_color: [4]u8,
    effects: [RICH_MAX_EFFECTS]RichEffect,
    effect_count: int,
}

RichGlyph :: struct {
    character: rune,
    glyph: int,                 // the glyph of the font, or the missing one
    style: u16,
    // set by RichLayout
    x: f32,                     // pixels from the left of the text to the pen position (after the alignment)
    baseline: f32,              // pixels from the top of the text to the baseline of its line
    line_top: f32,
    line_height: f32,
    size: f32,                  // pixels to the em
    advance: f32,               // pixels
    line: u16,
}

RichLine :: struct {
    first: int,                 // the glyph that starts the line
    count: int,
    width: f32,
    top: f32,
    baseline: f32,
    height: f32,
}

// A custom effect: a name for the tag and a proc that changes the state of a glyph
RichCustomEffect :: struct {
    name: string,
    apply: proc(state: ^RichGlyphState, index: int, run_index: int, time: f32, params: [4]f32, user: rawptr),
    user: rawptr,
}

// What an effect works on: where the glyph is moved, how it is turned and scaled (around its middle), its color (alpha 0 to 1 apart) and whether it is shown
RichGlyphState :: struct {
    offset: Vec2,               // pixels
    rotation: f32,              // radians
    scale: f32,
    color: [4]u8,
    alpha: f32,
    visible: bool,
}

RichText :: struct {
    glyphs: []RichGlyph,
    styles: []RichStyle,
    lines: []RichLine,
    glyph_count: int,
    style_count: int,
    line_count: int,
    size: Vec2,                 // after RichLayout: the size of the text in pixels
    missing: int,               // characters that the font does not have (they are drawn as boxes with a cross)
    unknown_tags: int,
    custom: []RichCustomEffect,
    base: RichStyle,            // what the text starts with (color, size 0): set it before RichParse for a text that is not white
}

RichInit :: proc(rich: ^RichText, glyphs: []RichGlyph, styles: []RichStyle, lines: []RichLine, custom: []RichCustomEffect = nil) {
    rich^ = {glyphs = glyphs, styles = styles, lines = lines, custom = custom}
    rich.base.color = {255, 255, 255, 255}
    rich.base.outline_color = {0, 0, 0, 255}
    rich.base.shadow_color = {0, 0, 0, 128}
}

// ------------------------------------------------------------------------------------------------------------------------
// Parsing

@(private)
richColor :: proc(text: string) -> (color: [4]u8, ok: bool) {
    names: [10]struct {name: string, color: [4]u8} = {
        {"white", {255, 255, 255, 255}}, {"black", {0, 0, 0, 255}}, {"red", {255, 64, 64, 255}}, {"green", {64, 220, 96, 255}}, {"blue", {80, 140, 255, 255}},
        {"yellow", {255, 230, 80, 255}}, {"orange", {255, 160, 50, 255}}, {"cyan", {80, 230, 230, 255}}, {"magenta", {255, 90, 220, 255}}, {"gray", {150, 150, 160, 255}},
    }
    for entry in names {
        if entry.name == text { return entry.color, true }
    }
    rgb, alpha, hex_ok := ColorFromHexBytes(text)
    if !hex_ok { return {}, false }
    return {rgb[0], rgb[1], rgb[2], alpha}, true
}

// "#rgb", "#rrggbb" or "#rrggbbaa" (the # is optional) as bytes
@(private)
ColorFromHexBytes :: proc(text: string) -> (rgb: [3]u8, alpha: u8, ok: bool) {
    body: string = text[1:] if len(text) > 0 && text[0] == '#' else text
    digit :: proc(character: u8) -> (value: int, ok: bool) {
        switch character {
        case '0' ..= '9': return int(character - '0'), true
        case 'a' ..= 'f': return int(character - 'a') + 10, true
        case 'A' ..= 'F': return int(character - 'A') + 10, true
        }
        return 0, false
    }
    values: [4]int = {0, 0, 0, 255}
    switch len(body) {
    case 3:
        for i in 0 ..< 3 {
            d, valid := digit(body[i])
            if !valid { return }
            values[i] = d * 17
        }
    case 6, 8:
        for i in 0 ..< len(body) / 2 {
            high, valid_high := digit(body[i * 2])
            low, valid_low := digit(body[i * 2 + 1])
            if !valid_high || !valid_low { return }
            values[i] = high * 16 + low
        }
    case:
        return
    }
    return {u8(values[0]), u8(values[1]), u8(values[2])}, u8(values[3]), true
}

@(private)
richNumber :: proc(text: string) -> (value: f32, ok: bool) {
    negative: bool
    i: int
    if i < len(text) && (text[i] == '-' || text[i] == '+') {
        negative = text[i] == '-'
        i += 1
    }
    whole: f32
    digits: int
    for i < len(text) && text[i] >= '0' && text[i] <= '9' {
        whole = whole * 10 + f32(text[i] - '0')
        i += 1
        digits += 1
    }
    fraction: f32
    if i < len(text) && text[i] == '.' {
        i += 1
        scale: f32 = 0.1
        for i < len(text) && text[i] >= '0' && text[i] <= '9' {
            fraction += f32(text[i] - '0') * scale
            scale *= 0.1
            i += 1
            digits += 1
        }
    }
    if digits == 0 || i != len(text) { return 0, false }
    value = whole + fraction
    return -value if negative else value, true
}

@(private)
TagParams :: struct {
    name: string,
    closing: bool,
    first: string,              // the value of `name=value`
    keys: [8]string,
    values: [8]string,
    count: int,
}

@(private)
tagParse :: proc(body: string) -> (tag: TagParams) {
    text: string = body
    if len(text) > 0 && text[0] == '/' {
        tag.closing = true
        text = text[1:]
    }
    // the name runs up to a space or an equal sign
    end: int
    for end < len(text) && text[end] != ' ' && text[end] != '=' { end += 1 }
    tag.name = text[:end]
    text = text[end:]
    for len(text) > 0 {
        if text[0] == ' ' {
            text = text[1:]
            continue
        }
        // key=value or =value (the first value of the tag)
        key_end: int
        for key_end < len(text) && text[key_end] != '=' && text[key_end] != ' ' { key_end += 1 }
        key: string = text[:key_end]
        text = text[key_end:]
        value: string
        if len(text) > 0 && text[0] == '=' {
            text = text[1:]
            value_end: int
            for value_end < len(text) && text[value_end] != ' ' { value_end += 1 }
            value = text[:value_end]
            text = text[value_end:]
        }
        if key == "" {
            tag.first = value
        } else if tag.count < len(tag.keys) {
            tag.keys[tag.count], tag.values[tag.count] = key, value
            tag.count += 1
        }
    }
    return
}

@(private)
tagNumber :: proc(tag: TagParams, key: string, fallback: f32) -> f32 {
    for i in 0 ..< tag.count {
        if tag.keys[i] == key {
            value, ok := richNumber(tag.values[i])
            if ok { return value }
        }
    }
    return fallback
}

@(private)
tagColor :: proc(tag: TagParams, key: string, fallback: [4]u8) -> [4]u8 {
    for i in 0 ..< tag.count {
        if tag.keys[i] == key {
            if color, ok := richColor(tag.values[i]); ok { return color }
        }
    }
    return fallback
}

@(private)
OpenTag :: struct {
    name: string,
    saved: RichStyle,
}

// Parses the markup into the glyphs and styles of `rich` (what was there is replaced). False when the glyphs or the styles do not fit (what fits is kept).
RichParse :: proc(rich: ^RichText, markup: string) -> bool {
    rich.glyph_count, rich.style_count, rich.line_count, rich.missing, rich.unknown_tags = 0, 0, 0, 0, 0
    current: RichStyle = rich.base
    stack: [RICH_MAX_DEPTH]OpenTag
    depth: int
    style_index: int = -1
    fits: bool = true

    append_glyph :: proc(rich: ^RichText, character: rune, current: ^RichStyle, style_index: ^int) -> bool {
        if rich.glyph_count >= len(rich.glyphs) { return false }
        if style_index^ < 0 || rich.styles[style_index^] != current^ {
            if rich.style_count >= len(rich.styles) { return false }
            rich.styles[rich.style_count] = current^
            style_index^ = rich.style_count
            rich.style_count += 1
        }
        rich.glyphs[rich.glyph_count] = {character = character, style = u16(style_index^)}
        rich.glyph_count += 1
        return true
    }

    i: int
    for i < len(markup) {
        character, width := utf8.decode_rune_in_string(markup[i:])
        if character != '[' {
            if !append_glyph(rich, character, &current, &style_index) { fits = false; break }
            i += width
            continue
        }
        close: int = -1
        for j in i + 1 ..< len(markup) {
            if markup[j] == ']' { close = j; break }
            if markup[j] == '[' { break }
        }
        if close < 0 {
            if !append_glyph(rich, character, &current, &style_index) { fits = false; break }
            i += width
            continue
        }
        tag: TagParams = tagParse(markup[i + 1:close])
        handled: bool = true
        if tag.name == "lb" && !tag.closing {
            handled = append_glyph(rich, '[', &current, &style_index)
            if !handled { fits = false; break }
            i = close + 1
            continue
        }
        if tag.closing {
            // the last open tag of this name: its state comes back
            found: int = -1
            for k := depth - 1; k >= 0; k -= 1 {
                if stack[k].name == tag.name { found = k; break }
            }
            if found >= 0 {
                current = stack[found].saved
                depth = found
            } else {
                handled = false
            }
        } else if depth >= RICH_MAX_DEPTH {
            handled = false
        } else {
            saved: RichStyle = current
            handled = richOpenTag(rich, &current, tag)
            if handled {
                stack[depth] = {tag.name, saved}
                depth += 1
            }
        }
        if !handled {
            // shown as it was written
            rich.unknown_tags += 1
            for k in i ..= close {
                if !append_glyph(rich, rune(markup[k]), &current, &style_index) { fits = false; break }
            }
        }
        i = close + 1
    }
    return fits
}

// Applies an opening tag to the style; false when the tag is not known
@(private)
richOpenTag :: proc(rich: ^RichText, current: ^RichStyle, tag: TagParams) -> bool {
    value_color :: proc(tag: TagParams, fallback: [4]u8) -> [4]u8 {
        if color, ok := richColor(tag.first); ok { return color }
        return fallback
    }
    add_effect :: proc(rich: ^RichText, current: ^RichStyle, effect: RichEffect) -> bool {
        if current.effect_count >= RICH_MAX_EFFECTS { return false }
        entry: RichEffect = effect
        entry.first_glyph = rich.glyph_count
        current.effects[current.effect_count] = entry
        current.effect_count += 1
        return true
    }
    switch tag.name {
    case "b": current.bold = true
    case "i": current.italic = true
    case "u": current.underline = true
    case "s": current.strike = true
    case "color": current.color = value_color(tag, current.color)
    case "bgcolor": current.background = value_color(tag, {255, 255, 255, 80})
    case "size":
        value, ok := richNumber(tag.first)
        if !ok { return false }
        current.size = value
    case "center": current.align = .CENTER
    case "right": current.align = .RIGHT
    case "outline":
        current.outline_size = tagNumber(tag, "size", 1)
        current.outline_color = tagColor(tag, "color", {0, 0, 0, 255})
    case "shadow":
        current.shadow = {tagNumber(tag, "x", 1), tagNumber(tag, "y", 1)}
        current.shadow_color = tagColor(tag, "color", {0, 0, 0, 128})
    case "wave": return add_effect(rich, current, {kind = .WAVE, params = {tagNumber(tag, "amp", 6), tagNumber(tag, "freq", 5), 0, 0}})
    case "shake": return add_effect(rich, current, {kind = .SHAKE, params = {tagNumber(tag, "rate", 20), tagNumber(tag, "level", 3), 0, 0}})
    case "rainbow": return add_effect(rich, current, {kind = .RAINBOW, params = {tagNumber(tag, "freq", 1), tagNumber(tag, "sat", 0.8), tagNumber(tag, "val", 1), 0}})
    case "fade": return add_effect(rich, current, {kind = .FADE, params = {tagNumber(tag, "start", 4), tagNumber(tag, "length", 14), 0, 0}})
    case "pulse": return add_effect(rich, current, {kind = .PULSE, params = {tagNumber(tag, "freq", 1), 0, 0, 0}, color = tagColor(tag, "color", {255, 255, 255, 64})})
    case "tornado": return add_effect(rich, current, {kind = .TORNADO, params = {tagNumber(tag, "radius", 8), tagNumber(tag, "freq", 1), 0, 0}})
    case:
        for entry, k in rich.custom {
            if entry.name == tag.name {
                return add_effect(rich, current, {kind = .CUSTOM, custom = u8(k), params = {tagNumber(tag, "a", 0), tagNumber(tag, "b", 0), tagNumber(tag, "c", 0), tagNumber(tag, "d", 0)}})
            }
        }
        return false
    }
    return true
}

// ------------------------------------------------------------------------------------------------------------------------
// Layout

// Places the glyphs: `base_size` is the size (pixels to the em) of the glyphs that have none of their own, `wrap_width` breaks lines at spaces (0: only new lines), `line_spacing` is a factor of
// the line height (0 is 1). Sets the size of the text. False when the lines do not fit.
RichLayout :: proc(rich: ^RichText, font: ^Font, base_size: f32, wrap_width: f32 = 0, line_spacing: f32 = 0) -> bool {
    spacing: f32 = line_spacing if line_spacing > 0 else 1
    rich.line_count = 0
    rich.size = {}
    rich.missing = 0
    fits: bool = true
    y: f32
    widest: f32
    start: int
    for {
        // one line: the glyphs from `start` to a new line or to where the next word does not fit
        pen: f32
        previous: int
        previous_size: f32
        ascent, descent, gap: f32
        i: int = start
        for i < rich.glyph_count {
            glyph: ^RichGlyph = &rich.glyphs[i]
            style: ^RichStyle = &rich.styles[glyph.style]
            size: f32 = style.size if style.size > 0 else base_size
            if glyph.character == '\n' {
                glyph.glyph, glyph.size, glyph.advance, glyph.x = 0, size, 0, pen
                ascent = max(ascent, font.ascent * size)
                descent = max(descent, -font.descent * size)
                i += 1
                break
            }
            character: rune = ' ' if glyph.character == '\t' else glyph.character
            resolved: int = FontResolve(font, character)
            space_advance: f32 = FontAdvance(font, resolved) * size
            if character == ' ' && wrap_width > 0 && pen > 0 {
                // a space in front of a word that does not fit: the line ends with the space
                word: f32
                for k := i + 1; k < rich.glyph_count; k += 1 {
                    next: ^RichGlyph = &rich.glyphs[k]
                    if next.character == ' ' || next.character == '\n' || next.character == '\t' { break }
                    next_style: ^RichStyle = &rich.styles[next.style]
                    word += FontAdvance(font, FontResolve(font, next.character)) * (next_style.size if next_style.size > 0 else base_size)
                }
                if pen + space_advance + word > wrap_width {
                    glyph.glyph, glyph.size, glyph.advance, glyph.x = resolved, size, 0, pen
                    ascent = max(ascent, font.ascent * size)
                    descent = max(descent, -font.descent * size)
                    i += 1
                    break
                }
            }
            if previous != 0 && previous_size == size { pen += FontKerning(font, previous, resolved) * size }
            glyph.glyph, glyph.size, glyph.advance, glyph.x = resolved, size, space_advance, pen
            if resolved == GlyphMissing(font) { rich.missing += 1 }
            pen += glyph.advance
            previous, previous_size = resolved, size
            ascent = max(ascent, font.ascent * size)
            descent = max(descent, -font.descent * size)
            gap = max(gap, font.line_gap * size)
            i += 1
        }
        if ascent == 0 && descent == 0 { ascent, descent, gap = font.ascent * base_size, -font.descent * base_size, font.line_gap * base_size }
        height: f32 = ascent + descent
        if rich.line_count < len(rich.lines) {
            rich.lines[rich.line_count] = {first = start, count = i - start, width = pen, top = y, baseline = y + ascent, height = height}
            for k in start ..< i {
                glyph: ^RichGlyph = &rich.glyphs[k]
                glyph.baseline, glyph.line_top, glyph.line_height, glyph.line = y + ascent, y, height, u16(rich.line_count)
            }
            rich.line_count += 1
        } else {
            fits = false
        }
        widest = max(widest, pen)
        y += (height + gap) * spacing
        start = i
        if start >= rich.glyph_count { break }
    }
    // alignment: a line goes to the left, the middle or the right of the width of the text (or of the room to wrap in)
    room: f32 = wrap_width if wrap_width > 0 else widest
    for line in rich.lines[:rich.line_count] {
        if line.count == 0 { continue }
        offset: f32
        switch rich.styles[rich.glyphs[line.first].style].align {
        case .LEFT: continue
        case .CENTER: offset = (room - line.width) * 0.5
        case .RIGHT: offset = room - line.width
        }
        for k in line.first ..< line.first + line.count { rich.glyphs[k].x += max(offset, 0) }
    }
    rich.size = {widest, y}
    return fits
}

// ------------------------------------------------------------------------------------------------------------------------
// Drawing

RichDrawOptions :: struct {
    typewriter: bool,           // show only the first `visible_characters` glyphs (a text that appears letter by letter)
    visible_characters: int,
    rotation: f32,              // radians, the whole text turned around its origin
    snap_to_pixels: bool,       // the line positions are rounded to whole pixels (only without a rotation)
}

RichDrawResult :: struct {
    count: int,                 // vertices written
    complete: bool,             // everything fit; false: `out` was full, the atlas was full or the palette was
    palette_full: bool,         // the palette of the atlas has no room for a color: draw what is batched, AtlasClearColors and call again
    atlas_full: bool,
}

@(private)
richHash :: proc(a: int, b: int) -> f32 {
    value: u32 = u32(a) * 374761393 + u32(b) * 668265263
    value = (value ~ (value >> 13)) * 1274126177
    value ~= value >> 16
    return f32(value & 0xFFFF) / 65535 * 2 - 1
}

@(private)
richHue :: proc(hue: f32, saturation: f32, value: f32) -> [4]u8 {
    steps: f32 = 24
    h: f32 = math.floor((hue - math.floor(hue)) * steps) / steps * 6
    sector: int = int(h)
    f: f32 = h - f32(sector)
    p: f32 = value * (1 - saturation)
    q: f32 = value * (1 - saturation * f)
    t: f32 = value * (1 - saturation * (1 - f))
    r, g, b: f32
    switch sector % 6 {
    case 0: r, g, b = value, t, p
    case 1: r, g, b = q, value, p
    case 2: r, g, b = p, value, t
    case 3: r, g, b = p, q, value
    case 4: r, g, b = t, p, value
    case: r, g, b = value, p, q
    }
    return {u8(clamp(r, 0, 1) * 255 + 0.5), u8(clamp(g, 0, 1) * 255 + 0.5), u8(clamp(b, 0, 1) * 255 + 0.5), 255}
}

// The state of a glyph at a time: what the effects of its style do to it
RichGlyphStateAt :: proc(rich: ^RichText, index: int, time: f32) -> RichGlyphState {
    glyph: ^RichGlyph = &rich.glyphs[index]
    style: ^RichStyle = &rich.styles[glyph.style]
    state: RichGlyphState = {scale = 1, color = style.color, alpha = 1, visible = true}
    for effect in style.effects[:style.effect_count] {
        run: int = index - effect.first_glyph
        switch effect.kind {
        case .NONE:
        case .WAVE:
            state.offset.y += math.sin(time * effect.params[1] + f32(run) * 0.6) * effect.params[0]
        case .SHAKE:
            tick: int = int(time * effect.params[0])
            state.offset.x += richHash(index, tick) * effect.params[1]
            state.offset.y += richHash(index + 7919, tick) * effect.params[1]
        case .RAINBOW:
            state.color = richHue(time * effect.params[0] + f32(run) * 0.06, effect.params[1], effect.params[2])
            state.color.a = style.color.a
        case .FADE:
            state.alpha *= 1 - clamp((f32(run) - effect.params[0]) / max(effect.params[1], 0.0001), 0, 1)
        case .PULSE:
            wave: f32 = math.sin(time * effect.params[0] * 2 * math.PI) * 0.5 + 0.5
            wave = math.floor(wave * 8 + 0.5) / 8
            for channel in 0 ..< 3 { state.color[channel] = u8(f32(state.color[channel]) + (f32(effect.color[channel]) - f32(state.color[channel])) * wave) }
            state.alpha *= 1 + (f32(effect.color.a) / 255 - 1) * wave
        case .TORNADO:
            angle: f32 = time * effect.params[1] * 2 * math.PI + f32(run) * 0.6
            state.offset += {math.cos(angle), math.sin(angle)} * effect.params[0]
        case .CUSTOM:
            if int(effect.custom) < len(rich.custom) {
                custom: RichCustomEffect = rich.custom[effect.custom]
                if custom.apply != nil { custom.apply(&state, index, run, time, effect.params, custom.user) }
            }
        }
    }
    return state
}

// The quads of the text at `time` (seconds), moved to `origin` on the screen, into `out`: for every glyph the background, the shadow, the outline, the glyph (struck twice for a bold) and the
// lines of an underline or a strike-through, in that order, so that the text is on top. The palette of the atlas gets the colors that are used. See RichDrawResult.
RichDraw :: proc(atlas: ^Atlas, rich: ^RichText, origin: Vec2, time: f32, out: []TextVertex, options: RichDrawOptions = {}) -> (result: RichDrawResult) {
    turn: TextTurn = TextTurnMake(origin, options.rotation)
    snap: bool = options.snap_to_pixels && options.rotation == 0
    result.complete = true
    color_of :: proc(atlas: ^Atlas, color: [4]u8, result: ^RichDrawResult) -> (index: u8, ok: bool) {
        index, ok = AtlasColor(atlas, color)
        if !ok { result.palette_full = true }
        return
    }
    emit_glyph :: proc(atlas: ^Atlas, instance: GlyphInstance, turn: TextTurn, out: []TextVertex, result: ^RichDrawResult) -> bool {
        added, ok := EmitGlyph(atlas, instance, turn, out[result.count:])
        if !ok {
            result.atlas_full = true
            return false
        }
        result.count += added
        return true
    }
    emit_rect :: proc(atlas: ^Atlas, rect: [4]f32, color: u8, alpha: u8, turn: TextTurn, out: []TextVertex, result: ^RichDrawResult) -> bool {
        added, ok := EmitRect(atlas, rect, color, alpha, turn, out[result.count:])
        if !ok {
            result.atlas_full = true
            return false
        }
        result.count += added
        return true
    }
    for index in 0 ..< rich.glyph_count {
        glyph: ^RichGlyph = &rich.glyphs[index]
        if glyph.character == '\n' { continue }
        style: ^RichStyle = &rich.styles[glyph.style]
        if options.typewriter && index >= options.visible_characters { continue }
        // a glyph needs room for everything it is drawn with: the worst case, so that the glyphs before it are whole
        if len(out) - result.count < 100 * TEXT_VERTICES_PER_GLYPH / 6 {
            result.complete = false
            break
        }
        state: RichGlyphState = RichGlyphStateAt(rich, index, time)
        if !state.visible { continue }
        alpha: u8 = u8(clamp(state.alpha, 0, 1) * 255 + 0.5)
        position: Vec2 = {glyph.x, glyph.baseline} + state.offset
        if snap { position = {math.round(origin.x + position.x) - origin.x, math.round(origin.y + position.y) - origin.y} }
        size: f32 = glyph.size * state.scale
        pivot: Vec2 = {glyph.advance * 0.5, -glyph.size * 0.3}
        if state.scale != 1 { position += pivot * (1 - state.scale) }
        instance: GlyphInstance = {glyph = glyph.glyph, position = position, pixels_per_em = size, rotation = state.rotation, pivot = pivot, slant = 0.2 if style.italic else 0, alpha = alpha}
        // a character that the font lacks is the box, in its own color
        main_color: [4]u8 = state.color
        if glyph.glyph == GlyphMissing(atlas.font) { main_color = {255, 0, 255, 255} }

        if style.background.a > 0 {
            index_color, ok := color_of(atlas, style.background, &result)
            if !ok { result.complete = false; break }
            if !emit_rect(atlas, {glyph.x, glyph.line_top, max(glyph.advance, 1), glyph.line_height}, index_color, alpha, turn, out, &result) { result.complete = false; break }
        }
        if style.shadow != {} {
            index_color, ok := color_of(atlas, style.shadow_color, &result)
            if !ok { result.complete = false; break }
            shadow: GlyphInstance = instance
            shadow.position += style.shadow
            shadow.color = index_color
            if !emit_glyph(atlas, shadow, turn, out, &result) { result.complete = false; break }
        }
        if style.outline_size > 0 {
            index_color, ok := color_of(atlas, style.outline_color, &result)
            if !ok { result.complete = false; break }
            ring: GlyphInstance = instance
            ring.color = index_color
            for step in 0 ..< 8 {
                angle: f32 = f32(step) * math.PI / 4
                ring.position = instance.position + Vec2{math.cos(angle), math.sin(angle)} * style.outline_size
                if !emit_glyph(atlas, ring, turn, out, &result) { result.complete = false; break }
            }
        }
        index_main, color_ok := color_of(atlas, main_color, &result)
        if !color_ok { result.complete = false; break }
        instance.color = index_main
        if !emit_glyph(atlas, instance, turn, out, &result) { result.complete = false; break }
        if style.bold {
            struck: GlyphInstance = instance
            struck.position.x += 0.035 * size
            if !emit_glyph(atlas, struck, turn, out, &result) { result.complete = false; break }
        }
        thickness: f32 = max(math.round(0.06 * size), 1)
        if style.underline {
            line_y: f32 = math.round(position.y + 0.12 * size)
            if !emit_rect(atlas, {position.x, line_y, glyph.advance, thickness}, index_main, alpha, turn, out, &result) { result.complete = false; break }
        }
        if style.strike {
            line_y: f32 = math.round(position.y - 0.30 * size)
            if !emit_rect(atlas, {position.x, line_y, glyph.advance, thickness}, index_main, alpha, turn, out, &result) { result.complete = false; break }
        }
    }
    return
}
