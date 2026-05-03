package weapon

import spr "../../sprite"
import "../projectile"
import "../sfx"
// import spr_glue "../../sprite/karl2d"
import karl2d "../../karl2d"
import "core:math"


// Default weapon "Animation"
tex_pos_weapon: []spr.vec2 = {{0,0}}
anim_weapon: spr.Frames = {tex_pos_weapon[:], {16, 16}}

// Templates - require assigned texture
prefab_shotgun: Weapon = {
    properties = {
        spread = math.PI * 0.015,
        fire_rate = 2,
        count = 5,
        kickback = 2000,
        angles = {-math.PI * 0.1, -math.PI * 0.05, 0, math.PI * 0.1, math.PI * 0.05},
    },
    sprite = {
        animation_set = {
            frames = {&anim_weapon},
        },
        offset = {-8, -8},
        scale = {1, 1},
    },
    bullet = &projectile.prefab_bullet1,
    sound = &sfx.gun,
    visible = true,
    tint = karl2d.WHITE,
    name = "Shotgun",
}


prefab_bite: Weapon = {
    properties = {
        spread = math.PI * 0.015,
        fire_rate = 2,
        count = 5,
        kickback = 2000,
        angles = {0},
    },
    sprite = {
        animation_set = {
            frames = {&anim_weapon},
        },
        offset = {-8, -8},
        scale = {1, 1},
    },
    bullet = &projectile.prefab_bite,
    visible = false,
    tint = karl2d.WHITE,
    name = "Bite",
}