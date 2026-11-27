#+private file
package demo_common

import "core:math/rand"
import pa ".."
import kit "../../demo_kit"

@(private="package")
demo_dust: kit.Demo = {
    name = "dust",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}

Particle :: pa.Particle

tex_pos: []pa.vec2 = {{0, 0}, {2, 0}, {4, 0}, {6, 0}}
particle_texture: kit.Texture

DUST_COUNT :: 100
dust_particles: [DUST_COUNT]Particle
spawned: int            // spawn calls, the first ones fill the pool, the later ones are respawns of particles that ended

init :: proc(ctx: ^kit.Context) {
    // a window test compares pictures: the dust must be the same every run (a normal run stays random)
    when kit.DEMO_TEST { rand.reset(4242) }
    ctx.background = kit.BLACK
    particle_texture = kit.TextureLoad(ctx, #load("../../assets/textures/dust_4_strip.png"))
    spawned = 0
    for i in 0 ..< len(dust_particles) {
        spawn_dust_particle(ctx, &dust_particles[i])
    }
}

finit :: proc(ctx: ^kit.Context) {
    kit.TextureUnload(ctx, particle_texture)
}

update :: proc(ctx: ^kit.Context) {
    for i in 0 ..< len(dust_particles) {
        particle: ^Particle = &dust_particles[i]
        particle.position += particle.velocity * ctx.delta_time
        pa.UpdateFrames(particle, ctx.delta_time)
        if !particle.active {
            spawn_dust_particle(ctx, particle)
        }
    }
}

draw :: proc(ctx: ^kit.Context) {
    for &particle in dust_particles {
        draw_particle(ctx, &particle)
    }
    kit.DrawText(ctx, "dust: 100 particles with a frame animation over their lifetime, respawned when they end", {10, 10}, 18, kit.GRAY)
}

spawn_dust_particle :: proc(ctx: ^kit.Context, particle: ^Particle) {
    spawned += 1
    particle.tex_pos = tex_pos[:]
    particle.size = {2, 2}
    particle.origin = {0, 0}
    particle.scale = {4, 4}
    particle.position = {
        50.0 + rand.float32() * (ctx.screen.x - 100.0),
        50.0 + rand.float32() * (ctx.screen.y - 100.0),
    }
    particle.velocity = {
        -20 + rand.float32() * 40,
        -20 + rand.float32() * 40,
    }
    particle.time = rand.float32() * 0.5
    particle.frame_time = 1.0 / (0.5 + rand.float32() * 3.0)
    // Pixel art dust can be only turned in 90 degrees
    rotation_choices: [4]f32 = {0, 90, 180, 270}
    particle.rotation = rand.choice(rotation_choices[:])
    particle.active = true
    // particle.image_index is calculated in update
}

// A particle is a frame of its strip: where it is on the texture, scaled, flipped by a negative scale, turned around its origin
draw_particle :: proc(ctx: ^kit.Context, particle: ^Particle) {
    // They also have random time start, so not the same fade in for every one
    fade: f32 = sin_fade(particle.time)
    tint: kit.Color = {255, 255, 255, u8(fade * 255)}

    source: kit.Rect
    source.xy = particle.tex_pos[particle.image_index]
    source.zw = particle.size
    target: kit.Rect
    target.xy = particle.position + particle.offset
    target.zw = source.zw

    origin: kit.Vec2 = particle.origin * {abs(particle.scale.x), abs(particle.scale.y)}
    if particle.scale.x < 0 { source.z *= -1 }
    if particle.scale.y < 0 {
        origin.y = particle.origin.y * particle.scale.y - target.w * particle.scale.y
        source.w *= -1
    }
    target.zw *= particle.scale
    kit.DrawTextureRect(ctx, particle_texture, source, target, origin, particle.rotation, tint)
}

sin_fade :: proc(t: f32) -> f32 {
    // sin(t * pi) without importing math for one use: the same curve as a parabola 4t(1-t), 0 at both ends, 1 in the middle
    return clamp(4 * t * (1 - t), 0, 1)
}

script: []kit.Step = {
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return particle_texture != kit.TEXTURE_NONE }, "the texture was loaded from the embedded bytes"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        for particle in dust_particles {
            if !particle.active || particle.image_index < 0 || particle.image_index >= len(tex_pos) { return false }
        }
        return true
    }, "every particle is alive and on a frame of its strip"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return spawned == DUST_COUNT }, "nothing ended yet"),
    kit.Wait(240),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return spawned > DUST_COUNT }, "particles that reached the end of their life are spawned again"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        for particle in dust_particles {
            if !particle.active { return false }
        }
        return true
    }, "the pool is full again after the respawns"),
    kit.Wait(2),
    kit.Capture("particles_dust_end"),
    kit.Wait(1),
}
