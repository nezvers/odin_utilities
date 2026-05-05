package particles_raylib

import rl "vendor:raylib"
import pa ".."

rectf :: [4]f32

DrawParticle::proc(particle:^pa.Particle, texture:^rl.Texture, tint:rl.Color){
    source_rect:rectf
    source_rect.xy = particle.tex_pos[particle.image_index]
    source_rect.zw = particle.size

    target_rect:rectf
    target_rect.xy = particle.position + particle.offset.xy
    target_rect.zw = source_rect.zw

    origin:rl.Vector2 = particle.origin * {abs(particle.scale.x), abs(particle.scale.y)}

    if particle.scale.x < 0 {
        source_rect.z *= -1
    }

    if particle.scale.y < 0 {
        origin.y = particle.origin.y * particle.scale.y - target_rect.w * particle.scale.y
        source_rect.w *= -1
    }
    target_rect.zw *= particle.scale

    rl.DrawTexturePro(
        texture^, 
        transmute(rl.Rectangle)source_rect, 
        transmute(rl.Rectangle)target_rect,
        origin,
        particle.rotation,
        tint,
    )
}