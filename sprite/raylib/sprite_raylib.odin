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
    sprite_rect, texture_rect: = sp.GetSpriteFrame(sprite)

    abs_scale:sp.vec2 = {abs(sprite.scale.x), abs(sprite.scale.y)}
    // Scale X
    sprite_rect.x = sprite.position.x + sprite.offset.x * abs_scale.x
    sprite_rect.z *= abs_scale.x
    // Scale Y
    sprite_rect.y = sprite.position.y + sprite.offset.y * abs_scale.y

    origin:rl.Vector2 = {0,0}
    // Raylib specific texture region flip
    if (sprite.scale.x < 0) {
        texture_rect.z *= -1
    }
    if (sprite.scale.y < 0) {
        texture_rect.w *= -1
        sprite_rect.y += sprite.offset.y * sprite.scale.y
        // origin.y -= sprite_rect.w
    }
    sprite_rect.w *= abs_scale.y


    // sprite_rect.xy += origin
    rl.DrawTexturePro(
        texture^, 
        transmute(rl.Rectangle)texture_rect, 
        transmute(rl.Rectangle)sprite_rect,
        origin,
        sprite.rotation,
        tint,
    )
}