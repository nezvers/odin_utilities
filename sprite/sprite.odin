package sprite

vec2 :: [2]f32
vec2i :: [2]int

rectf :: [4]f32
recti :: [4]int

// Data about Texture positions
// Frames for one animation
Frames :: struct {
    data:[]vec2,
    size:vec2, // texture region size
}

AnimationSet :: struct {
    frames:[]^Frames,
    animation_index:u32,
    image_index:u32, // index of current
    frame_rate:f32,
    time:f32,
}

Sprite::struct{
    animation_set:AnimationSet,
    position:vec2,
    offset:vec2,
    scale:vec2,
    rotation:f32,
}

ChangeAnimation::proc(animation_set:^AnimationSet, new_animation:u32){
    assert(new_animation < cast(u32)len(animation_set.frames))
    animation_set.animation_index = new_animation
    animation_set.image_index = 0
    animation_set.time = 0 
}

UpdateAnimation::proc(animation_set:^AnimationSet, delta_time:f32){
    animation_set.time += delta_time * animation_set.frame_rate
    if animation_set.time < 1 {
        return
    }
    image_count:int = len(animation_set.frames[animation_set.animation_index].data)
    increment:u32 = cast(u32)animation_set.time
    animation_set.time -= cast(f32)increment
    animation_set.image_index = (animation_set.image_index + increment) % cast(u32)image_count
}

UpdateSprite::proc(sprite:^Sprite, dt:f32){
    UpdateAnimation(&sprite.animation_set, dt)
}

GetAnimationFrame::proc(animation_set:^AnimationSet)->rectf {
    frame:^Frames = animation_set.frames[animation_set.animation_index]
    pos:vec2 = frame.data[animation_set.image_index]
    size:vec2 = frame.size
    return {pos.x, pos.y, size.x, size.y}
}

GetSpriteFrame::proc(sprite:^Sprite)->(sprite_rect:rectf, texture_rect:rectf) {
    texture_rect = GetAnimationFrame(&sprite.animation_set)
    sprite_rect.xy = sprite.position
    sprite_rect.zw = texture_rect.zw
    return
}