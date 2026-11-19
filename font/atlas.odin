package font

// The glyph data that the GPU reads, for one of the two methods. Everything is in one array of texels of four floats (a texture of ATLAS_WIDTH texels per row, in whatever pixel format
// holds four 32 bit floats), so a glue needs one texture, one sampler-less fetch (`texelFetch` / `Load`) and no vertex format that the frameworks lack. The array is the caller's (`texels`):
// a glyph is baked the first time it is asked for, and an atlas that is full says so instead of growing.
//
//     texels := make([]f32, 4 * 4096 * 256)                  // 4096 x 256 texels = 16 MB: some thousands of glyphs
//     slots := make([]i32, font.glyph_count)
//     atlas: font.Atlas
//     font.AtlasInit(&atlas, &font, .SLUG, texels, slots)
//     slot, ok := font.AtlasGlyph(&atlas, glyph)             // a number that goes into the vertices of the glyph (a texel of the glyph table says the rest)
//
// Layout (texel index i is at column i mod ATLAS_WIDTH, row i / ATLAS_WIDTH):
//   0 ..< 2 * max_glyphs      the glyph table: two texels per slot
//        first:  (data start, bands in x - 1, bands in y - 1, 0)
//        second: (band scale x, band scale y, band offset x, band offset y): band index = floor(em coordinate * scale + offset)
//   after it                  the data of the glyphs, one after the other (see slug.odin and scanline.odin)
// A glyph with no outline gets no data: `AtlasGlyph` returns ok with the slot -1 and the layout draws nothing for it.

ATLAS_WIDTH :: 4096
ATLAS_LOG_WIDTH :: 12
ATLAS_TABLE_SLOTS :: 2048           // glyphs one atlas can hold at most
ATLAS_MAX_CURVES :: 1024            // curves in one glyph (after cutting them into monotonic pieces)
ATLAS_MAX_BANDS :: 24
BAND_EPSILON :: f32(1.0 / 1024)     // bands overlap by this much (em units) so that a curve that touches a border is in both

Atlas :: struct {
    font: ^Font,
    method: Method,
    texels: []f32,              // the caller's memory, 4 floats per texel
    slot_of_glyph: []i32,       // by glyph number: the slot, -1 not baked yet, -2 no outline (the caller's memory, font.glyph_count long)
    used: int,                  // texels in use (the table included)
    slots: int,                 // slots handed out
    version: u32,               // grows when texels changed: a glue uploads again when it differs from what it uploaded
    dirty_from: int,            // the texels from here to `used` changed since the glue last took them (AtlasTakeDirty)
    table_dirty: bool,          // a slot of the glyph table was written
}

AtlasInit :: proc(atlas: ^Atlas, font: ^Font, method: Method, texels: []f32, slot_of_glyph: []i32) {
    assert(len(texels) % 4 == 0 && len(texels) >= 4 * ATLAS_WIDTH, "room for at least one row")
    assert(len(slot_of_glyph) >= font.glyph_count)
    atlas^ = {font = font, method = method, texels = texels, slot_of_glyph = slot_of_glyph}
    for i in 0 ..< font.glyph_count { slot_of_glyph[i] = -1 }
    atlas.used = 2 * ATLAS_TABLE_SLOTS
    atlas.dirty_from = 0
    atlas.table_dirty = true
    for i in 0 ..< atlas.used * 4 { texels[i] = 0 }
}

// How many rows of the texture are in use (the glue makes a texture this high, or taller)
AtlasRows :: proc(atlas: ^Atlas) -> int {
    return (atlas.used + ATLAS_WIDTH - 1) / ATLAS_WIDTH
}

AtlasCapacityRows :: proc(atlas: ^Atlas) -> int {
    return len(atlas.texels) / 4 / ATLAS_WIDTH
}

RowRange :: struct {
    first: int,
    count: int,
}

