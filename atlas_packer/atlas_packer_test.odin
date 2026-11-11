package atlas_packer

import "core:mem"
import "core:testing"

@(private="file")
overlaps :: proc(a: rectf, b: rectf) -> bool {
    return a.x < b.x + b.z && a.x + a.z > b.x && a.y < b.y + b.w && a.y + a.w > b.y
}

@(test)
test_pack_in_arena :: proc(t: ^testing.T) {
    buffer: [64 * mem.Kilobyte]byte
    arena: mem.Arena
    mem.arena_init(&arena, buffer[:])
    scene: mem.Allocator = mem.arena_allocator(&arena)

    packer: AtlasPacker
    testing.expect(t, Init(&packer, 128, 32, scene))
    testing.expect(t, arena.offset > 0)

    rects, ok: = GetRects(&packer, 20)
    testing.expect(t, ok)
    for i in 0..<len(rects) {
        rects[i].zw = {f32(8 + i % 3 * 8), f32(8 + i % 4 * 4)}
    }
    testing.expect(t, Pack(&packer))

    for i in 0..<len(rects) {
        testing.expect(t, rects[i].x >= 0 && rects[i].y >= 0)
        testing.expect(t, rects[i].x + rects[i].z <= 128 && rects[i].y + rects[i].w <= 128)
        for j in i+1..<len(rects) {
            testing.expect(t, !overlaps(rects[i], rects[j]))
        }
    }

    // Everything is released with the arena
    mem.arena_free_all(&arena)
    testing.expect(t, arena.offset == 0)
}

@(test)
test_rect_capacity_and_reset :: proc(t: ^testing.T) {
    buffer: [16 * mem.Kilobyte]byte
    arena: mem.Arena
    mem.arena_init(&arena, buffer[:])

    packer: AtlasPacker
    testing.expect(t, Init(&packer, 64, 4, mem.arena_allocator(&arena)))
    _, ok: = GetRects(&packer, 3)
    testing.expect(t, ok)
    _, ok = GetRects(&packer, 2)
    testing.expect(t, !ok)
    _, ok = GetRects(&packer, 1)
    testing.expect(t, ok)

    Reset(&packer)
    _, ok = GetRects(&packer, 4)
    testing.expect(t, ok)
}

@(test)
test_init_fails_when_arena_is_too_small :: proc(t: ^testing.T) {
    buffer: [256]byte
    arena: mem.Arena
    mem.arena_init(&arena, buffer[:])

    packer: AtlasPacker
    testing.expect(t, !Init(&packer, 512, 256, mem.arena_allocator(&arena)))
}

@(test)
test_pack_fails_when_atlas_is_full :: proc(t: ^testing.T) {
    buffer: [16 * mem.Kilobyte]byte
    arena: mem.Arena
    mem.arena_init(&arena, buffer[:])

    packer: AtlasPacker
    testing.expect(t, Init(&packer, 32, 8, mem.arena_allocator(&arena)))
    rects, _: = GetRects(&packer, 5)
    for i in 0..<len(rects) {
        rects[i].zw = {16, 16}
    }
    // 32x32 atlas fits 4 of 16x16
    testing.expect(t, !Pack(&packer))
}

@(test)
test_temp_memory_rollback :: proc(t: ^testing.T) {
    buffer: [16 * mem.Kilobyte]byte
    arena: mem.Arena
    mem.arena_init(&arena, buffer[:])
    scene: mem.Allocator = mem.arena_allocator(&arena)

    persistent, _: = make([]u8, 100, scene)
    used: int = arena.offset
    temp: mem.Arena_Temp_Memory = mem.begin_arena_temp_memory(&arena)
    scratch, _: = make([]u8, 1000, scene)
    testing.expect(t, arena.offset > used)
    mem.end_arena_temp_memory(temp)
    testing.expect(t, arena.offset == used)
    testing.expect(t, len(persistent) == 100 && len(scratch) == 1000)
}

@(test)
test_font_rects_and_render :: proc(t: ^testing.T) {
    @(static) font_data := #load("../assets/fonts/font.ttf")
    font: Font
    testing.expect(t, FontInit(&font, font_data, 32))
    testing.expect(t, font.line_spacing > 0)

    // Last one doesn't exist in the font
    letters: []rune = {'H', 'g', '.', 0x10FFFF}
    rects: [4]rectf
    glyphs: [4]Glyph
    count, ok: = GetFontRects(&font, letters, rects[:], glyphs[:], 2)
    testing.expect(t, ok)
    testing.expect(t, count == 3)
    testing.expect(t, glyphs[0].value == 'H' && glyphs[1].value == 'g' && glyphs[2].value == '.')
    for i in 0..<count {
        testing.expect(t, glyphs[i].size.x > 0 && glyphs[i].size.y > 0)
        // padding on both sides
        testing.expect(t, rects[i].z == f32(glyphs[i].size.x) + 4 && rects[i].w == f32(glyphs[i].size.y) + 4)
        testing.expect(t, glyphs[i].advance_x > 0)
    }

    alpha: [64 * 64]u8
    testing.expect(t, GlyphsMaxBytes(glyphs[:count]) <= len(alpha))
    testing.expect(t, RenderGlyph(&font, &glyphs[0], alpha[:]))
    drawn: int
    for i in 0..<int(glyphs[0].size.x * glyphs[0].size.y) {
        if alpha[i] > 0 { drawn += 1 }
    }
    testing.expect(t, drawn > 0)

    tiny: [1]u8
    testing.expect(t, !RenderGlyph(&font, &glyphs[0], tiny[:]))
}
