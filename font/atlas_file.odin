package font

// Baking from the program's side: choose the glyphs that are baked before the first frame (a range of characters, the characters of a text, every glyph of the font that fits), and keep what was
// baked as bytes (a file, an embedded asset) that is read back into an atlas later, so that a program starts with its glyphs ready and does no baking at run time. The font file is still
// needed (for the advances, the kerning and the layout); the file holds the data that the GPU reads: the glyph table, the palette and the curves of every baked glyph.
//
//     font.AtlasBakeRange(&atlas, 32, 126)                         // ASCII
//     size := font.AtlasWriteSize(&atlas)
//     bytes := make([]u8, size)
//     font.AtlasWrite(&atlas, bytes)                               // save these
//     ...
//     font.AtlasInit(&atlas, &face, .SLUG, texels, slots)          // the next run
//     font.AtlasRead(&atlas, bytes)                                // the same glyphs, no baking
//
// `odin run font/tool/bake` makes such a file from a font file.

import "core:mem"

ATLAS_FILE_MAGIC :: u32(0x4C544146)         // "FATL"
ATLAS_FILE_VERSION :: u32(1)

@(private)
AtlasFileHeader :: struct #packed {
    magic: u32,
    version: u32,
    method: u32,
    glyph_count: u32,           // of the font the atlas was baked from: the file only fits that font
    units_per_em: f32,
    slots: u32,
    palette_count: u32,
    data_texels: u32,           // the texels after the two header rows
    used_slot_entries: u32,     // how many entries of slot_of_glyph follow
}

// Bakes the glyphs of the characters from `first` to `last` (those that the font has). Returns how many were baked and false when the atlas became full.
AtlasBakeRange :: proc(atlas: ^Atlas, first: rune, last: rune) -> (baked: int, ok: bool) {
    for character in first ..= last {
        if !FontHasGlyph(atlas.font, character) { continue }
        glyph: int = FontGlyph(atlas.font, character)
        before: i32 = atlas.slot_of_glyph[glyph]
        if _, glyph_ok := AtlasGlyph(atlas, glyph); !glyph_ok { return baked, false }
        if before == -1 { baked += 1 }
    }
    return baked, true
}

// Bakes every glyph of the font that fits (and the two special ones). False when some did not fit.
AtlasBakeAll :: proc(atlas: ^Atlas) -> (baked: int, ok: bool) {
    ok = true
    for glyph in 0 ..< FontSlotCount(atlas.font) {
        before: i32 = atlas.slot_of_glyph[glyph]
        if _, glyph_ok := AtlasGlyph(atlas, glyph); !glyph_ok {
            ok = false
            continue
        }
        if before == -1 { baked += 1 }
    }
    return
}

// How many bytes AtlasWrite needs
AtlasWriteSize :: proc(atlas: ^Atlas) -> int {
    return size_of(AtlasFileHeader) + FontSlotCount(atlas.font) * size_of(i32) + atlas.palette_count * 4 + (2 * atlas.slots + (atlas.used - ATLAS_HEADER_TEXELS)) * 16
}

// The baked glyphs and the palette as bytes. False when `out` is too small (AtlasWriteSize).
AtlasWrite :: proc(atlas: ^Atlas, out: []u8) -> (written: int, ok: bool) {
    needed: int = AtlasWriteSize(atlas)
    if len(out) < needed { return 0, false }
    header: AtlasFileHeader = {
        magic = ATLAS_FILE_MAGIC, version = ATLAS_FILE_VERSION, method = u32(atlas.method), glyph_count = u32(atlas.font.glyph_count), units_per_em = atlas.font.units_per_em,
        slots = u32(atlas.slots), palette_count = u32(atlas.palette_count), data_texels = u32(atlas.used - ATLAS_HEADER_TEXELS), used_slot_entries = u32(FontSlotCount(atlas.font)),
    }
    at: int
    mem.copy(&out[at], &header, size_of(header))
    at += size_of(header)
    mem.copy(&out[at], raw_data(atlas.slot_of_glyph), FontSlotCount(atlas.font) * size_of(i32))
    at += FontSlotCount(atlas.font) * size_of(i32)
    mem.copy(&out[at], &atlas.palette[0], atlas.palette_count * 4)
    at += atlas.palette_count * 4
    table_bytes: int = 2 * atlas.slots * 16
    mem.copy(&out[at], raw_data(atlas.texels), table_bytes)
    at += table_bytes
    data_bytes: int = (atlas.used - ATLAS_HEADER_TEXELS) * 16
    mem.copy(&out[at], &atlas.texels[ATLAS_HEADER_TEXELS * 4], data_bytes)
    at += data_bytes
    return at, true
}

// Loads what AtlasWrite wrote into an atlas that was just made with AtlasInit (the same font and method, and room for the data). False, with the atlas as it was, when the bytes are not an atlas
// of this font and method or do not fit.
AtlasRead :: proc(atlas: ^Atlas, data: []u8) -> bool {
    if len(data) < size_of(AtlasFileHeader) { return false }
    header: AtlasFileHeader
    mem.copy(&header, &data[0], size_of(header))
    if header.magic != ATLAS_FILE_MAGIC || header.version != ATLAS_FILE_VERSION { return false }
    if Method(header.method) != atlas.method || int(header.glyph_count) != atlas.font.glyph_count || abs(header.units_per_em - atlas.font.units_per_em) > 0.01 { return false }
    if int(header.used_slot_entries) != FontSlotCount(atlas.font) || header.palette_count > ATLAS_PALETTE || header.slots > ATLAS_TABLE_SLOTS { return false }
    table_bytes: int = 2 * int(header.slots) * 16
    data_bytes: int = int(header.data_texels) * 16
    needed: int = size_of(header) + FontSlotCount(atlas.font) * size_of(i32) + int(header.palette_count) * 4 + table_bytes + data_bytes
    if len(data) < needed || ATLAS_HEADER_TEXELS + int(header.data_texels) > len(atlas.texels) / 4 { return false }
    at: int = size_of(header)
    mem.copy(raw_data(atlas.slot_of_glyph), &data[at], FontSlotCount(atlas.font) * size_of(i32))
    at += FontSlotCount(atlas.font) * size_of(i32)
    atlas.palette_count = int(header.palette_count)
    mem.copy(&atlas.palette[0], &data[at], atlas.palette_count * 4)
    at += atlas.palette_count * 4
    for i in 0 ..< atlas.palette_count {
        color: [4]u8 = atlas.palette[i]
        texel: []f32 = atlasTexel(atlas, ATLAS_PALETTE_START + i)
        texel[0], texel[1], texel[2], texel[3] = f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255
    }
    mem.copy(raw_data(atlas.texels), &data[at], table_bytes)
    at += table_bytes
    mem.copy(&atlas.texels[ATLAS_HEADER_TEXELS * 4], &data[at], data_bytes)
    atlas.slots = int(header.slots)
    atlas.used = ATLAS_HEADER_TEXELS + int(header.data_texels)
    atlas.dirty_from = ATLAS_HEADER_TEXELS
    atlas.table_dirty = true
    atlas.palette_dirty = true
    atlas.version += 1
    return true
}
