#+private file
package game

import "core:fmt"
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

// The letters to extract from the font
LETTERS_IN_FONT :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890?!&.,_:[]-+"
LETTER_COUNT :: len(LETTERS_IN_FONT)
// FONT_HEIGHT :: 16

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
atlas_buffer: glue.AtlasBuffer(512)
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
font_packed: karl2d.Font
font_rect_packed: []rectf
font_glyph_buffer: [LETTER_COUNT]karl2d.Font_Data
// Font draws outside Glyphs rectangle, so need to pack inside a bigger rectangle
FONT_PADDING :: 4

init :: proc() {
    background_color = karl2d.LIGHT_BLUE

    // 0. Init packer
    packer.Init(&atlas_packer)

    // 1. Load assets
    player_image, _: = glue.load_image_from_bytes(#load("../../../assets/textures/player_sheet.png"), {.alpha_premultiply}, context.allocator)
    // defer karl2d.destroy_texture(player_texture)

    tileset_image, _: = glue.load_image_from_bytes(#load("../../../assets/textures/tileset_template.png"), {.alpha_premultiply}, context.allocator)
    // defer karl2d.destroy_texture(tileset_texture)
    tileset_rects: [TILESET_SIZE]rectf
    for y:int = 0; y < TILE_ROWS; y += 1 {
        for x:int = 0; x < TILE_COLUMNS; x += 1 {
            i:int = TILE_COLUMNS * y + x
            tileset_rects[i] = {cast(f32)x * TILE_SIZE, cast(f32)y * TILE_SIZE, TILE_SIZE, TILE_SIZE}
        }
    }

    // TODO: load font

    // 2. Prepare target atlas
    atlas_ok:bool
    atlas_image, atlas_ok = glue.generate_image_from_bytes(atlas_buffer)
    
    
}

finit :: proc() {}

process :: proc() {}

draw :: proc() {
	karl2d.draw_text("Hellope!", {50, 50}, 100, karl2d.DARK_BLUE)
    
    stats_text:string = fmt.tprintf("window = (%v, %v), scale = %v, %v", window_width, window_height, window_scale, get_window_size())
	karl2d.draw_text(
        stats_text, 
        {50, 150}, 
        30, 
        karl2d.DARK_GRAY,
    )
    karl2d.draw_text( fmt.tprintf("mouse %v", get_local_mouse_position()), {50, 190},30, karl2d.DARK_GRAY)
}