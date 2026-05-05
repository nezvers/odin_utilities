#+private file
package game

import "core:fmt"
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
tex_pos: []sp.vec2 = {{0,0}, {16,0}, {32,0}, {48,0}, {64,0}, {80,0}, {96,0}, {112,0}}
anim_idle: sp.Frames = {tex_pos[0:2], SPRITE_SIZE}
anim_walk: sp.Frames = {tex_pos[2:8], SPRITE_SIZE}
anim_up: sp.Frames = {tex_pos[5:6], SPRITE_SIZE}
anim_down: sp.Frames = {tex_pos[7:8], SPRITE_SIZE}

player_animations:sp.AnimationSet = { 
    {&anim_idle, &anim_walk, &anim_up, &anim_down}, 
    cast(u32)PlayerStates.idle, 0, 12, 0,
}

player_sprite:sp.Sprite = {
    player_animations,
    {18, 50},
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
    ZOOM :: 8
    camera:karl2d.Camera
    camera.zoom = ZOOM
    karl2d.set_camera(camera)

    frame_rect:Rect = transmute(Rect)sp.GetAnimationFrame(&player_sprite.animation_set)
    karl2d.draw_texture_rect(player_texture, frame_rect, {10, 10})

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
    glue.DrawSprite(&player_sprite, player_texture, karl2d.WHITE)
    karl2d.set_camera(nil)

    karl2d.draw_text("Fetch frame manually without transforming", {30, 5 * ZOOM}, 20, karl2d.BLACK)
    karl2d.draw_text("Draw frame with modification", {30, 30 * ZOOM}, 20, karl2d.BLACK)
    karl2d.draw_text("Hold CTRL: default values", {300, 30 * ZOOM}, 20, karl2d.BLACK)
    img_index:u32 = player_sprite.animation_set.image_index
    karl2d.draw_text(fmt.tprintf("image_index: %v", img_index), {300, 20 * ZOOM}, 20, karl2d.BLACK)

    mouse: = get_local_mouse_position()
    is_held:bool = karl2d.mouse_button_is_held(.Left)
    slider_rect:Rect = {300, 34 * ZOOM, 300, 25}

    @(static) off_x:f32
    if Slider(&off_x, &player_sprite.offset.x, -16, 16, slider_rect, mouse, is_held, fmt.tprintf("offset.x = %.2v", player_sprite.offset.x)) {
        if karl2d.key_is_held(.Left_Control) {
            player_sprite.offset.x = -8
        }
    }
    slider_rect.y += 30

    @(static) off_y:f32
    if Slider(&off_y, &player_sprite.offset.y, -16, 16, slider_rect, mouse, is_held, fmt.tprintf("offset.y = %.2v", player_sprite.offset.y)) {
        if karl2d.key_is_held(.Left_Control) {
            player_sprite.offset.y = -16
        }
    }
    slider_rect.y += 30

    @(static) scale_x:f32
    if Slider(&scale_x, &player_sprite.scale.x, -2, 2, slider_rect, mouse, is_held, fmt.tprintf("scale.x = %.2v", player_sprite.scale.x)) {
        if karl2d.key_is_held(.Left_Control) {
            player_sprite.scale.x = 1
        }
    }
    slider_rect.y += 30

    @(static) scale_y:f32
    if Slider(&scale_y, &player_sprite.scale.y, -2, 2, slider_rect, mouse, is_held, fmt.tprintf("scale.y = %.2v", player_sprite.scale.y)) {
        if karl2d.key_is_held(.Left_Control) {
            player_sprite.scale.y = 1
        }
    }
    slider_rect.y += 30

    @(static) rotation:f32
    if Slider(&rotation, &player_sprite.rotation, -PI, PI, slider_rect, mouse, is_held, fmt.tprintf("rotation = %.2v", player_sprite.rotation)) {
        if karl2d.key_is_held(.Left_Control) {
            player_sprite.rotation = 0
        }
    }
}