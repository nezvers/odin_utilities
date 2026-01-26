package demo

import rl "vendor:raylib"
import sp ".."


Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
Color :: rl.Color
Font :: rl.Font
Texture2D :: rl.Texture2D

screen_size:Vector2
sprite_texture: Texture2D

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
    {100, 200},
    {-8, -16},
    {1, 1},
}

game_init :: proc() {
    sprite_texture = rl.LoadTexture("demo/player_sheet.png")
    sp.ChangeAnimation(&player_sprite.animation_set, cast(u32)PlayerStates.walk)
}

game_shutdown :: proc() {
	rl.UnloadTexture(sprite_texture)
}

update :: proc() {
    sp.UpdateSprite(&player_sprite, rl.GetFrameTime())
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.WHITE)

    // Draw current frame as preview
    frame_rect:rl.Rectangle = transmute(rl.Rectangle)sp.GetAnimationFrame(&player_sprite.animation_set)
    rl.DrawTextureRec(sprite_texture, frame_rect, {100, 100}, rl.WHITE)


    sprite_rect, texture_rect: = sp.GetSpriteFrame(&player_sprite)

    // Test shapes
    rl.DrawRectangleLinesEx(transmute(rl.Rectangle)sprite_rect, 1, rl.DARKGRAY)
    rl.DrawLine(
        cast(i32)player_sprite.position.x,
        cast(i32)player_sprite.position.y - 16,
        cast(i32)player_sprite.position.x,
        cast(i32)player_sprite.position.y + 16,
        rl.BLACK,
    )

    // Player Sprite
    ORIGIN:rl.Vector2: {0, 0}
    rl.DrawTexturePro(
        sprite_texture, 
        transmute(rl.Rectangle)texture_rect, 
        transmute(rl.Rectangle)sprite_rect,
        ORIGIN,
        0,
        rl.WHITE,
    )

    rl.EndDrawing()
}