// What changed since the last call, as ranges of whole rows of the texture (at most two: the glyph table, which is the first row, and the new data after it); a count of 0 is nothing. A glue
// uploads these rows. Call AtlasRows for the size of the texture.
AtlasTakeDirty :: proc(atlas: ^Atlas) -> (ranges: [2]RowRange) {
    if atlas.table_dirty {
        ranges[0] = {0, 1}
        atlas.table_dirty = false
    }
    if atlas.dirty_from < atlas.used {
        first: int = atlas.dirty_from / ATLAS_WIDTH
        last: int = (atlas.used + ATLAS_WIDTH - 1) / ATLAS_WIDTH
        ranges[1] = {max(first, 1), max(last - max(first, 1), 0)}
        atlas.dirty_from = atlas.used
    }
    return
}

@(private)
atlasTexel :: proc(atlas: ^Atlas, index: int) -> []f32 {
    return atlas.texels[index * 4:index * 4 + 4]
}

// The slot of a glyph: baked now if it was not. -1: there is nothing to draw (a space). ok is false when the atlas is full or the glyph is too complex for a fixed buffer.
AtlasGlyph :: proc(atlas: ^Atlas, glyph: int) -> (slot: int, ok: bool) {
    if glyph < 0 || glyph >= atlas.font.glyph_count { return -1, false }
    known: i32 = atlas.slot_of_glyph[glyph]
    if known >= 0 { return int(known), true }
    if known == -2 { return -1, true }

    curves: [ATLAS_MAX_CURVES]Curve
    count, curves_ok := FontGlyphCurves(atlas.font, glyph, curves[:])
    if !curves_ok { return -1, false }
    if count == 0 {
        atlas.slot_of_glyph[glyph] = -2
        return -1, true
    }
    if atlas.slots >= ATLAS_TABLE_SLOTS { return -1, false }
    start: int = atlas.used
    baked: bool
    switch atlas.method {
    case .SLUG: baked = slugBake(atlas, curves[:count], atlas.slots, start)
    case .SCANLINE: baked = scanlineBake(atlas, curves[:count], atlas.slots, start)
    }
    if !baked { return -1, false }
    slot = atlas.slots
    atlas.slots += 1
    atlas.table_dirty = true
    atlas.slot_of_glyph[glyph] = i32(slot)
    atlas.version += 1
    return slot, true
}

// The bounds of a set of curves
@(private)
curvesBox :: proc(curves: []Curve) -> (low: Vec2, high: Vec2) {
    low = {1e9, 1e9}
    high = {-1e9, -1e9}
    for curve in curves {
        for point in ([3]Vec2{curve.p0, curve.p1, curve.p2}) {
            low = {min(low.x, point.x), min(low.y, point.y)}
            high = {max(high.x, point.x), max(high.y, point.y)}
        }
    }
    return
}

// Writes the two texels of a glyph in the table
@(private)
atlasWriteSlot :: proc(atlas: ^Atlas, slot: int, start: int, bands_x: int, bands_y: int, low: Vec2, high: Vec2) {
    info: []f32 = atlasTexel(atlas, slot * 2)
    info[0], info[1], info[2], info[3] = f32(start), f32(bands_x - 1), f32(bands_y - 1), 0
    transform: []f32 = atlasTexel(atlas, slot * 2 + 1)
    size: Vec2 = {max(high.x - low.x, 1e-6), max(high.y - low.y, 1e-6)}
    scale: Vec2 = {f32(bands_x) / size.x, f32(bands_y) / size.y}
    transform[0], transform[1] = scale.x, scale.y
    transform[2], transform[3] = -low.x * scale.x, -low.y * scale.y
}

// A glyph that was baked: what the layout needs to place its quad
GlyphBox :: struct {
    low, high: Vec2,            // em units: the box around the outline
}

// The box around the outline of a glyph (the quad that is drawn is a bit bigger, see TextQuads)
AtlasGlyphBox :: proc(atlas: ^Atlas, glyph: int) -> (box: GlyphBox, ok: bool) {
    low, high, has := FontGlyphBox(atlas.font, glyph)
    return {low, high}, has
}
