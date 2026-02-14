package demo

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
Color :: rl.Color
Font :: rl.Font
Texture2D :: rl.Texture2D

import pa ".."
import pr "../raylib"
vec2::pa.vec2
Particle::pa.Particle

particle_texture: Texture2D
tex_pos:[]vec2 = {{0,0},{2,0},{4,0},{6,0},}

DUST_COUNT::100
dust_particles:[DUST_COUNT]Particle

screen_size:Vector2

game_init :: proc() {
    screen_size = { cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight() }

    particle_texture = rl.LoadTexture("../assets/textures/dust_4_strip.png")
    for i:int = 0; i < len(dust_particles); i += 1 {
        SpawnDustParticle(&dust_particles[i])
    }
}

game_shutdown :: proc() {
	rl.UnloadTexture(particle_texture)
}

update :: proc() {
    if rl.IsWindowResized() {
        screen_size = { cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight() }
    }

    delta_time:f32 = rl.GetFrameTime()
    for i:int = 0; i < len(dust_particles); i += 1 {
        particle:^Particle = &dust_particles[i]
        UpdateDustParticle(particle, delta_time)
        if !particle.active {
            SpawnDustParticle(particle)
        }
    }
    
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

    for i:int = 0; i < len(dust_particles); i += 1 {
        DrawDustParticle(&dust_particles[i])
    }
    

    rl.EndDrawing()
}

SpawnDustParticle::proc(particle:^Particle){
    particle.tex_pos = tex_pos[:]
    particle.size = {2,2}
    particle.offset = {0,0}
    particle.scale = {4,4}

    particle.position = {
        50.0 + rand.float32() * (screen_size.x - 100.0),
        50.0 + rand.float32() * (screen_size.y - 100.0),
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
    particle.position += particle.velocity * rl.GetFrameTime()
    pa.UpdateFrames(particle, rl.GetFrameTime())
}

DrawDustParticle::proc(particle:^Particle){
    // They also have random time start, so not same fade in for every one
    fade_in_and_out:f32 = math.sin(particle.time * math.PI)
    pr.DrawParticle(particle, &particle_texture, rl.ColorAlpha(rl.WHITE, fade_in_and_out))
}