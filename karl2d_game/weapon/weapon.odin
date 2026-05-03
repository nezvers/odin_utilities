package weapon

import spr "../../sprite"
import spr_glue "../../sprite/karl2d"
import karl2d "../../karl2d"
// import "core:math"

WeaponProperties :: struct {
    spread: f32,
    fire_rate: f32,
    count: u32,
    kickback: f32,
    angles: []f32,
}

Weapon :: struct {
    using visual: spr_glue.SpriteKarl2d,
    using properties: WeaponProperties,
}

Draw::proc(weapon: ^Weapon){
    sprite:^spr.Sprite = &weapon.sprite
    texture:karl2d.Texture = weapon.texture
    tint:karl2d.Color = weapon.tint

    target_rect, source_rect: = spr.GetSpriteFrame(sprite)

    target_rect.zw *= sprite.scale
    origin:karl2d.Vec2 = -sprite.offset * {abs(sprite.scale.x), abs(sprite.scale.y)}

    if sprite.scale.x < 0 {
        source_rect.z *= -1
    }

    if sprite.scale.y < 0 {
        origin.y = (-sprite.offset.y * sprite.scale.y) + source_rect.w
        source_rect.w *= -1
    }
    
    karl2d.draw_texture_fit(
		texture,
		transmute(karl2d.Rect)source_rect,
		transmute(karl2d.Rect)target_rect,
		origin,
		sprite.rotation,
        tint,
	)
}