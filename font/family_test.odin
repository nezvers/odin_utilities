#+build !js
package font

import "core:testing"

JB_REGULAR :: #load("../assets/fonts/jetbrains_mono/JetBrainsMono-Regular.ttf")
JB_BOLD :: #load("../assets/fonts/jetbrains_mono/JetBrainsMono-Bold.ttf")
JB_ITALIC :: #load("../assets/fonts/jetbrains_mono/JetBrainsMono-Italic.ttf")
JB_BOLD_ITALIC :: #load("../assets/fonts/jetbrains_mono/JetBrainsMono-BoldItalic.ttf")

@(private = "file")
Family :: struct {
    fonts: [4]Font,
    slots: [4][]i32,
    texels: []f32,
    atlas: Atlas,
    glyphs: [128]RichGlyph,
    styles: [32]RichStyle,
    lines: [8]RichLine,
    rich: RichText,
    vertices: [2048]TextVertex,
}

// `faces` says how many of the four faces are added
@(private = "file")
makeFamily :: proc(faces: int, method: Method = .SLUG) -> ^Family {
    family: ^Family = new(Family)
    sources: [4][]u8 = {JB_REGULAR, JB_BOLD, JB_ITALIC, JB_BOLD_ITALIC}
    for i in 0 ..< 4 { assert(FontInit(&family.fonts[i], sources[i])) }
    family.texels = make([]f32, 4 * ATLAS_WIDTH * 12)
    for i in 0 ..< 4 { family.slots[i] = make([]i32, FontSlotCount(&family.fonts[i])) }
    AtlasInit(&family.atlas, &family.fonts[0], method, family.texels, family.slots[0])
    for i in 1 ..< faces { assert(AtlasAddFace(&family.atlas, i, &family.fonts[i], family.slots[i])) }
    RichInit(&family.rich, family.glyphs[:], family.styles[:], family.lines[:])
    return family
}

@(private = "file")
freeFamily :: proc(family: ^Family) {
    delete(family.texels)
    for slots in family.slots { delete(slots) }
    free(family)
}

@(test)
test_the_faces_of_a_family_share_an_atlas_and_each_bakes_its_own_glyphs :: proc(t: ^testing.T) {
    family: ^Family = makeFamily(4)
    defer freeFamily(family)
    testing.expect(t, !AtlasAddFace(&family.atlas, 1, &family.fonts[1], family.slots[1]), "a face is added once")
    testing.expect(t, !AtlasAddFace(&family.atlas, 0, &family.fonts[1], family.slots[1]), "the regular face is the font of AtlasInit")
    regular, ok_regular := AtlasGlyph(&family.atlas, FontGlyph(&family.fonts[0], 'g'), 0)
    bold, ok_bold := AtlasGlyph(&family.atlas, FontGlyph(&family.fonts[1], 'g'), 1)
    testing.expect(t, ok_regular && ok_bold && regular != bold, "another glyph of the same letter has its own slot")
    // the strokes of the bold face are heavier: the middle of the stem of an l is covered in both, the edge only in the bold one
    l_regular, _ := AtlasGlyph(&family.atlas, FontGlyph(&family.fonts[0], 'l'), 0)
    l_bold, _ := AtlasGlyph(&family.atlas, FontGlyph(&family.fonts[1], 'l'), 1)
    low, high, _ := FontGlyphBox(&family.fonts[0], FontGlyph(&family.fonts[0], 'l'))
    probe: Vec2 = {(low.x + high.x) * 0.5, 0.3}
    testing.expect(t, SlugCoverage(&family.atlas, l_regular, probe, {50, 50}) > 0.99 && SlugCoverage(&family.atlas, l_bold, probe, {50, 50}) > 0.99)
    // measure the stem of the l along y = 0.3 in both faces: the bold one is wider
    stem :: proc(family: ^Family, slot: int, from: f32, to: f32) -> f32 {
        width: f32
        step: f32 = 0.002
        for x := from; x < to; x += step { width += step * SlugCoverage(&family.atlas, slot, {x, 0.3}, {200, 200}) }
        return width
    }
    testing.expect(t, stem(family, l_bold, 0.1, 0.5) > stem(family, l_regular, 0.1, 0.5) * 1.2, "the stem of the bold l is wider")
    // clearing forgets the glyphs of every face
    AtlasClear(&family.atlas)
    again, _ := AtlasGlyph(&family.atlas, FontGlyph(&family.fonts[1], 'g'), 1)
    testing.expect_value(t, again, 0)
    // plain text takes the face from its options; a face that is not there is the regular one
    testing.expect_value(t, AtlasFace(&family.atlas, 2), &family.fonts[2])
    family.atlas.faces[3] = nil
    testing.expect_value(t, AtlasFace(&family.atlas, 3), &family.fonts[0])
}

