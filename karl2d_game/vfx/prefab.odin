package vfx

import karl2d "../../karl2d"
import spr "../../sprite"
// import spr_glue "../../sprite/karl2d"

// Default projectile "Animation"
tex_pos_vfx: []spr.vec2 = {{0,0}, {16,0}, {32,0}, {48,0}, {64,0}, {80,0}, {96,0}, {112,0}}
// anim_strip_1: spr.Frames = {tex_pos_vfx[:1], {16, 16}}
// anim_strip_5: spr.Frames = {tex_pos_vfx[:5], {16, 16}}
anim_strip_5: spr.Frames = {tex_pos_vfx[:6], {16, 16}}

prefab_impact:Vfx = {
    sprite = {
        animation_set = {
            frames = {&anim_strip_5},
            frame_rate = 12,
        },
        offset = {-8, -8},
        scale = {1, 1},
    },
    visible = true,
    tint = karl2d.WHITE,
    is_foreground = true,
}