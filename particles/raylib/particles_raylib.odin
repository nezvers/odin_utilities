package particles_raylib

import rl "vendor:raylib"
import pa ".."

rectf :: [4]f32

DrawParticle::proc(particle:^pa.Particle, texture:^rl.Texture, tint:rl.Color){
    source_rect:rectf
    source_rect.xy = particle.tex_pos[particle.image_index]
    source_rect.zw = particle.size

    target_rect:rectf
    target_rect.xy = particle.position
    target_rect.zw = source_rect.zw * particle.scale
    origin:rl.Vector2 = -particle.offset * {abs(particle.scale.x), abs(particle.scale.y)}

    if particle.scale.x < 0 {
        source_rect.z *= -1
    }

    if particle.scale.y < 0 {
        source_rect.w *= -1
        origin.y += -particle.offset.y * particle.scale.y
    }

    rl.DrawTexturePro(
        texture^, 
        transmute(rl.Rectangle)source_rect, 
        transmute(rl.Rectangle)target_rect,
        origin,
        particle.rotation,
        tint,
    )
}