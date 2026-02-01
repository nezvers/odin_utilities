package particles

vec2 :: [2]f32

// State of particle instance
Particle::struct{
    tex_pos:[]vec2,
    size:vec2, // texture region size
    position:vec2,
    offset:vec2,
    scale:vec2,
    velocity:vec2,
    rotation:f32,
    time:f32,       // 0 to 1, interpolates between frames
    frame_time:f32, // 1.0/lifetime
    image_index:int,
    active:bool,
}

UpdateFrames::proc(particle:^Particle, delta_time:f32){
    particle.time += delta_time * particle.frame_time
    if particle.time >= 1 {
        particle.time -= cast(f32)cast(i32)particle.time
        particle.active = false
        return
    }
    frame_count:int = len(particle.tex_pos)
    particle.image_index = cast(int)(cast(f32)frame_count * particle.time)
}