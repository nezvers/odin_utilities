package sprite_raylib

import rl "vendor:raylib"
import sp ".."

// Optional struct
SpriteRaylib::struct{
    sprite: sp.Sprite,
    texture: ^rl.Texture2D,
    tint: rl.Color,
}

DrawSpriteRaylib::proc(raylib_sprite:^SpriteRaylib){
    DrawSprite(&raylib_sprite.sprite, raylib_sprite.texture, raylib_sprite.tint)
}

DrawSprite::proc(sprite:^sp.Sprite, texture:^rl.Texture, tint:rl.Color){
    target_rect, source_rect: = sp.GetSpriteFrame(sprite)
    target_rect.xy += sprite.offset.xy

    origin:rl.Vector2 = sprite.origin * {abs(sprite.scale.x), abs(sprite.scale.y)}

    if sprite.scale.x < 0 {
        source_rect.z *= -1
    }

    if sprite.scale.y < 0 {
        origin.y = sprite.origin.y * sprite.scale.y - target_rect.w * sprite.scale.y
        source_rect.w *= -1
    }
    target_rect.zw *= sprite.scale

    rl.DrawTexturePro(
        texture^, 
        transmute(rl.Rectangle)source_rect, 
        transmute(rl.Rectangle)target_rect,
        origin,
        sprite.rotation,
        tint,
    )
}