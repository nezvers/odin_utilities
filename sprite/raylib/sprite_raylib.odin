package sprite_raylib

import rl "vendor:raylib"
import sp ".."

// Optional struct
SpriteRaylib::struct{
    sprite:sp.Sprite,
    texture:^rl.Texture2D,
    tint:rl.Color,
}

DrawSpriteRaylib::proc(raylib_sprite:^SpriteRaylib){
    DrawSprite(&raylib_sprite.sprite, raylib_sprite.texture, raylib_sprite.tint)
}

DrawSprite::proc(sprite:^sp.Sprite, texture:^rl.Texture, tint:rl.Color){
    target_rect, source_rect: = sp.GetSpriteFrame(sprite)

    target_rect.zw *= sprite.scale
    origin:rl.Vector2 = -sprite.offset * {abs(sprite.scale.x), abs(sprite.scale.y)}

    if sprite.scale.x < 0 {
        source_rect.z *= -1
    }

    if sprite.scale.y < 0 {
        source_rect.w *= -1
        origin.y += -sprite.offset.y * sprite.scale.y
    }

    rl.DrawTexturePro(
        texture^, 
        transmute(rl.Rectangle)source_rect, 
        transmute(rl.Rectangle)target_rect,
        origin,
        sprite.rotation,
        tint,
    )
}