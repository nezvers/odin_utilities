package sprite
import "core:testing"

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
    origin:vec2, // pivot point
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
    if animation_set.time < 1 { return }

    image_count:int = len(animation_set.frames[animation_set.animation_index].data)
    increment:u32 = cast(u32)animation_set.time
    animation_set.time -= cast(f32)increment
    animation_set.image_index = (animation_set.image_index + increment) % cast(u32)image_count
}

UpdateSprite::proc(sprite:^Sprite, delta_time:f32){
    UpdateAnimation(&sprite.animation_set, delta_time)
}

GetAnimationFrame::proc(animation_set:^AnimationSet)->rectf {
    frame:^Frames = animation_set.frames[animation_set.animation_index]
    pos:vec2 = frame.data[animation_set.image_index]
    size:vec2 = frame.size
    result:rectf = {pos.x, pos.y, size.x, size.y}
    return result
}

GetSpriteFrame::proc(sprite:^Sprite)->(sprite_rect:rectf, texture_rect:rectf) {
    texture_rect = GetAnimationFrame(&sprite.animation_set)
    sprite_rect.xy = sprite.position
    sprite_rect.zw = texture_rect.zw
    return
}

// --- Tests ---

@(private="file")
make_walk :: proc(frames: ^[2]Frames, positions: ^[6]vec2, pointers: ^[2]^Frames) -> AnimationSet {
    positions^ = {{0, 0}, {16, 0}, {32, 0}, {0, 16}, {16, 16}, {32, 16}}
    frames[0] = {data = positions[0:3], size = {16, 16}}
    frames[1] = {data = positions[3:5], size = {16, 16}}
    pointers^ = {&frames[0], &frames[1]}
    return {frames = pointers[:], frame_rate = 10}
}

@(test)
test_animation_advances_and_wraps :: proc(t: ^testing.T) {
    frames: [2]Frames
    positions: [6]vec2
    pointers: [2]^Frames
    set: AnimationSet = make_walk(&frames, &positions, &pointers)

    UpdateAnimation(&set, 0.05)                                                            // half a frame
    testing.expect_value(t, set.image_index, u32(0))
    UpdateAnimation(&set, 0.05)
    testing.expect_value(t, set.image_index, u32(1))
    UpdateAnimation(&set, 0.1)
    testing.expect_value(t, set.image_index, u32(2))
    UpdateAnimation(&set, 0.1)
    testing.expect_value(t, set.image_index, u32(0))                                       // wraps to the start

    UpdateAnimation(&set, 0.35)                                                            // several frames in one update keep the fraction
    testing.expect_value(t, set.image_index, u32(0))                                       // 3 frames on a loop of 3
    testing.expect(t, abs(set.time - 0.5) < 1e-4)
}

@(test)
test_animation_change_and_frame_rect :: proc(t: ^testing.T) {
    frames: [2]Frames
    positions: [6]vec2
    pointers: [2]^Frames
    set: AnimationSet = make_walk(&frames, &positions, &pointers)
    UpdateAnimation(&set, 0.1)

    ChangeAnimation(&set, 1)
    testing.expect_value(t, set.animation_index, u32(1))
    testing.expect_value(t, set.image_index, u32(0))                                       // starts from the first frame
    testing.expect_value(t, set.time, f32(0))
    testing.expect_value(t, GetAnimationFrame(&set), rectf{0, 16, 16, 16})

    UpdateAnimation(&set, 0.1)
    UpdateAnimation(&set, 0.1)
    testing.expect_value(t, set.image_index, u32(0))                                       // the second clip has only 2 frames
}

@(test)
test_sprite_frame_rects :: proc(t: ^testing.T) {
    frames: [2]Frames
    positions: [6]vec2
    pointers: [2]^Frames
    sprite: Sprite = {animation_set = make_walk(&frames, &positions, &pointers), position = {100, 50}}
    UpdateSprite(&sprite, 0.1)

    target, source := GetSpriteFrame(&sprite)
    testing.expect_value(t, source, rectf{16, 0, 16, 16})
    testing.expect_value(t, target, rectf{100, 50, 16, 16})
}
