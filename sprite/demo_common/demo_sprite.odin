#+private file
package demo_common

// A sprite with frame animations (Sprite and AnimationSet point at the frames) and the properties of its transform as sliders.

import sp ".."
import kit "../../demo_kit"

@(private="package")
demo_sprite: kit.Demo = {
    name = "sprite",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

PlayerStates :: enum {
    idle,
    walk,
    jump_up,
    jump_down,
}

SPRITE_SIZE :: sp.vec2{16, 16}
// All positions on texture
tex_pos: []sp.vec2 = {{0, 0}, {16, 0}, {32, 0}, {48, 0}, {64, 0}, {80, 0}, {96, 0}, {112, 0}}
anim_idle: sp.Frames
anim_walk: sp.Frames
anim_up: sp.Frames
anim_down: sp.Frames
anim_list: [4]^sp.Frames           // the animation set holds a slice of this: it has to outlive init
player_animations: sp.AnimationSet
player_sprite: sp.Sprite
player_texture: kit.Texture
frame_changes: int          // how many times the shown frame changed

init :: proc(ctx: ^kit.Context) {
    anim_idle = {tex_pos[0:1], SPRITE_SIZE}
    anim_walk = {tex_pos[1:8], SPRITE_SIZE}
    anim_up = {tex_pos[5:6], SPRITE_SIZE}
    anim_down = {tex_pos[7:8], SPRITE_SIZE}
    anim_list = {&anim_idle, &anim_walk, &anim_up, &anim_down}
    player_animations = {anim_list[:], u32(PlayerStates.idle), 0, 12, 0}
    player_sprite = {player_animations, {18, 60}, {8, 16}, {0, 0}, {1, 1}, 0.0}
    player_texture = kit.TextureLoad(ctx, #load("../../assets/textures/player_sheet.png"))
    sp.ChangeAnimation(&player_sprite.animation_set, u32(PlayerStates.walk))
    frame_changes = 0
}

finit :: proc(ctx: ^kit.Context) {
    kit.TextureUnload(ctx, player_texture)
}

last_image: u32
SLIDER_X :: 1000        // fixed, so a script knows where the sliders are on any window size

update :: proc(ctx: ^kit.Context) {
    sp.UpdateSprite(&player_sprite, ctx.delta_time)
    if player_sprite.animation_set.image_index != last_image {
        last_image = player_sprite.animation_set.image_index
        frame_changes += 1
    }
    // the animations by key
    for key, state in ([4]kit.Key{.N1, .N2, .N3, .N4}) {
        if kit.KeyPressed(&ctx.input, key) { sp.ChangeAnimation(&player_sprite.animation_set, u32(state)) }
    }
}

draw :: proc(ctx: ^kit.Context) {
    kit.CameraBegin(ctx, {zoom = 4})        // zoom in
    // Fetch frame manually without animation logic
    frame: sp.rectf = sp.GetAnimationFrame(&player_sprite.animation_set)
    kit.DrawTextureRect(ctx, player_texture, frame, {10, 10, frame.z, frame.w})

    // PLAYER SPRITE: the pivot, and the frame without scale, and the sprite
    position: kit.Vec2 = player_sprite.position
    kit.DrawLine(ctx, position - {8, 0}, position + {8, 0}, 1, kit.BLACK)
    kit.DrawLine(ctx, position - {0, 8}, position + {0, 8}, 1, kit.BLACK)
    kit.DrawRectOutline(ctx, {position.x + player_sprite.offset.x - player_sprite.origin.x, position.y + player_sprite.offset.y - player_sprite.origin.y, 16, 16}, 0.5, kit.DARK_GRAY)
    target, source := sp.GetSpriteFrame(&player_sprite)
    DrawSpriteRects(ctx, target, source, player_sprite.origin, player_sprite.offset, player_sprite.scale, player_sprite.rotation, player_texture, kit.WHITE)
    kit.CameraEnd(ctx)

    // the sliders are on the right, in screen pixels
    x: f32 = SLIDER_X
    kit.Slider(ctx, {x, 10, 220, 22}, "offset.x", &player_sprite.offset.x, -16, 16)
    kit.Slider(ctx, {x, 40, 220, 22}, "offset.y", &player_sprite.offset.y, -16, 16)
    kit.Slider(ctx, {x, 70, 220, 22}, "origin.x", &player_sprite.origin.x, -16, 16)
    kit.Slider(ctx, {x, 100, 220, 22}, "origin.y", &player_sprite.origin.y, -16, 16)
    kit.Slider(ctx, {x, 130, 220, 22}, "scale.x", &player_sprite.scale.x, -1, 1)
    kit.Slider(ctx, {x, 160, 220, 22}, "scale.y", &player_sprite.scale.y, -1, 1)
    kit.Slider(ctx, {x, 190, 220, 22}, "rotate", &player_sprite.rotation, -180, 180)
    kit.DrawText(ctx, "keys 1 - 4: idle, walk, jump up, jump down", {10, 10}, 16, kit.DARK_GRAY)
}

script: []kit.Step = {
    kit.Wait(40),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player_texture != kit.TEXTURE_NONE }, "the sprite sheet is loaded"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return frame_changes >= 3 }, "the walk animation advances at 12 frames per second"),
    kit.Tap(.N1),
    kit.Wait(30),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player_sprite.animation_set.animation_index == u32(PlayerStates.idle) && player_sprite.animation_set.image_index == 0 }, "idle is a single frame"),
    kit.Tap(.N3),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player_sprite.animation_set.animation_index == u32(PlayerStates.jump_up) }, "key 3 shows the jump frame"),
    // slider: drag the rotation slider to its right end
    kit.Drag({SLIDER_X + 200, 201}, {SLIDER_X + 400, 201}, 5),     // inside of the bar whatever the width of the label is, then past its right end
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player_sprite.rotation > 100 }, "the rotate slider turns the sprite"),
}
