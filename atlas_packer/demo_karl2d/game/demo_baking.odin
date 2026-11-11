#+private file
package game

// import "core:fmt"
import "core:mem"
import "../../../karl2d"
Vec2 :: karl2d.Vec2
Rect :: karl2d.Rect
Texture :: karl2d.Texture

import packer "../.."
vec2i:: packer.vec2i
rectf:: packer.rectf

import glue "../../karl2d"
Image :: glue.Image

@(private="package")
baking_state: GameState = {
    init,
    finit,
    process,
    draw,
}

ATLAS_SIZE :: 512
RECTF_BUFFER_SIZE :: 256

// Pre-allocated memory of the state. Packer, atlas pixels and rectangle slices are taken from the arena and live until finit.
// Source images are decoded into the same arena inside of a temporary section that is rolled back after baking.
ARENA_SIZE :: 4 * mem.Megabyte
arena_buffer: [ARENA_SIZE]byte
arena: mem.Arena

// Holds data about source/original sprite frames
player_sprite_source: []rectf = {
    {0,   0, 16, 16},
    {16,  0, 16, 16},
    {32,  0, 16, 16},
    {48,  0, 16, 16},
    {64,  0, 16, 16},
    {80,  0, 16, 16},
    {96,  0, 16, 16},
    {112, 0, 16, 16},
}

atlas_packer: packer.AtlasPacker

// Target atlas, pixels live in the arena
atlas_image: Image
atlas_texture: Texture

player_sprite_packed: []rectf
player_timer: f32 // for animation

tileset_packed: []rectf
TILESET_SIZE :: 5 * 10
TILE_SIZE :: 16
TILE_COLUMNS :: 10
TILE_ROWS :: 5

// The letters to extract from the font
LETTERS_IN_FONT :: " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890?!&.,_:[]-+"
LETTER_COUNT :: len(LETTERS_IN_FONT)
FONT_HEIGHT :: 32
// Extra pixels around each glyph, so scaled/filtered text doesn't pick neighbour glyphs
FONT_PADDING :: 2

font: packer.Font
font_glyphs: []packer.Glyph
font_rect_packed: []rectf
packed_font: karl2d.Font
is_font_registered: bool

