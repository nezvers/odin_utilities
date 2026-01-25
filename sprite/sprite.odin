package sprite

vec2f :: [2]f32
vec2i :: [2]int

rectf :: [4]f32
recti :: [4]int

// Data about Texture positions
// Frames for one animation
Frames :: struct {
    data:[]vec2f,
    size:vec2f, // texture region size
}

AnimationSet :: struct {
    frames:[]^Frames,
    animation_index:u32,
    image_index:u32, // index of current
    frame_duration:f32, // 1/framerate
    time:f32,
}

ChangeAnimation::proc(animation_set:^AnimationSet, new_animation:u32){
    assert(new_animation < cast(u32)len(animation_set.frames))
    animation_set.animation_index = new_animation
    animation_set.image_index = 0
    animation_set.time = 0 
}

UpdateAnimation::proc(animation_set:^AnimationSet, delta_time:f32){
    animation_set.time += delta_time * animation_set.frame_duration
    if animation_set.time < 1 {
        return
    }
    image_count:int = len(animation_set.frames[animation_set.animation_index].data)
    animation_set.image_index = (animation_set.image_index + cast(u32)animation_set.time) % cast(u32)image_count
}

GetFrame::proc(animation_set:^AnimationSet)->rectf {
    frame:^Frames = animation_set.frames[animation_set.animation_index]
    pos:vec2f = frame.data[animation_set.image_index]
    size:vec2f = frame.size
    return {pos.x, pos.y, size.x, size.y}
}