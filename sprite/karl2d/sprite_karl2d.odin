package sprite_karl2d

import sp ".."
import "../../karl2d"
Texture :: karl2d.Texture
Vec2 :: karl2d.Vec2

// Optional struct
SpriteKarl2d::struct{
    using sprite: sp.Sprite,
    texture: Texture,
    tint: karl2d.Color,
    visible:bool,
}

DrawSpriteKarl2d::proc(karl_sprite: ^SpriteKarl2d){
    if !karl_sprite.visible { return }
    DrawSprite(&karl_sprite.sprite, karl_sprite.texture, karl_sprite.tint)
}

DrawSprite::proc(sprite:^sp.Sprite, texture:Texture, tint:karl2d.Color){
    target_rect, source_rect: = sp.GetSpriteFrame(sprite)
    DrawSpriteRects(target_rect, source_rect, sprite.origin, sprite.offset, sprite.scale, sprite.rotation, texture, tint)
}

// A sprite whose animation is data (see sp.SheetSprite): the sheets are the table the sprite refers to
SheetSpriteKarl2d::struct{
    using sprite: sp.SheetSprite,
    texture: Texture,
    tint: karl2d.Color,
    visible:bool,
}

DrawSheetSpriteKarl2d::proc(sheets:[]sp.Sheet, karl_sprite: ^SheetSpriteKarl2d){
    if !karl_sprite.visible { return }
    DrawSheetSprite(sheets, &karl_sprite.sprite, karl_sprite.texture, karl_sprite.tint)
}

DrawSheetSprite::proc(sheets:[]sp.Sheet, sprite:^sp.SheetSprite, texture:Texture, tint:karl2d.Color){
    target_rect, source_rect: = sp.SheetSpriteFrame(sheets, sprite)
    DrawSpriteRects(target_rect, source_rect, sprite.origin, sprite.offset, sprite.scale, sprite.rotation, texture, tint)
}

// The drawing of every kind of sprite: where the frame is on the texture, where it goes, and the pivot, flip and turn
DrawSpriteRects::proc(target_rect:sp.rectf, source_rect:sp.rectf, sprite_origin:Vec2, offset:Vec2, scale:Vec2, rotation:f32, texture:Texture, tint:karl2d.Color){
    target_rect: = target_rect
    source_rect: = source_rect
    target_rect.xy += offset

    origin:karl2d.Vec2 = sprite_origin * {abs(scale.x), abs(scale.y)}

    // a negative scale flips: the source is read backwards and the pivot moves with it
    if scale.x < 0 {
        source_rect.z *= -1
    }

    if scale.y < 0 {
        origin.y = sprite_origin.y * scale.y - target_rect.w * scale.y
        source_rect.w *= -1
    }
    target_rect.zw *= scale

    karl2d.draw_texture_fit(
		texture,
		transmute(karl2d.Rect)source_rect,
		transmute(karl2d.Rect)target_rect,
		origin,
		rotation,
        tint,
	)
}



DrawSpriteOscillate::proc(sprite:^sp.Sprite, texture:Texture, tint:karl2d.Color, osc: ^sp.OscillatorSprite, delta_time: f32){
    target_rect, source_rect: = sp.GetSpriteFrame(sprite)
    osc_offset:Vec2 = sp.OscilateProperty2D(&osc.offset, delta_time)
    target_rect.xy += sprite.offset + osc_offset

    osc_scale: Vec2 = sp.OscilateProperty2D(&osc.scale, delta_time) + sprite.scale

    osc_origin: Vec2 = sp.OscilateProperty2D(&osc.origin, delta_time) + sprite.origin
    osc_origin = osc_origin * {abs(osc_scale.x), abs(osc_scale.y)}

    if osc_scale.x < 0 {
        source_rect.z *= -1
    }

    if osc_scale.y < 0 {
        osc_origin.y = osc_origin.y * osc_scale.y - target_rect.w * osc_scale.y
        source_rect.w *= -1
    }
    target_rect.zw *= osc_scale
    
    osc_rotation: f32 = sp.OscilateProperty(&osc.rotation, delta_time)
    karl2d.draw_texture_fit(
		texture,
		transmute(karl2d.Rect)source_rect,
		transmute(karl2d.Rect)target_rect,
		osc_origin,
		sprite.rotation + osc_rotation,
        tint,
	)
}