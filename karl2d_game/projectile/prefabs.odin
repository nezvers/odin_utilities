package projectile

import karl2d "../../karl2d"
import spr "../../sprite"
import "../vfx"
// import spr_glue "../../sprite/karl2d"


// Default projectile "Animation"
tex_pos_projectile: []spr.vec2 = {{0,0}, {16,0}, {32,0}, {48,0}, {64,0}, {80,0}, {96,0}, {112,0}}
anim_projectile1: spr.Frames = {tex_pos_projectile[:1], {16, 16}}
anim_projectile5: spr.Frames = {tex_pos_projectile[:5], {16, 16}}

// Templates - require assigned texture
prefab_bullet1: Projectile = {
    state = {
        lifetime = 0.5,
    },
    properties = {
        kickback = 200,
        speed = 240,
        height = 7,
        damping = 0.05,
        damage = 50.0,
    },
    sprite = {
        animation_set = {
            frames = {&anim_projectile1},
        },
        offset = {-8, -8},
        scale = {1, 1},
    },
    visible = true,
    tint = karl2d.WHITE,
    vfx_impact = &vfx.prefab_impact,
}

prefab_bite: Projectile = {
    state = {
        lifetime = 0.42,
    },
    properties = {
        kickback = 100,
        speed = 0,
        height = 7,
        damping = 0.05,
        damage = 10.0,
        stay = true,
        dont_rotate = true,
    },
    sprite = {
        animation_set = {
            frames = {&anim_projectile5},
            frame_rate = 12,
        },
        offset = {-8, -8},
        scale = {1, 1},
    },
    visible = true,
    tint = karl2d.WHITE,
}