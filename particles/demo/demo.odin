package demo

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

particle:Particle = {
    tex_pos = tex_pos[:],
    size = {2,2},
    position = {100,100},
    offset = {0,0},
    scale = {4,4},
    velocity = {4, 10},
    rotation = 0,
    time = 0,
    frame_time = 1.0/3.0,
    image_index = 1,
    alive = true,
}

game_init :: proc() {
    particle_texture = rl.LoadTexture("demo/dust_4_strip.png")
}

game_shutdown :: proc() {
	rl.UnloadTexture(particle_texture)
}

update :: proc() {
    particle.position += particle.velocity * rl.GetFrameTime()
    pa.Update(&particle, rl.GetFrameTime())
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

    pr.DrawParticle(&particle, &particle_texture, rl.WHITE)

    rl.EndDrawing()
}
