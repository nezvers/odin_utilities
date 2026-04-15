#+private file
package demo

import "core:slice"

import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle

import packer ".."
import packer_rl "../raylib"
vec2i:: packer.vec2i
rectf:: packer.rectf

import stbrp "vendor:stb/rect_pack"
stb_Rect:: stbrp.Rect

@(private="package")
baking_state :State = {
    init,
    finit,
    update,
    draw,
}

// Vector2{ATLAS_SIZE, ATLAS_SIZE}
ATLAS_SIZE :: 512
BUFFER_SIZE :: 256
AtlasPacker :: packer.AtlasPacker(BUFFER_SIZE, ATLAS_SIZE)

// The letters to extract from the font
LETTERS_IN_FONT :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890?!&.,_:[]-+"
LETTER_COUNT :: len(LETTERS_IN_FONT)
// FONT_HEIGHT :: 16

Sprite :: struct {
    size: Vector2,
    tex_pos:[]Vector2,
}

// Holds data about source/original sprite frames
player_sprite_source: []rectf = {
    {0, 0,16,16},
    {16,0,16,16},
    {32,0,16,16},
    {48,0,16,16},
    {64,0,16,16},
    {80,0,16,16},
    {96,0,16,16},
}

atlas_packer: AtlasPacker

// Used as target atlas
atlas_image:rl.Image
atlas_texture:rl.Texture

player_sprite_packed: []rectf
player_timer: f32 // for animation

tileset_packed: []rectf
TILESET_SIZE :: 5 * 10
TILE_SIZE :: 16
TILE_COLUMNS :: 10
TILE_ROWS :: 5

font_packed: rl.Font
font_rect_packed: []rectf
font_glyph_buffer: [LETTER_COUNT]rl.GlyphInfo
// Maybe Raylib specific, font draws outside Glyphs rectangle, so need to pack inside bigger rectangle
FONT_PADDING :: 4


init :: proc() {
    // 0. Init packer
    packer.Init(&atlas_packer)

    // 1. Load assets
    player_texture: rl.Texture2D = rl.LoadTexture("../assets/textures/player_sheet.png")
    defer rl.UnloadTexture(player_texture)

    tileset_texture: rl.Texture2D = rl.LoadTexture("../assets/textures/tileset_template.png")
    defer rl.UnloadTexture(tileset_texture)
    tileset_rects: [TILESET_SIZE]rectf
    for y:int = 0; y < TILE_ROWS; y += 1 {
        for x:int = 0; x < TILE_COLUMNS; x += 1 {
            i:int = TILE_COLUMNS * y + x
            tileset_rects[i] = {cast(f32)x * TILE_SIZE, cast(f32)y * TILE_SIZE, TILE_SIZE, TILE_SIZE}
        }
    }

    codepoints: [LETTER_COUNT]rune = LETTERS_IN_FONT
    font_source:rl.Font = rl.LoadFontEx("../assets/fonts/font.ttf", 32, &codepoints[0], cast(i32)LETTER_COUNT)
    defer rl.UnloadFont(font_source)

    // 2. Prepare target atlas
    atlas_image = rl.GenImageColor(ATLAS_SIZE, ATLAS_SIZE, {})

    // 3. Fetch target rectf slices
    player_sprite_ok:bool
    player_sprite_packed, player_sprite_ok = packer.GetRects(&atlas_packer, len(player_sprite_source))

    tileset_ok:bool
    tileset_packed, tileset_ok = packer.GetRects(&atlas_packer, TILESET_SIZE)

    font_ok:bool
    font_rect_packed, font_ok = packer.GetRects(&atlas_packer, LETTER_COUNT)
    
    // 4. Init sizes & stuff
    packer.CopySizes(player_sprite_source[:], player_sprite_packed[:])
    packer.CopySizes(tileset_rects[:], tileset_packed[:])
    packer_rl.init_packed_font(&font_source, &font_packed, font_glyph_buffer[:], font_rect_packed, FONT_PADDING)
    
    // 5. Pack
    packer.Pack(&atlas_packer)

    // 6. Transfer to atlas image
    player_image: rl.Image = rl.LoadImageFromTexture(player_texture)
    defer rl.UnloadImage(player_image)
    packer_rl.BakeImageRects(&player_image, &atlas_image, player_sprite_source, player_sprite_packed)

    tileset_image: rl.Image = rl.LoadImageFromTexture(tileset_texture)
    defer rl.UnloadImage(tileset_image)
    packer_rl.BakeImageRects(&tileset_image, &atlas_image, tileset_rects[:], tileset_packed[:])

    font_image: rl.Image = rl.LoadImageFromTexture(font_source.texture)
    defer rl.UnloadImage(font_image)
    font_source_rects: []rectf = slice.from_ptr(cast([^]rectf)font_source.recs, cast(int)font_source.glyphCount)
    packer_rl.BakeImageRects(&font_image, &atlas_image, font_source_rects, font_rect_packed, FONT_PADDING)

    // Shrink rects to original size in center of baked rectangle
    for i:int = 0; i < len(font_rect_packed); i += 1 {
        font_rect_packed[i].xy += {FONT_PADDING, FONT_PADDING}
        font_rect_packed[i].zw -= {FONT_PADDING, FONT_PADDING} * 2
    }

    // Make Texture from Image
    atlas_texture = rl.LoadTextureFromImage(atlas_image)

    // Assign texture to font
    font_packed.texture = atlas_texture
}

finit :: proc() {
	rl.UnloadImage(atlas_image)
    rl.UnloadTexture(atlas_texture)
}

update :: proc() {
    delta_time: f32 = rl.GetFrameTime()
    player_timer += delta_time * 12
    if int(player_timer) > len(player_sprite_packed)-1 {
        player_timer -= f32(int(player_timer))
    }
}

draw :: proc(){
    rect:Rectangle = {10, 10, cast(f32)ATLAS_SIZE, cast(f32)ATLAS_SIZE}
    source_rect:Rectangle = {0, 0, rect.width, rect.height}
    dest_rect:Rectangle = {10, 10, rect.width, rect.height}

    rl.DrawRectangleLinesEx(rect, 1, rl.BLACK)
    rl.DrawRectangleRec(rect, rl.LIGHTGRAY)
    rl.DrawTexturePro(atlas_texture, source_rect, dest_rect, {0,0}, 0.0, rl.WHITE)

    // Player sprite
    player_frame:int = int(player_timer)
    rect_player:Rectangle = transmute(Rectangle)player_sprite_packed[player_frame]
    rl.DrawTextureRec(atlas_texture, rect_player, {530, 10}, rl.WHITE)

    // Tileset
    for y:int = 0; y < TILE_ROWS; y += 1 {
        for x:int = 0; x < TILE_COLUMNS; x += 1 {
            i:int = TILE_COLUMNS * y + x
            TILESET_POS :Vector2: {530, 40}
            tile_pos:Vector2 = {TILESET_POS.x + TILE_SIZE * cast(f32)x, TILESET_POS.y + TILE_SIZE * cast(f32)y}
            tile_rect:Rectangle = transmute(Rectangle)tileset_packed[i]
            rl.DrawTextureRec(atlas_texture, tile_rect, tile_pos, rl.WHITE)
        }
    }

    // Font
    rl.DrawTextEx(font_packed, "Hello, baked font!", {550, 10}, cast(f32)font_packed.baseSize, 0, rl.BLACK)
}