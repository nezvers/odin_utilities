package particles
import "core:testing"

vec2 :: [2]f32

// State of particle instance
Particle::struct{
    tex_pos:[]vec2,
    size:vec2, // texture region size
    position:vec2,
    origin:vec2,
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

// --- Tests ---

@(test)
test_particle_frames_over_lifetime :: proc(t: ^testing.T) {
    frames: [4]vec2 = {{0, 0}, {8, 0}, {16, 0}, {24, 0}}
    particle: Particle = {tex_pos = frames[:], frame_time = 1, active = true}              // lives for one second

    UpdateFrames(&particle, 0.1)
    testing.expect_value(t, particle.image_index, 0)
    UpdateFrames(&particle, 0.2)
    testing.expect_value(t, particle.image_index, 1)
    UpdateFrames(&particle, 0.6)
    testing.expect_value(t, particle.image_index, 3)
    testing.expect_value(t, particle.active, true)

    UpdateFrames(&particle, 0.2)                                                           // past the end of the life
    testing.expect_value(t, particle.active, false)
    testing.expect(t, particle.time < 1, "the time wraps back")
}

@(test)
test_particle_shorter_lifetime :: proc(t: ^testing.T) {
    frames: [2]vec2 = {{0, 0}, {8, 0}}
    particle: Particle = {tex_pos = frames[:], frame_time = 4, active = true}              // a quarter of a second
    UpdateFrames(&particle, 0.1)
    testing.expect_value(t, particle.image_index, 0)
    UpdateFrames(&particle, 0.1)
    testing.expect_value(t, particle.image_index, 1)
    UpdateFrames(&particle, 0.1)
    testing.expect_value(t, particle.active, false)
}