init :: proc() {
    background_color = karl2d.LIGHT_BLUE

    mem.arena_init(&arena, arena_buffer[:])
    scene: mem.Allocator = mem.arena_allocator(&arena)

    // 0. Persistent memory: packer buffers, target atlas, glyph list
    packer.Init(&atlas_packer, ATLAS_SIZE, RECTF_BUFFER_SIZE, scene)
    atlas_image, _ = glue.CreateImage(ATLAS_SIZE, scene)
    font_glyphs = make([]packer.Glyph, LETTER_COUNT, scene)

    // Everything allocated until end_arena_temp_memory is released
    temp: mem.Arena_Temp_Memory = mem.begin_arena_temp_memory(&arena)

    // 1. Load assets
    player_image, _: = glue.LoadImageFromBytes(#load("../../../assets/textures/player_sheet.png"), {.alpha_premultiply}, scene)
    tileset_image, _: = glue.LoadImageFromBytes(#load("../../../assets/textures/tileset_template.png"), {.alpha_premultiply}, scene)

    tileset_rects: [TILESET_SIZE]rectf
    for y:int = 0; y < TILE_ROWS; y += 1 {
        for x:int = 0; x < TILE_COLUMNS; x += 1 {
            i:int = TILE_COLUMNS * y + x
            tileset_rects[i] = {cast(f32)x * TILE_SIZE, cast(f32)y * TILE_SIZE, TILE_SIZE, TILE_SIZE}
        }
    }

    // Measure letters, characters missing in the font are skipped
    font_ok: bool = packer.FontInit(&font, #load("../../../assets/fonts/font.ttf"), FONT_HEIGHT)
    assert(font_ok)
    codepoints: [LETTER_COUNT]rune = LETTERS_IN_FONT
    letter_rects: []rectf = make([]rectf, LETTER_COUNT, scene)
    letter_count: int
    letter_count, _ = packer.GetFontRects(&font, codepoints[:], letter_rects, font_glyphs, FONT_PADDING)

    // 2. Fetch target rectf slices
    player_sprite_ok:bool
    player_sprite_packed, player_sprite_ok = packer.GetRects(&atlas_packer, len(player_sprite_source))

    tileset_ok:bool
    tileset_packed, tileset_ok = packer.GetRects(&atlas_packer, TILESET_SIZE)

    font_rects_ok:bool
    font_rect_packed, font_rects_ok = packer.GetRects(&atlas_packer, letter_count)
    font_glyphs = font_glyphs[:letter_count]

    // 3. Init sizes & stuff
    packer.CopySizes(player_sprite_source[:], player_sprite_packed[:])
    packer.CopySizes(tileset_rects[:], tileset_packed[:])
    packer.CopySizes(letter_rects[:letter_count], font_rect_packed)

    // 4. Pack
    packer.Pack(&atlas_packer)

    // 5. Transfer to atlas image
    glue.BakeImageRects(player_image, &atlas_image, player_sprite_source, player_sprite_packed)
    glue.BakeImageRects(tileset_image, &atlas_image, tileset_rects[:], tileset_packed[:])

    alpha_buffer: []u8 = make([]u8, packer.GlyphsMaxBytes(font_glyphs), scene)
    glue.BakeFontGlyphs(&font, font_glyphs, font_rect_packed, &atlas_image, alpha_buffer, FONT_PADDING)

    // Source images, TTF measurements and glyph bitmaps are not needed anymore
    mem.end_arena_temp_memory(temp)

    // 6. Make Texture from Image and a Font that uses it
    atlas_texture = glue.LoadTextureFromImage(&atlas_image)
    packed_font, is_font_registered = glue.RegisterFont(karl_state, atlas_texture, &font, font_glyphs, font_rect_packed, FONT_PADDING)
}

finit :: proc() {
    if is_font_registered {
        // Destroys atlas texture and glyph data owned by Karl2D
        karl2d.destroy_font(packed_font)
        is_font_registered = false
    } else {
        karl2d.destroy_texture(atlas_texture)
    }
    mem.arena_free_all(&arena)
}

process :: proc() {
    // animate using packed rectangles
    delta_time: f32 = karl2d.get_frame_time()
    player_timer += delta_time * 12
    if int(player_timer) > len(player_sprite_packed)-1 {
        player_timer -= f32(int(player_timer))
    }
}

draw :: proc() {
    rect:Rect = {10, 10, cast(f32)ATLAS_SIZE, cast(f32)ATLAS_SIZE}
    karl2d.draw_rect(rect, karl2d.LIGHT_GRAY)

	karl2d.draw_texture(atlas_texture, {10,10})

    // Player sprite
    player_frame:int = int(player_timer)
    rect_player:Rect = transmute(Rect)player_sprite_packed[player_frame]
    karl2d.draw_texture_rect(atlas_texture, rect_player, {530, 10})

    // Tileset
    TILESET_POS :Vec2: {530, 40}
    for y:int = 0; y < TILE_ROWS; y += 1 {
        for x:int = 0; x < TILE_COLUMNS; x += 1 {
            i:int = TILE_COLUMNS * y + x
            tile_pos:Vec2 = {TILESET_POS.x + TILE_SIZE * cast(f32)x, TILESET_POS.y + TILE_SIZE * cast(f32)y}
            karl2d.draw_texture_rect(atlas_texture, transmute(Rect)tileset_packed[i], tile_pos)
        }
    }

    // Font that was baked into the same atlas texture
    if is_font_registered {
        karl2d.draw_text("Hello, baked font!", {530, 140}, FONT_HEIGHT, karl2d.BLACK, packed_font)
        karl2d.draw_text("Draw calls: 1 texture", {530, 180}, FONT_HEIGHT * 0.5, karl2d.DARK_BLUE, packed_font)
    }
}
