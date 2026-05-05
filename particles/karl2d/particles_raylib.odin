package particles_karl2d

import "../../karl2d"
Texture :: karl2d.Texture
Color :: karl2d.Color
Vec2 :: karl2d.Vec2

import pa ".."
Particle :: pa.Particle

rectf :: [4]f32

// Optional struct
ParticleKarl2d::struct{
    partickle: Particle,
    texture: ^karl2d.Texture,
    tint: karl2d.Color,
}

DrawPartickleKarl2d::proc(karl_partickle: ^ParticleKarl2d){
    DrawParticle(&karl_partickle.partickle, karl_partickle.texture, karl_partickle.tint)
}

DrawParticle::proc(particle:^pa.Particle, texture:^Texture, tint:Color){
    source_rect:rectf
    source_rect.xy = particle.tex_pos[particle.image_index]
    source_rect.zw = particle.size

    target_rect:rectf
    target_rect.xy = particle.position + particle.offset.xy
    target_rect.zw = source_rect.zw

    origin:karl2d.Vec2 = particle.origin * {abs(particle.scale.x), abs(particle.scale.y)}

    if particle.scale.x < 0 {
        source_rect.z *= -1
    }

    if particle.scale.y < 0 {
        origin.y = particle.origin.y * particle.scale.y - target_rect.w * particle.scale.y
        source_rect.w *= -1
    }
    target_rect.zw *= particle.scale
    
    karl2d.draw_texture_fit(
		texture^,
		transmute(karl2d.Rect)source_rect,
		transmute(karl2d.Rect)target_rect,
		origin,
		particle.rotation,
        tint,
	)
}