package demo

import rl "vendor:raylib"
import sp ".."
import sr "../raylib"


Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
Color :: rl.Color
Font :: rl.Font
Texture2D :: rl.Texture2D

screen_size:Vector2
player_texture: Texture2D

PlayerStates::enum {
    idle,
    walk,
    jump_up,
    jump_down,
}

SPRITE_SIZE :sp.vec2: {16, 16}
// All positions on texture
tex_pos:[]sp.vec2 = {{0,0}, {16,0}, {32,0}, {48,0}, {64,0}, {80,0}, {96,0}}
anim_idle:sp.Frames = {tex_pos[0:1], SPRITE_SIZE}
anim_walk:sp.Frames = {tex_pos[1:7], SPRITE_SIZE}
anim_up:sp.Frames = {tex_pos[5:6], SPRITE_SIZE}
anim_down:sp.Frames = {tex_pos[6:7], SPRITE_SIZE}

player_animations:sp.AnimationSet = { 
    {&anim_idle, &anim_walk, &anim_up, &anim_down}, 
    cast(u32)PlayerStates.idle, 0, 12, 0,
}

player_sprite:sp.Sprite = {
    player_animations,
    {18, 100},
    {-8, -16},
    {1, 1},
    0.0,
}

game_init :: proc() {
    player_texture = rl.LoadTexture("../assets/textures/player_sheet.png")
    sp.ChangeAnimation(&player_sprite.animation_set, cast(u32)PlayerStates.walk)
}

game_shutdown :: proc() {
	rl.UnloadTexture(player_texture)
}

update :: proc() {
    sp.UpdateSprite(&player_sprite, rl.GetFrameTime())
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.WHITE)
    screen_size = {cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}
    camera:rl.Camera2D = { {0, 0}, {0,0}, 0, 4,} // zoom in
    rl.BeginMode2D(camera)

    // Draw current frame as preview
    frame_rect:rl.Rectangle = transmute(rl.Rectangle)sp.GetAnimationFrame(&player_sprite.animation_set)
    rl.DrawTextureRec(player_texture, frame_rect, {10, 10}, rl.WHITE)

    // PLAYER SPRITE
    rl.DrawLine(
        cast(i32)player_sprite.position.x - 8,
        cast(i32)player_sprite.position.y,
        cast(i32)player_sprite.position.x + 8,
        cast(i32)player_sprite.position.y,
        rl.BLACK,
    )
    rl.DrawLine(
        cast(i32)player_sprite.position.x,
        cast(i32)player_sprite.position.y - 8,
        cast(i32)player_sprite.position.x,
        cast(i32)player_sprite.position.y + 8,
        rl.BLACK,
    )
    rl.DrawRectangleLines(
        cast(i32)(player_sprite.position.x + player_sprite.offset.x),
        cast(i32)(player_sprite.position.y + player_sprite.offset.y),
        16, 16,
        rl.DARKGRAY,
    )
    sr.DrawSprite(&player_sprite, &player_texture, rl.WHITE)
    

    rl.EndMode2D()
    
    slider_rect:rl.Rectangle = {screen_size.x - 110, 10, 100, 25}
    rl.GuiSlider(slider_rect, "scale X", "", &player_sprite.scale.x, -1, 1)
    slider_rect.y += 30
    rl.GuiSlider(slider_rect, "scale Y", "", &player_sprite.scale.y, -1, 1)
    slider_rect.y += 30
    rl.GuiSlider(slider_rect, "rotate", "", &player_sprite.rotation, -180, 180)
    
    rl.EndDrawing()
}
