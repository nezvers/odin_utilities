package sprite_karl2d

import sp ".."
import "../../karl2d"

// Optional struct
SpriteKarl2d::struct{
    sprite: sp.Sprite,
    texture: ^karl2d.Texture,
    tint: karl2d.Color,
}

DrawSpriteRaylib::proc(karl_sprite: ^SpriteKarl2d){
    DrawSprite(&karl_sprite.sprite, karl_sprite.texture, karl_sprite.tint)
}

DrawSprite::proc(sprite:^sp.Sprite, texture:^karl2d.Texture, tint:karl2d.Color){
    target_rect, source_rect: = sp.GetSpriteFrame(sprite)

    target_rect.zw *= sprite.scale
    origin:karl2d.Vec2 = -sprite.offset * {abs(sprite.scale.x), abs(sprite.scale.y)}

    if sprite.scale.x < 0 {
        source_rect.z *= -1
    }

    if sprite.scale.y < 0 {
        source_rect.w *= -1
        origin.y += -sprite.offset.y * sprite.scale.y
    }
    
    karl2d.draw_texture_fit(
		texture^,
		transmute(karl2d.Rect)source_rect,
		transmute(karl2d.Rect)target_rect,
		origin,
		sprite.rotation,
        tint,
	)
}