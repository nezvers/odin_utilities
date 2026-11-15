package sprite_raylib

import rl "vendor:raylib"
import sp ".."

// Optional struct
SpriteRaylib::struct{
    sprite: sp.Sprite,
    texture: ^rl.Texture2D,
    tint: rl.Color,
}

DrawSpriteRaylib::proc(raylib_sprite:^SpriteRaylib) {
    DrawSprite(&raylib_sprite.sprite, raylib_sprite.texture, raylib_sprite.tint)
}

DrawSprite::proc(sprite:^sp.Sprite, texture:^rl.Texture, tint:rl.Color) {
    target_rect, source_rect: = sp.GetSpriteFrame(sprite)
    DrawSpriteRects(target_rect, source_rect, sprite.origin, sprite.offset, sprite.scale, sprite.rotation, texture, tint)
}

// A sprite whose animation is data (see sp.SheetSprite): the sheets are the table the sprite refers to
DrawSheetSprite::proc(sheets:[]sp.Sheet, sprite:^sp.SheetSprite, texture:^rl.Texture, tint:rl.Color) {
    target_rect, source_rect: = sp.SheetSpriteFrame(sheets, sprite)
    DrawSpriteRects(target_rect, source_rect, sprite.origin, sprite.offset, sprite.scale, sprite.rotation, texture, tint)
}

// The drawing of every kind of sprite: where the frame is on the texture, where it goes, and the pivot, flip and turn
DrawSpriteRects::proc(target_rect:sp.rectf, source_rect:sp.rectf, sprite_origin:[2]f32, offset:[2]f32, scale:[2]f32, rotation:f32, texture:^rl.Texture, tint:rl.Color) {
    target_rect: = target_rect
    source_rect: = source_rect
    target_rect.xy += offset

    origin:rl.Vector2 = sprite_origin * {abs(scale.x), abs(scale.y)}

    // a negative scale flips: the source is read backwards and the pivot moves with it
    if scale.x < 0 {
        source_rect.z *= -1
    }

    if scale.y < 0 {
        origin.y = sprite_origin.y * scale.y - target_rect.w * scale.y
        source_rect.w *= -1
    }
    target_rect.zw *= scale

    rl.DrawTexturePro(
        texture^,
        transmute(rl.Rectangle)source_rect,
        transmute(rl.Rectangle)target_rect,
        origin,
        rotation,
        tint,
    )
}
