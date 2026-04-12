#+private file
package demo

import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle

import packer ".."
vec2i:: packer.vec2i
rectf:: packer.rectf

import stbrp "vendor:stb/rect_pack"
stb_Rect:: stbrp.Rect

@(private="package")
baking_state :State = {
    init,
    finit,
    nil,
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

// Used as dynamic atlas
render_texture:rl.RenderTexture

// Holds data about generated atlas texture, assigned to spawned instances
player_sprite_packed: []rectf


reset_atlas :: proc() {
	rl.UnloadRenderTexture(render_texture)
	render_texture = rl.LoadRenderTexture(ATLAS_SIZE, ATLAS_SIZE)
}

init :: proc() {
    // 0. Init packer
    atlas_packer = {}
    packer.Init(&atlas_packer)

    // 1. Load assets
    player_texture: rl.Texture2D = rl.LoadTexture("../assets/textures/player_sheet.png")
    defer rl.UnloadTexture(player_texture)

    font_source:rl.Font = rl.LoadFont("../assets/fonts/font.ttf")
    defer rl.UnloadFont(font_source)

    // 2. Prepare target texture / atlas
    reset_atlas()

    // 3. Fetch target rectf slices
    player_sprite_ok:bool
    player_sprite_packed, player_sprite_ok = packer.GetRects(&atlas_packer, len(player_sprite_source))

    // 4. Init sizes for target rectf
    packer.CopySizes(player_sprite_source[:], player_sprite_packed[:])

    packer.Pack(&atlas_packer)
}

finit :: proc() {
	rl.UnloadRenderTexture(render_texture)
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
    // rect_player:Rectangle = transmute(Rectangle)player_sprite_packed[0]
    // rl.DrawRectangleLinesEx({530, 10, rect_player.width, rect_player.height}, 1, rl.BLACK)
    // rl.DrawTextureRec(render_texture.texture, rect_player, {530, 10}, rl.WHITE)
}