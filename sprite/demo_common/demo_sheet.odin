#+private file
package demo_common

// The same player as data: the frames are rows of a constant table (Sheet), the sprite only holds numbers (SheetSprite and Animator):
// sheet, clip, frame, time. It can be copied, put in prefab data and saved.

import sp ".."
import kit "../../demo_kit"

@(private="package")
demo_sheet: kit.Demo = {
    name = "sheet",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

CLIP_IDLE :: u16(0)
CLIP_WALK :: u16(1)
CLIP_UP :: u16(2)
CLIP_DOWN :: u16(3)

positions: [8]sp.vec2 = {{0, 0}, {16, 0}, {32, 0}, {48, 0}, {64, 0}, {80, 0}, {96, 0}, {112, 0}}
clips: [4]sp.Clip = {{0, 1}, {1, 7}, {5, 1}, {7, 1}}        // idle, walk, up, down: frames of the table
sheets: [1]sp.Sheet
sprite: sp.SheetSprite
copy_of_sprite: sp.SheetSprite
texture: kit.Texture

init :: proc(ctx: ^kit.Context) {
    sheets = {{frame_size = {16, 16}, frames = positions[:], clips = clips[:]}}
    sprite = {animator = {sheet = 0, clip = CLIP_WALK, frame_rate = 12}, position = {60, 60}, origin = {8, 16}, scale = {1, 1}}
    copy_of_sprite = sprite             // a sprite is plain data: this is a second sprite, not a reference
    copy_of_sprite.position = {100, 60}
    copy_of_sprite.scale = {-1, 1}
    texture = kit.TextureLoad(ctx, #load("../../assets/textures/player_sheet.png"))
}

finit :: proc(ctx: ^kit.Context) {
    kit.TextureUnload(ctx, texture)
}

update :: proc(ctx: ^kit.Context) {
    for key, clip in ([4]kit.Key{.N1, .N2, .N3, .N4}) {
        if kit.KeyPressed(&ctx.input, key) { sp.AnimatorChange(&sprite.animator, u16(clip)) }
    }
    sp.SheetSpriteUpdate(sheets[:], &sprite, ctx.delta_time)
    sp.SheetSpriteUpdate(sheets[:], &copy_of_sprite, ctx.delta_time)
}

draw :: proc(ctx: ^kit.Context) {
    kit.CameraBegin(ctx, {zoom = 4})
    draw_sheet_sprite(ctx, &sprite)
    draw_sheet_sprite(ctx, &copy_of_sprite)
    kit.CameraEnd(ctx)
    kit.DrawText(ctx, "SheetSprite: only numbers. Keys 1 - 4 change the clip of the first sprite, the second is a copy of it, flipped", {10, 10}, 16, kit.DARK_GRAY)
}

draw_sheet_sprite :: proc(ctx: ^kit.Context, sheet_sprite: ^sp.SheetSprite) {
    target, source := sp.SheetSpriteFrame(sheets[:], sheet_sprite)
    DrawSpriteRects(ctx, target, source, sheet_sprite.origin, sheet_sprite.offset, sheet_sprite.scale, sheet_sprite.rotation, texture, kit.WHITE)
}

script: []kit.Step = {
    kit.Wait(40),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return sprite.animator.clip == CLIP_WALK && sprite.animator.image > 0 || sprite.animator.time > 0 }, "the walk clip plays"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return copy_of_sprite.animator.image == sprite.animator.image }, "the copy plays by itself, in step with the original"),
    kit.Tap(.N3),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return sprite.animator.clip == CLIP_UP && sprite.animator.image == 0 && copy_of_sprite.animator.clip == CLIP_WALK }, "changing the clip of one does not touch its copy"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        frame := sp.AnimatorFrame(sheets[:], sprite.animator)
        return frame == sp.rectf{80, 0, 16, 16}
    }, "the up clip is the frame at 80,0 of the table"),
}
