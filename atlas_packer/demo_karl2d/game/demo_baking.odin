#+private file
package game

// import "core:fmt"
import "../../../karl2d"
Vec2 :: karl2d.Vec2
Rect :: karl2d.Rect
Texture :: karl2d.Texture

import packer "../.."
vec2i:: packer.vec2i
rectf:: packer.rectf

import glue "../../karl2d"
Image :: glue.Image

import stbrp "vendor:stb/rect_pack"
stb_Rect:: stbrp.Rect


@(private="package")
baking_state: GameState = {
    init,
    finit,
    process,
    draw,
}


ATLAS_SIZE :: 512
RECTF_BUFFER_SIZE :: 256
AtlasPacker :: packer.AtlasPacker(RECTF_BUFFER_SIZE, ATLAS_SIZE)

Sprite :: struct {
    size: Vec2,
    tex_pos:[]Vec2,
}

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

atlas_packer: AtlasPacker

// Used as target atlas
// WIDTH * HEIGHT
atlas_buffer: [ATLAS_SIZE * ATLAS_SIZE]glue.Color
atlas_image: Image
atlas_texture: Texture

player_sprite_packed: []rectf
player_timer: f32 // for animation

tileset_packed: []rectf
TILESET_SIZE :: 5 * 10
TILE_SIZE :: 16
TILE_COLUMNS :: 10
TILE_ROWS :: 5

// TODO: font baking
// The letters to extract from the font
LETTERS_IN_FONT :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890?!&.,_:[]-+"
LETTER_COUNT :: len(LETTERS_IN_FONT)
// Font draws outside Glyphs rectangle, so need to pack inside a bigger rectangle
FONT_PADDING :: 4

font_packed: karl2d.Font
font_rect_packed: []rectf
font_glyph_buffer: [LETTER_COUNT]karl2d.Font_Data

init :: proc() {
    background_color = karl2d.LIGHT_BLUE

    // 0. Init packer
    packer.Init(&atlas_packer)

    // 1. Load assets
    player_image, _: = glue.LoadImageFromBytes(#load("../../../assets/textures/player_sheet.png"), {.alpha_premultiply}, karl_state.frame_allocator)
    // defer glue.DestroyImage(player_image)

    tileset_image, _: = glue.LoadImageFromBytes(#load("../../../assets/textures/tileset_template.png"), {.alpha_premultiply}, karl_state.frame_allocator)
    // defer glue.DestroyImage(tileset_image)
    
    tileset_rects: [TILESET_SIZE]rectf
    for y:int = 0; y < TILE_ROWS; y += 1 {
        for x:int = 0; x < TILE_COLUMNS; x += 1 {
            i:int = TILE_COLUMNS * y + x
            tileset_rects[i] = {cast(f32)x * TILE_SIZE, cast(f32)y * TILE_SIZE, TILE_SIZE, TILE_SIZE}
        }
    }

    // TODO: load font
    // codepoints: [LETTER_COUNT]rune = LETTERS_IN_FONT
    // karl2d.load_font_from_bytes(#load("../../../assets/fonts/font.ttf"), {.premultiply_alpha})

    // 2. Fetch target rectf slices
    player_sprite_ok:bool
    player_sprite_packed, player_sprite_ok = packer.GetRects(&atlas_packer, len(player_sprite_source))

    tileset_ok:bool
    tileset_packed, tileset_ok = packer.GetRects(&atlas_packer, TILESET_SIZE)

    // TODO: 
    /*
    font_ok:bool
    font_rect_packed, font_ok = packer.GetRects(&atlas_packer, LETTER_COUNT)
    */

    // 3. Init sizes & stuff
    packer.CopySizes(player_sprite_source[:], player_sprite_packed[:])
    packer.CopySizes(tileset_rects[:], tileset_packed[:])
    // packer_rl.init_packed_font(&font_source, &font_packed, font_glyph_buffer[:], font_rect_packed, FONT_PADDING)

    // 4. Pack
    packer.Pack(&atlas_packer)

    // 5. Prepare target atlas
    atlas_ok:bool
    atlas_image, atlas_ok = glue.GenerateImageFromBuffer(atlas_buffer[:], ATLAS_SIZE)

    // 6. Transfer to atlas image
    glue.BakeImageRects(player_image, &atlas_image, player_sprite_source, player_sprite_packed)
    glue.BakeImageRects(tileset_image, &atlas_image, tileset_rects[:], tileset_packed[:])

    // Make Texture from Image
    atlas_texture = glue.LoadTextureFromImage(&atlas_image)
}

finit :: proc() {}

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
}