#+build !js
#+build !arm64
package font

import "core:testing"

@(private = "file")
loadFont :: proc() -> ^Font {
    font: ^Font = new(Font)
    assert(FontInit(font, FIRA))
    return font
}

@(test)
test_a_range_is_baked_ahead_and_the_atlas_is_saved_and_read_back_with_no_baking :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    texels: []f32 = make([]f32, 4 * ATLAS_WIDTH * 8)
    slots: []i32 = make([]i32, FontSlotCount(font))
    texels_again: []f32 = make([]f32, 4 * ATLAS_WIDTH * 8)
    slots_again: []i32 = make([]i32, FontSlotCount(font))
    defer { delete(texels); delete(slots); delete(texels_again); delete(slots_again) }
    for method in Method {
        atlas: Atlas
        AtlasInit(&atlas, font, method, texels, slots)
        baked, ok := AtlasBakeRange(&atlas, 32, 126)
        testing.expect(t, ok && baked == 95, "every printable ASCII character that the font has")
        again, _ := AtlasBakeRange(&atlas, 32, 126)
        testing.expect_value(t, again, 0)                                      // baked once
        AtlasColor(&atlas, {10, 20, 30, 40})
        AtlasGlyph(&atlas, GlyphMissing(font))
        bytes: []u8 = make([]u8, AtlasWriteSize(&atlas))
        defer delete(bytes)
        written, write_ok := AtlasWrite(&atlas, bytes)
        testing.expect(t, write_ok && written == len(bytes))
        small: [10]u8
        _, small_ok := AtlasWrite(&atlas, small[:])
        testing.expect(t, !small_ok)

        loaded: Atlas
        AtlasInit(&loaded, font, method, texels_again, slots_again)
        testing.expect(t, AtlasRead(&loaded, bytes))
        testing.expect_value(t, loaded.slots, atlas.slots)
        testing.expect_value(t, loaded.used, atlas.used)
        testing.expect_value(t, loaded.palette[0], [4]u8{10, 20, 30, 40})
        // the same glyphs, with no baking: asking again changes nothing, and the pixels are the same
        used: int = loaded.used
        slot_a, _ := AtlasGlyph(&atlas, FontGlyph(font, 'g'))
        slot_b, _ := AtlasGlyph(&loaded, FontGlyph(font, 'g'))
        testing.expect_value(t, slot_b, slot_a)
        testing.expect_value(t, loaded.used, used)
        for point in ([?]Vec2{{0.3, 0.3}, {0.2, 0.05}, {0.45, -0.1}}) {
            first: f32
            second: f32
            if method == .SLUG {
                first = SlugCoverage(&atlas, slot_a, point, {30, 30})
                second = SlugCoverage(&loaded, slot_b, point, {30, 30})
            } else {
                first = ScanlineCoverage(&atlas, slot_a, point, {0.016, 0.016})
                second = ScanlineCoverage(&loaded, slot_b, point, {0.016, 0.016})
            }
            testing.expect_value(t, second, first)
        }
        // it is not the file of another method or of an atlas that is too small
        other: Atlas
        AtlasInit(&other, font, Method(1 - int(method)), texels_again, slots_again)
        testing.expect(t, !AtlasRead(&other, bytes), "a file of the other method")
        broken: []u8 = make([]u8, len(bytes))
        defer delete(broken)
        copy(broken, bytes)
        broken[0] = 0
        AtlasInit(&other, font, method, texels_again, slots_again)
        testing.expect(t, !AtlasRead(&other, broken), "not a file of an atlas")
        testing.expect(t, !AtlasRead(&other, bytes[:len(bytes) - 100]), "cut short")
    }
}

@(test)
test_every_glyph_of_the_font_can_be_baked_when_there_is_room_and_the_rest_is_told :: proc(t: ^testing.T) {
    font: ^Font = loadFont()
    defer free(font)
    texels: []f32 = make([]f32, 4 * ATLAS_WIDTH * 4)
    slots: []i32 = make([]i32, FontSlotCount(font))
    defer { delete(texels); delete(slots) }
    atlas: Atlas
    AtlasInit(&atlas, font, .SCANLINE, texels, slots)
    baked, ok := AtlasBakeAll(&atlas)
    testing.expect(t, !ok && baked > 50 && baked < FontSlotCount(font), "two rows of data hold some of the glyphs of a big font, not all")
}
