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

SPRITE_SIZE :sp.vec2f: {16, 16}
// All positions on texture
tex_pos:[]sp.vec2f = {{0,0}, {16,0}, {32,0}, {48,0}, {64,0}, {80,0}, {96,0}}
anim_idle:sp.Frames = {tex_pos[0:1], SPRITE_SIZE}
anim_walk:sp.Frames = {tex_pos[1:7], SPRITE_SIZE}
anim_up:sp.Frames = {tex_pos[5:6], SPRITE_SIZE}
anim_down:sp.Frames = {tex_pos[6:7], SPRITE_SIZE}

player_animations:sp.AnimationSet = { 
    {&anim_idle, &anim_walk, &anim_up, &anim_down}, 
    0, 0, (1 / 12), 0,
}
PlayerStates::enum {
    idle,
    walk,
    jump_up,
    jump_down,
}

game_init :: proc() {
    sprite_texture = rl.LoadTexture("demo/player_sheet.png")
    sp.ChangeAnimation(&player_animations, cast(u32)PlayerStates.idle)
}

game_shutdown :: proc() {
	rl.UnloadTexture(sprite_texture)
}

update :: proc() {
    sp.UpdateAnimation(&player_animations, rl.GetFrameTime())
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.WHITE)

    rect:rl.Rectangle = transmute(rl.Rectangle)sp.GetFrame(&player_animations)

    rl.DrawTextureRec(sprite_texture, rect, {100, 100}, rl.WHITE)

    rl.EndDrawing()
}
