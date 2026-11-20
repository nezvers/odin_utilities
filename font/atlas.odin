package font

// The glyph data that the GPU reads, for one of the two methods. Everything is in one array of texels of four floats (a texture of ATLAS_WIDTH texels per row, in whatever pixel format
// holds four 32 bit floats), so a glue needs one texture, one sampler-less fetch (`texelFetch` / `Load`) and no vertex format that the frameworks lack. The array is the caller's (`texels`):
// a glyph is baked the first time it is asked for, and an atlas that is full says so instead of growing.
//
//     texels := make([]f32, 4 * 4096 * 256)                  // 4096 x 256 texels = 16 MB: some thousands of glyphs
//     slots := make([]i32, font.FontSlotCount(&face))
//     atlas: font.Atlas
//     font.AtlasInit(&atlas, &font, .SLUG, texels, slots)
//     slot, ok := font.AtlasGlyph(&atlas, glyph)             // a number that goes into the vertices of the glyph (a texel of the glyph table says the rest)
//
// Layout (texel index i is at column i mod ATLAS_WIDTH, row i / ATLAS_WIDTH):
//   row 0                     the glyph table: two texels per slot
//        first:  (data start, bands in x - 1, bands in y - 1, 0)
//        second: (band scale x, band scale y, band offset x, band offset y): band index = floor(em coordinate * scale + offset)
//   row 1                     the palette: ATLAS_PALETTE colors (r, g, b, a as 0 to 1) that the vertices name by an index, so a batch can have text of many colors
//   after them                the data of the glyphs, one after the other (see slug.odin and scanline.odin)
// A glyph with no outline gets no data: `AtlasGlyph` returns ok with the slot -1 and the layout draws nothing for it.

ATLAS_WIDTH :: 4096
ATLAS_LOG_WIDTH :: 12
ATLAS_TABLE_SLOTS :: 2048           // glyphs one atlas can hold at most
ATLAS_PALETTE :: 256                // colors a batch of text can use (a vertex has a byte for it)
ATLAS_HEADER_TEXELS :: 2 * ATLAS_WIDTH
ATLAS_PALETTE_START :: ATLAS_WIDTH
ATLAS_MAX_CURVES :: 1024            // curves in one glyph (after cutting them into monotonic pieces)
ATLAS_MAX_BANDS :: 24
BAND_EPSILON :: f32(1.0 / 1024)     // bands overlap by this much (em units) so that a curve that touches a border is in both

ATLAS_FACES :: 16                   // fonts one atlas holds: regular, bold, italic, bold italic (a face is named by bit 0 = bold, bit 1 = italic), and four more that a program names itself (another weight, a code face, an icon font)

Atlas :: struct {
    font: ^Font,                // face 0 (the regular one)
    faces: [ATLAS_FACES]^Font,  // nil: the face is not there (rich text then makes it from the regular one: struck twice for bold, slanted for italic)
    face_slots: [ATLAS_FACES][]i32,
    method: Method,
    texels: []f32,              // the caller's memory, 4 floats per texel
    slot_of_glyph: []i32,       // by glyph number: the slot, -1 not baked yet, -2 no outline (the caller's memory, FontSlotCount(font) long: the glyphs of the font and the two special ones)
    used: int,                  // texels in use (the table included)
    slots: int,                 // slots handed out
    version: u32,               // grows when texels changed: a glue uploads again when it differs from what it uploaded
    dirty_from: int,            // the texels from here to `used` changed since the glue last took them (AtlasTakeDirty)
    table_dirty: bool,          // a slot of the glyph table was written
    palette: [ATLAS_PALETTE][4]u8, // the colors in the palette (what AtlasColor was asked for)
    palette_count: int,
    palette_dirty: bool,
}

AtlasInit :: proc(atlas: ^Atlas, font: ^Font, method: Method, texels: []f32, slot_of_glyph: []i32) {
    assert(len(texels) % 4 == 0 && len(texels) >= 4 * ATLAS_WIDTH * 3, "room for the two header rows and one row of data")
    assert(len(slot_of_glyph) >= FontSlotCount(font))
    atlas^ = {font = font, method = method, texels = texels, slot_of_glyph = slot_of_glyph}
    atlas.faces[0] = font
    atlas.face_slots[0] = slot_of_glyph
    for i in 0 ..< FontSlotCount(font) { slot_of_glyph[i] = -1 }
    atlas.used = ATLAS_HEADER_TEXELS
    atlas.dirty_from = ATLAS_HEADER_TEXELS
    atlas.table_dirty = true
    atlas.palette_dirty = true
    for i in 0 ..< atlas.used * 4 { texels[i] = 0 }
}

// The font of a face of a family (the regular one when the face is not there)
FaceOf :: proc(faces: ^[ATLAS_FACES]^Font, face: int) -> ^Font {
    if face > 0 && face < ATLAS_FACES && faces[face] != nil { return faces[face] }
    return faces[0]
}

