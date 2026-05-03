package projectile

import karl2d "../../karl2d"
import spr "../../sprite"
// import spr_glue "../../sprite/karl2d"


// Default projectile "Animation"
tex_pos_projectile: []spr.vec2 = {{0,0}}
anim_projectile: spr.Frames = {tex_pos_projectile[:], {16, 16}}

// Templates - require assigned texture
prefab_bullet1: Projectile = {
    state = {
        lifetime = 0.5,
    },
    properties = {
        kickback = 2000,
        speed = 240,
        height = 7,
        damping = 0.05,
    },
    sprite = {
        animation_set = {
            frames = {&anim_projectile},
        },
        offset = {-8, -8},
        scale = {1, 1},
    },
    visible = true,
    tint = karl2d.WHITE,
}