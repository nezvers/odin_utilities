#+private file
package demo_common

// Pack the frames of a sprite sheet, the tiles of a tileset and the glyphs of a font into ONE texture at run time. All of it on the CPU
// and without a framework: the images are decoded with core:image, the glyphs are rendered by stb_truetype (atlas_packer/font.odin), the
// result is a block of RGBA bytes that the kit turns into a texture. Packer buffers, pixels and glyph data come from one arena over a
// static buffer, finit frees everything with one call.

import "core:image"
import "core:image/png"
import "core:mem"
import packer ".."
import kit "../../demo_kit"

@(private="package")
demo_baking: kit.Demo = {
    name = "baking",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

ATLAS_SIZE :: 512
RECT_CAPACITY :: 256
ARENA_SIZE :: 4 * mem.Megabyte
arena_buffer: [ARENA_SIZE]byte
arena: mem.Arena

rectf :: packer.rectf

// Frames of the sprite sheet, where they are in the source
player_sprite_source: [8]rectf = {
    {0, 0, 16, 16}, {16, 0, 16, 16}, {32, 0, 16, 16}, {48, 0, 16, 16},
    {64, 0, 16, 16}, {80, 0, 16, 16}, {96, 0, 16, 16}, {112, 0, 16, 16},
}

TILESET_SIZE :: 5 * 10
TILE_SIZE :: 16
TILE_COLUMNS :: 10
TILE_ROWS :: 5

LETTERS_IN_FONT :: " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890?!&.,_:[]-+"
LETTER_COUNT :: len(LETTERS_IN_FONT)
FONT_HEIGHT :: 24
FONT_PADDING :: 2           // empty pixels around each glyph, so scaling does not pick up the neighbour

atlas_packer: packer.AtlasPacker
atlas_pixels: []u8          // the baked atlas: RGBA, ATLAS_SIZE x ATLAS_SIZE
atlas_texture: kit.Texture
player_packed: []rectf
tileset_packed: []rectf
glyph_rects: []rectf
glyphs: [LETTER_COUNT]packer.Glyph
glyph_count: int
font: packer.Font
pack_ok: bool
player_timer: f32

font_bytes: []byte = #load("../../assets/fonts/font.ttf")
player_png: []byte = #load("../../assets/textures/player_sheet.png")
tileset_png: []byte = #load("../../assets/textures/tileset_template.png")

init :: proc(ctx: ^kit.Context) {
    mem.arena_init(&arena, arena_buffer[:])
    scene: mem.Allocator = mem.arena_allocator(&arena)

    // 0. Init the packer
    ok: bool = packer.Init(&atlas_packer, ATLAS_SIZE, RECT_CAPACITY, scene)
    assert(ok)

    // 1. Load the sources
    player_image, player_error := png.load_from_bytes(player_png, {.alpha_add_if_missing}, scene)
    tileset_image, tileset_error := png.load_from_bytes(tileset_png, {.alpha_add_if_missing}, scene)
    assert(player_error == nil && tileset_error == nil)
    tileset_rects: [TILESET_SIZE]rectf
    for y in 0 ..< TILE_ROWS {
        for x in 0 ..< TILE_COLUMNS {
            tileset_rects[TILE_COLUMNS * y + x] = {f32(x * TILE_SIZE), f32(y * TILE_SIZE), TILE_SIZE, TILE_SIZE}
        }
    }
    font_ok: bool = packer.FontInit(&font, font_bytes, FONT_HEIGHT)
    assert(font_ok)
    letters: [LETTER_COUNT]rune
    for letter, i in LETTERS_IN_FONT { letters[i] = letter }

    // 2. Ask the packer for the rectangles, the sizes are known now
    player_packed, ok = packer.GetRects(&atlas_packer, len(player_sprite_source))
    tileset_packed, ok = packer.GetRects(&atlas_packer, TILESET_SIZE)
    glyph_rects, ok = packer.GetRects(&atlas_packer, LETTER_COUNT)
    packer.CopySizes(player_sprite_source[:], player_packed)
    packer.CopySizes(tileset_rects[:], tileset_packed)
    glyph_count, _ = packer.GetFontRects(&font, letters[:], glyph_rects, glyphs[:], FONT_PADDING)

    // 3. Pack: the rectangles get their positions
    pack_ok = packer.Pack(&atlas_packer)

    // 4. Bake into the pixels of the atlas
    atlas_pixels = make([]u8, ATLAS_SIZE * ATLAS_SIZE * 4, scene)
    bake_image(player_image, player_sprite_source[:], player_packed)
    bake_image(tileset_image, tileset_rects[:], tileset_packed)
    alpha: []u8 = make([]u8, packer.GlyphsMaxBytes(glyphs[:glyph_count]), scene)
    for i in 0 ..< glyph_count {
        packer.RenderGlyph(&font, &glyphs[i], alpha)
        bake_glyph(&glyphs[i], alpha, glyph_rects[i])
        // from now on the rectangle is the glyph without its padding
        glyph_rects[i].xy += FONT_PADDING
        glyph_rects[i].zw -= FONT_PADDING * 2
    }

    // 5. The kit makes a texture of the bytes
    atlas_texture = kit.TextureFromPixels(ctx, ATLAS_SIZE, ATLAS_SIZE, atlas_pixels)
    player_timer = 0
}

finit :: proc(ctx: ^kit.Context) {
    kit.TextureUnload(ctx, atlas_texture)
    mem.arena_free_all(&arena)
    atlas_pixels = nil
}

// Copy the rectangles of a decoded image into the atlas, row by row
bake_image :: proc(source: ^image.Image, source_rects: []rectf, target_rects: []rectf) {
    pixels: []u8 = source.pixels[:]
    for i in 0 ..< len(source_rects) {
        from: rectf = source_rects[i]
        to: rectf = target_rects[i]
        for y in 0 ..< int(from.w) {
            source_row: int = ((int(from.y) + y) * source.width + int(from.x)) * 4
            target_row: int = ((int(to.y) + y) * ATLAS_SIZE + int(to.x)) * 4
            copy(atlas_pixels[target_row:target_row + int(from.z) * 4], pixels[source_row:source_row + int(from.z) * 4])
        }
    }
}

// A glyph is an alpha mask: white with that alpha, inside of its rectangle (the padding stays empty)
bake_glyph :: proc(glyph: ^packer.Glyph, alpha: []u8, rect: rectf) {
    for y in 0 ..< int(glyph.size.y) {
        for x in 0 ..< int(glyph.size.x) {
            target: int = ((int(rect.y) + FONT_PADDING + y) * ATLAS_SIZE + int(rect.x) + FONT_PADDING + x) * 4
            value: u8 = alpha[y * int(glyph.size.x) + x]
            atlas_pixels[target + 0] = 255
            atlas_pixels[target + 1] = 255
            atlas_pixels[target + 2] = 255
            atlas_pixels[target + 3] = value
        }
    }
}

update :: proc(ctx: ^kit.Context) {
    player_timer += ctx.delta_time * 12
    if int(player_timer) > len(player_packed) - 1 {
        player_timer -= f32(int(player_timer))
    }
}

draw :: proc(ctx: ^kit.Context) {
    // The atlas
    atlas: kit.Rect = {10, 10, ATLAS_SIZE, ATLAS_SIZE}
    kit.DrawRect(ctx, atlas, kit.LIGHT_GRAY)
    kit.DrawTextureRect(ctx, atlas_texture, {0, 0, ATLAS_SIZE, ATLAS_SIZE}, atlas)
    kit.DrawRectOutline(ctx, atlas, 1, kit.BLACK)

    // Player sprite
    frame: rectf = player_packed[int(player_timer)]
    kit.DrawTextureRect(ctx, atlas_texture, frame, {530, 10, frame.z, frame.w})

    // Tileset
    for y in 0 ..< TILE_ROWS {
        for x in 0 ..< TILE_COLUMNS {
            tile: rectf = tileset_packed[TILE_COLUMNS * y + x]
            kit.DrawTextureRect(ctx, atlas_texture, tile, {530 + f32(TILE_SIZE * x), 40 + f32(TILE_SIZE * y), TILE_SIZE, TILE_SIZE})
        }
    }

    // The baked font: every letter is a rectangle of the atlas, placed by the advance of the glyphs
    draw_baked_text(ctx, "Hello, baked font!", {530, 160}, kit.BLACK)
    kit.DrawText(ctx, "the atlas is made in memory: frames, tiles and glyphs packed by atlas_packer", {10, 540}, 18, kit.DARK_GRAY)
}

draw_baked_text :: proc(ctx: ^kit.Context, text: string, position: kit.Vec2, color: kit.Color) {
    cursor: kit.Vec2 = position
    for letter in text {
        index: int = glyph_index(letter)
        if index < 0 { continue }
        glyph: packer.Glyph = glyphs[index]
        rect: rectf = glyph_rects[index]
        kit.DrawTextureRect(ctx, atlas_texture, rect, {cursor.x + glyph.offset.x, cursor.y + glyph.offset.y, rect.z, rect.w}, {}, 0, color)
        cursor.x += glyph.advance_x
    }
}

glyph_index :: proc(letter: rune) -> int {
    for i in 0 ..< glyph_count {
        if glyphs[i].value == letter { return i }
    }
    return -1
}

// Every rectangle is inside of the atlas and none overlaps another
rects_are_valid :: proc() -> bool {
    all: []rectf = atlas_packer.buffer[:atlas_packer.length]
    for a, i in all {
        if a.x < 0 || a.y < 0 || a.x + a.z > ATLAS_SIZE || a.y + a.w > ATLAS_SIZE { return false }
        for b, j in all {
            if i == j { continue }
            if a.x < b.x + b.z && a.x + a.z > b.x && a.y < b.y + b.w && a.y + a.w > b.y { return false }
        }
    }
    return true
}

script: []kit.Step = {
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return pack_ok && atlas_texture != kit.TEXTURE_NONE }, "everything fits in the atlas and the texture was made"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return rects_are_valid() }, "the packed rectangles are inside of the atlas and never overlap"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return glyph_count == LETTER_COUNT }, "the font has every letter that was asked for"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        // the first frame of the player was copied: a pixel of the baked rectangle is not empty
        rect: rectf = player_packed[0]
        for y in 0 ..< 16 {
            for x in 0 ..< 16 {
                if atlas_pixels[((int(rect.y) + y) * ATLAS_SIZE + int(rect.x) + x) * 4 + 3] != 0 { return true }
            }
        }
        return false
    }, "the player frame was baked into the pixels"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        // a letter was rendered: its glyph rectangle has white pixels with some alpha
        index: int = glyph_index('H')
        rect: rectf = glyph_rects[index]
        total: int = 0
        for y in 0 ..< int(rect.w) {
            for x in 0 ..< int(rect.z) {
                total += int(atlas_pixels[((int(rect.y) + y) * ATLAS_SIZE + int(rect.x) + x) * 4 + 3])
            }
        }
        return total > 0 && glyphs[index].advance_x > 0
    }, "the letter H was rendered with an advance"),
    kit.Wait(60),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player_timer >= 0 && int(player_timer) < len(player_packed) }, "the baked frames animate"),
}
