#+private file
package game

// import "core:fmt"
import "../../../karl2d"

import partickles "../.."
import glue "../../karl2d"
Particle:: partickles.Particle

import "core:math/rand"
import "core:math"
PI :: math.PI

@(private="package")
dust_state: GameState = {
    init,
    finit,
    process,
    draw,
}

partickle_texture: karl2d.Texture
frame_pos:[]Vec2 = {{0,0},{2,0},{4,0},{6,0},}

DUST_COUNT::100
dust_particles:[DUST_COUNT]Particle

init :: proc() {
    background_color = karl2d.BLACK
    partickle_texture = karl2d.load_texture_from_bytes(#load("../../../assets/textures/dust_4_strip.png"))

    for i:int = 0; i < len(dust_particles); i += 1 {
        SpawnDustParticle(&dust_particles[i])
    }
}

finit :: proc() {
    karl2d.destroy_texture(partickle_texture)
}

process :: proc() {
    delta_time:f32 = karl2d.get_frame_time()
    for i:int = 0; i < len(dust_particles); i += 1 {
        particle:^Particle = &dust_particles[i]
        UpdateDustParticle(particle, delta_time)
        if !particle.active {
            SpawnDustParticle(particle)
        }
    }
}

draw :: proc() {
    for i:int = 0; i < len(dust_particles); i += 1 {
        DrawDustParticle(&dust_particles[i])
    }
}

SpawnDustParticle::proc(particle:^Particle){
    particle.tex_pos = frame_pos[:]
    particle.size = {2,2}
    particle.origin = {0,0}
    particle.scale = {4,4}

    window_size:Vec2 = get_window_size()
    particle.position = {
        50.0 + rand.float32() * (window_size.x - 100.0),
        50.0 + rand.float32() * (window_size.y - 100.0),
    }
    particle.velocity = {
        -20 + rand.float32() * 40,
        -20 + rand.float32() * 40,
    }
    particle.time = rand.float32() * 0.5
    particle.frame_time = 1.0/(0.5 + rand.float32() * 3.0)
    
    // Pixel art dust can be only rotated in 90 degrees or 0.25 TAU
    rotation_choices:[4]f32 = {0.0, 0.25, 0.5, 0.75}
    particle.rotation = rand.choice(rotation_choices[:]) * math.TAU
    particle.active = true
    // particle.image_index is calculated in update
}

UpdateDustParticle::proc(particle:^Particle, delta_time:f32){
    particle.position += particle.velocity * delta_time
    partickles.UpdateFrames(particle, delta_time)
}

DrawDustParticle::proc(particle:^Particle){
    // They also have random time start, so not same fade in for every one
    fade_in_and_out:f32 = math.sin(particle.time * math.PI)
    color:Color = karl2d.WHITE
    color.a = u8(255 * fade_in_and_out)
    glue.DrawParticle(particle, &partickle_texture, color)
}