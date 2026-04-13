#+private file
package demo

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
render_texture:rl.RenderTexture

player_sprite_packed: []rectf
player_timer: f32 // for animation

font_packed: rl.Font
font_rect_packed: []rectf
font_glyph_buffer: [LETTER_COUNT]rl.GlyphInfo

reset_atlas :: proc() {
	rl.UnloadRenderTexture(render_texture)
	render_texture = rl.LoadRenderTexture(ATLAS_SIZE, ATLAS_SIZE)
}

init :: proc() {
    // 0. Init packer
    packer.Init(&atlas_packer)

    // 1. Load assets
    player_texture: rl.Texture2D = rl.LoadTexture("../assets/textures/player_sheet.png")
    defer rl.UnloadTexture(player_texture)

    codepoints: [LETTER_COUNT]rune = LETTERS_IN_FONT
    font_source:rl.Font = rl.LoadFontEx("../assets/fonts/font.ttf", 32, &codepoints[0], cast(i32)LETTER_COUNT)
    defer rl.UnloadFont(font_source)

    // 2. Prepare target texture / atlas
    reset_atlas()

    // 3. Fetch target rectf slices
    player_sprite_ok:bool
    player_sprite_packed, player_sprite_ok = packer.GetRects(&atlas_packer, len(player_sprite_source))

    font_ok:bool
    font_rect_packed, font_ok = packer.GetRects(&atlas_packer, LETTER_COUNT)
    
    // 4. Init sizes & stuff
    packer.CopySizes(player_sprite_source[:], player_sprite_packed[:])
    packer_rl.init_packed_font(&font_source, &font_packed, render_texture.texture, font_glyph_buffer[:], font_rect_packed)
    
    // 5. Pack
    packer.Pack(&atlas_packer)

    // 6. Transfer to render texture
    // Raylib need temporary texture because, render textures are vertically flipped
    temp_render_texture: rl.RenderTexture2D = rl.LoadRenderTexture(ATLAS_SIZE, ATLAS_SIZE)
    defer rl.UnloadRenderTexture(temp_render_texture)

    // Recommended to do manualy in one draw call. Each call does separate draw call.
    packer_rl.BakeTextureRects(temp_render_texture, player_texture, player_sprite_source, player_sprite_packed)
    packer_rl.BakeFontRects(temp_render_texture, &font_source, &font_packed)

    // Transfer to target render_texture to flip it correclty
    rl.BeginTextureMode(render_texture)
    rl.DrawTexture(temp_render_texture.texture, 0, 0, rl.WHITE)
    rl.EndTextureMode()
}

finit :: proc() {
	rl.UnloadRenderTexture(render_texture)
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
    rl.DrawTexturePro(render_texture.texture, source_rect, dest_rect, {0,0}, 0.0, rl.WHITE)

    // Test player tex_pos
    // Spawned instance
    rect_player:Rectangle = transmute(Rectangle)player_sprite_packed[int(player_timer)]
    rl.DrawRectangleLinesEx({530, 10, rect_player.width, rect_player.height}, 1, rl.BLACK)
    rl.DrawTextureRec(render_texture.texture, rect_player, {530, 10}, rl.WHITE)

    rl.DrawTextEx(font_packed, "Hello, baked font!", {550, 10}, cast(f32)font_packed.baseSize, 0, rl.BLACK)
}