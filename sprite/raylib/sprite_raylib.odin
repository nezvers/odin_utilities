package sprite_raylib

import rl "vendor:raylib"
import sp ".."

// Optional struct
SpriteRaylib::struct{
    sprite:sp.Sprite,
    texture:^rl.Texture2D,
}

DrawSpriteRaylib::proc(raylib_sprite:^SpriteRaylib){
    DrawSprite(&raylib_sprite.sprite, raylib_sprite.texture)
}

DrawSprite::proc(sprite:^sp.Sprite, texture:^rl.Texture){
    sprite_rect, texture_rect: = sp.GetSpriteFrame(sprite)

    abs_scale:sp.vec2 = {abs(sprite.scale.x), abs(sprite.scale.y)}
    // Scale X
    sprite_rect.x = sprite.position.x + sprite.offset.x * abs_scale.x
    sprite_rect.z *= abs_scale.x
    // Scale Y
    sprite_rect.y = sprite.position.y + sprite.offset.y * abs_scale.y
    sprite_rect.w *= abs_scale.y

    // Raylib specific texture region flip
    if (sprite.scale.x < 0) {
        texture_rect.z *= -1
    }
    if (sprite.scale.y < 0) {
        texture_rect.w *= -1
        sprite_rect.y += sprite.offset.y * sprite.scale.y
    }

    ORIGIN:rl.Vector2: {0, 0}
    rl.DrawTexturePro(
        texture^, 
        transmute(rl.Rectangle)texture_rect, 
        transmute(rl.Rectangle)sprite_rect,
        ORIGIN,
        0,
        rl.WHITE,
    )
}