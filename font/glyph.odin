package font

// One glyph (or one filled rectangle) as a quad: what the layout of plain text and the layout of rich text both end in. A glyph instance says which glyph, where, how big and how it is moved
// (turned about a pivot, slanted for an italic), with which color of the palette and how transparent; EmitGlyph writes its six vertices. Everything is in pixels from the origin of the text.

import "core:math"

// A quad of a glyph
GlyphInstance :: struct {
    glyph: int,                 // a glyph of the font or a special one (FontResolve)
    position: Vec2,             // where the origin of the glyph is (on its baseline, at its left): pixels from the origin of the text, y down
    pixels_per_em: f32,         // size
    rotation: f32,              // radians, clockwise, around `pivot`
    pivot: Vec2,                // pixels from `position` (y down): where the rotation turns
    slant: f32,                 // how far right the top of an em goes: 0.2 makes an italic
    color: u8,                  // index in the palette of the atlas
    alpha: u8,                  // 255 opaque (this is not the alpha of the color: it multiplies it, per glyph)
}

// The turn of the whole text
TextTurn :: struct {
    origin: Vec2,               // where the text starts on the screen
    cos_angle: f32,
    sin_angle: f32,
}

TextTurnMake :: proc(origin: Vec2, rotation: f32) -> TextTurn {
    if rotation == 0 { return {origin, 1, 0} }
    return {origin, math.cos(rotation), math.sin(rotation)}
}

// A point of the text (pixels from its origin, y down) on the screen
TextTurnPoint :: proc(turn: TextTurn, local: Vec2) -> Vec2 {
    return turn.origin + Vec2{local.x * turn.cos_angle - local.y * turn.sin_angle, local.x * turn.sin_angle + local.y * turn.cos_angle}
}

// The six vertices of a glyph (the quad is its box and a margin of QUAD_MARGIN_PIXELS), written to `out`. False when the atlas is full or `out` too small; a glyph with nothing to draw (a
// space) writes nothing and is ok.
EmitGlyph :: proc(atlas: ^Atlas, instance: GlyphInstance, turn: TextTurn, out: []TextVertex) -> (count: int, ok: bool) {
    low, high, has_box := FontGlyphBox(atlas.font, instance.glyph)
    if !has_box { return 0, true }
    slot, baked := AtlasGlyph(atlas, instance.glyph)
    if !baked || len(out) < TEXT_VERTICES_PER_GLYPH { return 0, false }
    if slot < 0 { return 0, true }
    margin: f32 = QUAD_MARGIN_PIXELS / instance.pixels_per_em
    corner_low: Vec2 = low - {margin, margin}
    corner_high: Vec2 = high + {margin, margin}
    rotation_cos: f32 = 1
    rotation_sin: f32 = 0
    if instance.rotation != 0 { rotation_cos, rotation_sin = math.cos(instance.rotation), math.sin(instance.rotation) }
    // a corner of the box (em units, y up) as a point of the text
    corner :: proc(em: Vec2, instance: GlyphInstance, turn: TextTurn, rotation_cos: f32, rotation_sin: f32) -> TextVertex {
        local: Vec2 = {(em.x + instance.slant * em.y) * instance.pixels_per_em, -em.y * instance.pixels_per_em}
        local -= instance.pivot
        local = {local.x * rotation_cos - local.y * rotation_sin, local.x * rotation_sin + local.y * rotation_cos} + instance.pivot
        return {position = TextTurnPoint(turn, instance.position + local), uv = em, color = instance.color, alpha = instance.alpha}
    }
    a: TextVertex = corner({corner_low.x, corner_low.y}, instance, turn, rotation_cos, rotation_sin)
    b: TextVertex = corner({corner_high.x, corner_low.y}, instance, turn, rotation_cos, rotation_sin)
    c: TextVertex = corner({corner_high.x, corner_high.y}, instance, turn, rotation_cos, rotation_sin)
    d: TextVertex = corner({corner_low.x, corner_high.y}, instance, turn, rotation_cos, rotation_sin)
    a.slot, b.slot, c.slot, d.slot = u32(slot), u32(slot), u32(slot), u32(slot)
    out[0], out[1], out[2] = a, b, c
    out[3], out[4], out[5] = a, c, d
    return TEXT_VERTICES_PER_GLYPH, true
}

SOLID_PIXELS_PER_EM :: f32(100)

// A filled rectangle (pixels from the origin of the text: x, y, width, height) as the six vertices of a quad of the solid glyph: the edges are the edges of the quad (put them on whole pixels
// for a crisp line). Underlines, strike-through and backgrounds.
EmitRect :: proc(atlas: ^Atlas, rect: [4]f32, color: u8, alpha: u8, turn: TextTurn, out: []TextVertex) -> (count: int, ok: bool) {
    slot, baked := AtlasGlyph(atlas, GlyphSolid(atlas.font))
    if !baked || len(out) < TEXT_VERTICES_PER_GLYPH || slot < 0 { return 0, false }
    // em coordinates centered on the rectangle, at a fixed size: the solid glyph is much bigger than any rectangle, so the whole quad is inside of it
    half: Vec2 = {rect.z, rect.w} * 0.5 / SOLID_PIXELS_PER_EM
    make_vertex :: proc(x: f32, y: f32, em: Vec2, slot: int, color: u8, alpha: u8, turn: TextTurn) -> TextVertex {
        return {position = TextTurnPoint(turn, {x, y}), uv = em, slot = u32(slot), color = color, alpha = alpha}
    }
    a: TextVertex = make_vertex(rect.x, rect.y + rect.w, {-half.x, -half.y}, slot, color, alpha, turn)
    b: TextVertex = make_vertex(rect.x + rect.z, rect.y + rect.w, {half.x, -half.y}, slot, color, alpha, turn)
    c: TextVertex = make_vertex(rect.x + rect.z, rect.y, {half.x, half.y}, slot, color, alpha, turn)
    d: TextVertex = make_vertex(rect.x, rect.y, {-half.x, half.y}, slot, color, alpha, turn)
    out[0], out[1], out[2] = a, b, c
    out[3], out[4], out[5] = a, c, d
    return TEXT_VERTICES_PER_GLYPH, true
}
