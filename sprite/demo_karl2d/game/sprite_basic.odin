#+private file
package game

// import "core:fmt"
import "../../../karl2d"
Rect :: karl2d.Rect

import sp "../.."
import glue "../../karl2d"

import "core:math"
PI :: math.PI

@(private="package")
sprite_state: GameState = {
    init,
    finit,
    process,
    draw,
}

player_texture: karl2d.Texture

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

init :: proc() {
    background_color = karl2d.WHITE
    player_texture = karl2d.load_texture_from_bytes(#load("../../../assets/textures/player_sheet.png"))
    sp.ChangeAnimation(&player_sprite.animation_set, cast(u32)PlayerStates.walk)
}

finit :: proc() {
    karl2d.destroy_texture(player_texture)
}

process :: proc() {
    sp.UpdateSprite(&player_sprite, karl2d.get_frame_time())
}

draw :: proc() {
	// Draw current frame as preview
    frame_rect:Rect = transmute(Rect)sp.GetAnimationFrame(&player_sprite.animation_set)
    karl2d.draw_texture_section(player_texture, frame_rect, {10, 10})

    // PLAYER SPRITE
    karl2d.draw_line(
        {player_sprite.position.x - 8,
        player_sprite.position.y},
        {player_sprite.position.x + 8,
        player_sprite.position.y},
        1,
        karl2d.BLACK,
    )
    karl2d.draw_line(
        {player_sprite.position.x,
        player_sprite.position.y - 8},
        {player_sprite.position.x,
        player_sprite.position.y + 8},
        1,
        karl2d.BLACK,
    )
    karl2d.draw_rect_outline(
        {(player_sprite.position.x + player_sprite.offset.x),
        (player_sprite.position.y + player_sprite.offset.y),
        16, 16},
        1,
        karl2d.DARK_GRAY,
    )
    glue.DrawSprite(&player_sprite, &player_texture, karl2d.WHITE)

    mouse: = get_local_mouse_position()
    is_held:bool = karl2d.mouse_button_is_held(.Left)
    slider_rect:Rect = {300, 10, 100, 25}

    @(static) scale_x:f32
    if Slider(&scale_x, &player_sprite.scale.x, -1, 1, slider_rect, mouse, is_held) {
    }
    slider_rect.y += 30

    @(static) scale_y:f32
    if Slider(&scale_y, &player_sprite.scale.y, -1, 1, slider_rect, mouse, is_held) {
    }
    slider_rect.y += 30

    @(static) rotation:f32
    if Slider(&rotation, &player_sprite.rotation, -PI, PI, slider_rect, mouse, is_held) {
    }
}

Slider :: proc(state: ^f32, value: ^f32, from:f32, to:f32, rect:Rect, pos:Vec2, active:bool)->(hover:bool) {
    state^ = NormalizeRange(value^, from, to)
    hover = IsHovering(pos, rect)
    if (hover && active){
        if karl2d.mouse_button_is_held(.Left) {
            state^ = (pos.x - rect.x) / rect.w
            value^ = Lerpf(from, to, state^)
        }
    }
    karl2d.draw_rect_outline(
        rect,
        1,
        karl2d.GRAY,
    )
    slider_val:Rect = rect
    slider_val.w *= state^
    karl2d.draw_rect(slider_val, karl2d.LIGHT_GRAY)
    return
}

NormalizeRange :: proc(value:f32, from:f32, to:f32)->f32 {
    return math.abs(value - from) / math.abs(to - from)
}

Lerpf :: proc(a:f32, b:f32, t:f32)->f32 {
    return a + (b - a) * t
}

IsHovering :: proc(p:Vec2, r:Rect)->bool {
    return p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h
}