@(test)
test_plain_text_takes_a_face_with_its_options :: proc(t: ^testing.T) {
    family: ^Family = makeFamily(2)
    defer freeFamily(family)
    count_regular, _, _, _ := TextQuads(&family.atlas, "g", {}, 20, family.vertices[:], {})
    regular_slot: u32 = family.vertices[0].slot
    count_bold, _, _, _ := TextQuads(&family.atlas, "g", {}, 20, family.vertices[:], {face = 1})
    testing.expect_value(t, count_regular, 6)
    testing.expect_value(t, count_bold, 6)
    testing.expect(t, family.vertices[0].slot != regular_slot, "the bold face has its own slot")
    // a face that is not in the atlas is the regular one
    TextQuads(&family.atlas, "g", {}, 20, family.vertices[:], {face = 3})
    testing.expect_value(t, family.vertices[0].slot, regular_slot)
}

@(test)
test_rich_text_uses_the_real_faces_and_makes_the_missing_ones_from_the_regular :: proc(t: ^testing.T) {
    draw :: proc(family: ^Family, markup: string) -> RichDrawResult {
        RichParse(&family.rich, markup)
        RichLayout(&family.rich, &family.atlas.faces, 20)
        return RichDraw(&family.atlas, &family.rich, {}, 0, family.vertices[:])
    }
    // all four faces: a bold glyph is one quad, an italic one too, with no slant, and the faces are the ones of the glyphs
    full: ^Family = makeFamily(4)
    defer freeFamily(full)
    result := draw(full, "[b]a[/b][i]a[/i][b][i]a[/i][/b]a")
    testing.expect_value(t, result.count, 4 * TEXT_VERTICES_PER_GLYPH)
    faces: [4]u8
    for i in 0 ..< 4 { faces[i] = full.rich.glyphs[i].face }
    testing.expect_value(t, faces, [4]u8{1, 2, 3, 0})
    for i in 0 ..< 4 { testing.expect(t, !full.rich.glyphs[i].synth_bold && !full.rich.glyphs[i].synth_italic) }
    testing.expect(t, abs(full.vertices[TEXT_VERTICES_PER_GLYPH + 2].position.x - full.vertices[TEXT_VERTICES_PER_GLYPH + 1].position.x) < 0.01, "the italic face is not slanted by the library")
    // only the regular face: bold is struck twice, italic is slanted, bold italic is both
    regular_only: ^Family = makeFamily(1)
    defer freeFamily(regular_only)
    plain := draw(regular_only, "[b]a[/b]")
    testing.expect_value(t, plain.count, 2 * TEXT_VERTICES_PER_GLYPH)
    testing.expect(t, regular_only.rich.glyphs[0].synth_bold && !regular_only.rich.glyphs[0].synth_italic)
    draw(regular_only, "[i]a[/i]")
    testing.expect(t, regular_only.rich.glyphs[0].synth_italic && regular_only.vertices[2].position.x - regular_only.vertices[1].position.x > 2)
    // bold and italic faces without a bold italic one: the bold face is slanted, or the italic one struck twice
    partial: ^Family = makeFamily(2)
    defer freeFamily(partial)
    draw(partial, "[b][i]a[/i][/b]")
    testing.expect(t, partial.rich.glyphs[0].face == 1 && !partial.rich.glyphs[0].synth_bold && partial.rich.glyphs[0].synth_italic)
    // a character that the bold face lacks (and the regular one has) is drawn with the regular face
    draw(full, "[b]§[/b]")
    testing.expect(t, full.rich.glyphs[0].face == 1 || full.rich.glyphs[0].face == 0)
}

@(test)
test_the_atlas_file_keeps_every_face :: proc(t: ^testing.T) {
    family: ^Family = makeFamily(4)
    defer freeFamily(family)
    for face in 0 ..< 4 {
        baked, ok := AtlasBakeRange(&family.atlas, 'a', 'f', face)
        testing.expect(t, ok && baked == 6)
    }
    bytes: []u8 = make([]u8, AtlasWriteSize(&family.atlas))
    defer delete(bytes)
    _, wrote := AtlasWrite(&family.atlas, bytes)
    testing.expect(t, wrote)

    again: ^Family = makeFamily(4)
    defer freeFamily(again)
    testing.expect(t, AtlasRead(&again.atlas, bytes))
    used: int = again.atlas.used
    for face in 0 ..< 4 {
        slot_a, _ := AtlasGlyph(&family.atlas, FontGlyph(&family.fonts[face], 'c'), face)
        slot_b, _ := AtlasGlyph(&again.atlas, FontGlyph(&again.fonts[face], 'c'), face)
        testing.expect_value(t, slot_b, slot_a)
    }
    testing.expect_value(t, again.atlas.used, used)                                  // nothing was baked again
    // a file of an atlas with other faces is not accepted
    fewer: ^Family = makeFamily(2)
    defer freeFamily(fewer)
    testing.expect(t, !AtlasRead(&fewer.atlas, bytes))
}
