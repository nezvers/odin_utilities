package demo_common

// Drawing a sprite with the kit: where the frame is on the texture, where it goes on the screen, the pivot, the flip and the turn.
// The framework glue (sprite/raylib, sprite/karl2d) does the same with the draw call of its framework.

import sp ".."
import kit "../../demo_kit"

// A frame of the texture on the screen. A negative scale flips: the source is read backwards and the pivot moves with it.
DrawSpriteRects :: proc(ctx: ^kit.Context, target_rect: sp.rectf, source_rect: sp.rectf, sprite_origin: kit.Vec2, offset: kit.Vec2, scale: kit.Vec2, rotation: f32, texture: kit.Texture, tint: kit.Color) {
    target_rect: sp.rectf = target_rect
    source_rect: sp.rectf = source_rect
    target_rect.xy += offset

    origin: kit.Vec2 = sprite_origin * {abs(scale.x), abs(scale.y)}
    if scale.x < 0 {
        source_rect.z *= -1
    }
    if scale.y < 0 {
        origin.y = sprite_origin.y * scale.y - target_rect.w * scale.y
        source_rect.w *= -1
    }
    target_rect.zw *= scale
    kit.DrawTextureRect(ctx, texture, source_rect, target_rect, origin, rotation, tint)
}
