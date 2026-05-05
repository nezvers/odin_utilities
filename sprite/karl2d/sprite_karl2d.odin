package sprite_karl2d

import sp ".."
import "../../karl2d"

// Optional struct
SpriteKarl2d::struct{
    using sprite: sp.Sprite,
    texture: karl2d.Texture,
    tint: karl2d.Color,
    visible:bool,
}

DrawSpriteKarl2d::proc(karl_sprite: ^SpriteKarl2d){
    if !karl_sprite.visible { return }
    DrawSprite(&karl_sprite.sprite, karl_sprite.texture, karl_sprite.tint)
}

DrawSprite::proc(sprite:^sp.Sprite, texture:karl2d.Texture, tint:karl2d.Color){
    target_rect, source_rect: = sp.GetSpriteFrame(sprite)
    target_rect.xy += sprite.offset.xy

    // target_rect.zw *= sprite.scale
    origin:karl2d.Vec2 = sprite.origin * {abs(sprite.scale.x), abs(sprite.scale.y)}

    if sprite.scale.x < 0 {
        source_rect.z *= -1
    }

    if sprite.scale.y < 0 {
        origin.y = sprite.origin.y * sprite.scale.y - target_rect.w * sprite.scale.y
        source_rect.w *= -1
    }
    target_rect.zw *= sprite.scale
    
    karl2d.draw_texture_fit(
		texture,
		transmute(karl2d.Rect)source_rect,
		transmute(karl2d.Rect)target_rect,
		origin,
		sprite.rotation,
        tint,
	)
}