// Adds a face of the family: `index` 1 is the bold one, 2 the italic and 3 the bold italic (0 is the font of AtlasInit). `slots` is the table of its glyphs (FontSlotCount(font) long, the
// caller's memory). All faces share the texture, the palette and the batch, so a text that mixes them is still one draw call.
AtlasAddFace :: proc(atlas: ^Atlas, index: int, font: ^Font, slots: []i32) -> bool {
    if index < 1 || index >= ATLAS_FACES || atlas.faces[index] != nil || len(slots) < FontSlotCount(font) { return false }
    atlas.faces[index] = font
    atlas.face_slots[index] = slots
    for i in 0 ..< FontSlotCount(font) { slots[i] = -1 }
    return true
}

// The font of a face (the regular one when the face is not there)
AtlasFace :: proc(atlas: ^Atlas, face: int) -> ^Font {
    if face > 0 && face < ATLAS_FACES && atlas.faces[face] != nil { return atlas.faces[face] }
    return atlas.font
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

// What changed since the last call, as ranges of whole rows of the texture (at most three: the glyph table, the palette and the new data after them); a count of 0 is nothing. A glue uploads
// these rows. Call AtlasRows for the size of the texture.
AtlasTakeDirty :: proc(atlas: ^Atlas) -> (ranges: [3]RowRange) {
    if atlas.table_dirty {
        ranges[0] = {0, 1}
        atlas.table_dirty = false
    }
    if atlas.palette_dirty {
        ranges[1] = {1, 1}
        atlas.palette_dirty = false
    }
    if atlas.dirty_from < atlas.used {
        first: int = max(atlas.dirty_from / ATLAS_WIDTH, 2)
        last: int = (atlas.used + ATLAS_WIDTH - 1) / ATLAS_WIDTH
        ranges[2] = {first, max(last - first, 0)}
        atlas.dirty_from = atlas.used
    }
    return
}

// The index of a color in the palette (added when it is not there): what a vertex of this color carries. False when the palette is full: flush what is batched, AtlasClearColors and ask again.
AtlasColor :: proc(atlas: ^Atlas, color: [4]u8) -> (index: u8, ok: bool) {
    for i in 0 ..< atlas.palette_count {
        if atlas.palette[i] == color { return u8(i), true }
    }
    if atlas.palette_count >= ATLAS_PALETTE { return 0, false }
    i: int = atlas.palette_count
    atlas.palette[i] = color
    texel: []f32 = atlasTexel(atlas, ATLAS_PALETTE_START + i)
    texel[0], texel[1], texel[2], texel[3] = f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255
    atlas.palette_count += 1
    atlas.palette_dirty = true
    return u8(i), true
}

AtlasClearColors :: proc(atlas: ^Atlas) {
    atlas.palette_count = 0
}

// Forgets every glyph that was baked (the memory is reused from the start) and the colors: for an atlas that is full. What is batched for the GPU refers to the old slots, so the glue draws it first.
AtlasClear :: proc(atlas: ^Atlas) {
    for face in 0 ..< ATLAS_FACES {
        if atlas.faces[face] == nil { continue }
        for i in 0 ..< FontSlotCount(atlas.faces[face]) { atlas.face_slots[face][i] = -1 }
    }
    atlas.used = ATLAS_HEADER_TEXELS
    atlas.dirty_from = ATLAS_HEADER_TEXELS
    atlas.slots = 0
    atlas.palette_count = 0
    atlas.table_dirty = true
    atlas.version += 1
}

// Bakes every glyph of a text. False when the atlas is full (clear it and ask again: a text of more different glyphs than an atlas holds cannot be drawn).
AtlasReserveText :: proc(atlas: ^Atlas, text: string, face: int = 0) -> bool {
    font: ^Font = AtlasFace(atlas, face)
    for character in text {
        glyph: int = FontResolve(font, character)
        if _, ok := AtlasGlyph(atlas, glyph, face); !ok { return false }
    }
    return true
}

@(private)
atlasTexel :: proc(atlas: ^Atlas, index: int) -> []f32 {
    return atlas.texels[index * 4:index * 4 + 4]
}

// The slot of a glyph: baked now if it was not. -1: there is nothing to draw (a space). ok is false when the atlas is full or the glyph is too complex for a fixed buffer.
AtlasGlyph :: proc(atlas: ^Atlas, glyph: int, face: int = 0) -> (slot: int, ok: bool) {
    font: ^Font = AtlasFace(atlas, face)
    slots: []i32 = atlas.face_slots[face if face > 0 && face < ATLAS_FACES && atlas.faces[face] != nil else 0]
    if glyph < 0 || glyph >= FontSlotCount(font) { return -1, false }
    known: i32 = slots[glyph]
    if known >= 0 { return int(known), true }
    if known == -2 { return -1, true }

    curves: [ATLAS_MAX_CURVES]Curve
    count, curves_ok := FontGlyphCurves(font, glyph, curves[:])
    if !curves_ok { return -1, false }
    if count == 0 {
        slots[glyph] = -2
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
    slots[glyph] = i32(slot)
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
