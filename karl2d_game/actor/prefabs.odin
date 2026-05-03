package actor


import karl2d "../../karl2d"
import spr "../../sprite"
import "../sfx"
// import spr_glue "../../sprite/karl2d"

CHAR_SIZE :spr.vec2: {16, 16}
// All positions on texture
tex_pos_char: []spr.vec2 = {{0,0}, {16,0}, {32,0}, {48,0}, {64,0}, {80,0}, {96,0}, {112,0}}
anim_char_idle: spr.Frames = {tex_pos_char[0:2], CHAR_SIZE}
anim_char_walk: spr.Frames = {tex_pos_char[2:8], CHAR_SIZE}
anim_char_up: spr.Frames = {tex_pos_char[5:6], CHAR_SIZE}
anim_char_down: spr.Frames = {tex_pos_char[7:8], CHAR_SIZE}

character_animations: spr.AnimationSet = { 
    {&anim_char_idle, &anim_char_walk, &anim_char_up, &anim_char_down}, 
    cast(u32)ActorAnimations.char_idle, 0, 12, 0,
}

// Templates - required to assign textures on load
prefab_plumber: Actor = {
    visuals = {
        animation_set = character_animations,
        position = {0, 0},
        offset = {-8, -16},
        scale = {1, 1},
        rotation = 0.0,
        visible = true,
        tint = karl2d.WHITE,
    },
    properties = {
        acceleration = 3.0,
        deacceleration = 3.0,
        max_speed = 120.0,
    },
    health = {
        value = 100,
    },
    damage_sound = &sfx.damage,
    spawn_callback = nil,
    draw_callback = nil,
    update_callback = UpdateCharacter, // TODO: each character its specialized update
    type = .Player,
}

prefab_electrician: Actor = {
    visuals = {
        animation_set = character_animations,
        position = {0, 0},
        offset = {-8, -16},
        scale = {1, 1},
        rotation = 0.0,
        visible = true,
        tint = karl2d.WHITE,
    },
    properties = {
        acceleration = 3.0,
        deacceleration = 3.0,
        max_speed = 120.0,
    },
    health = {
        value = 100,
    },
    damage_sound = &sfx.damage,
    spawn_callback = nil,
    draw_callback = DrawElectricianCallback,
    update_callback = UpdateCharacter, // TODO: each character its specialized update
    type = .Player,
}

prefab_zombie: Actor = {
    visuals = {
        animation_set = character_animations,
        position = {0, 0},
        offset = {-8, -16},
        scale = {1, 1},
        rotation = 0.0,
        visible = true,
        tint = karl2d.WHITE,
    },
    properties = {
        acceleration = 3.0,
        deacceleration = 1.0,
        max_speed = 20.0,
    },
    health = {
        value = 100,
    },
    // damage_sound = &sfx.damage,
    draw_callback = nil,
    spawn_callback = nil,
    update_callback = UpdateCharacter, // Overriden in enemies.odin Reset()
    type = .Enemy,
}