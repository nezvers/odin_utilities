package weapon

import spr "../../sprite"
// import spr_glue "../../sprite/karl2d"
import karl2d "../../karl2d"
import "core:math"


// Default weapon "Animation"
tex_pos_weapon: []spr.vec2 = {{0,0}}
anim_weapon: spr.Frames = {tex_pos_weapon[:], {16, 16}}

// Templates - require assigned texture
shotgun: Weapon = {
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
    visible = true,
    tint = karl2d.WHITE,
}