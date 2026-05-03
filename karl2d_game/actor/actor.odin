package actor

import spr "../../sprite"
import spr_glue "../../sprite/karl2d"
import karl2d "../../karl2d"
import "../weapon"
import "core:sort"
import "../../cool_math"
import "../projectile"
// import "core:math/rand"

vec2 :: [2]f32
ActorAnimations :: enum {
    char_idle = 0,
    char_walk = 1,
    char_jump_up = 2,
    char_jump_down = 3,
}

ActorType :: enum {
    Player,
    NPC,
    Zombie,
    Zombie_crawl,
}

ActorInput :: struct {
    move_dir:vec2,
    aim_dir:vec2,
    attack:bool,
}

ActorProperties :: struct {
    acceleration: f32,
    deacceleration: f32,
    max_speed: f32,
}

ActorState :: struct {
    velocity: vec2,
    attack_timer: f32,
}

Actor :: struct {
    using visuals: spr_glue.SpriteKarl2d,
    using input: ActorInput,
    using properties: ActorProperties,
    using state: ActorState,
    draw_callback: proc(^Actor),
    update_callback: proc(^Actor, f32),
    type:ActorType,
    id:int,
    weapon: ^weapon.Weapon,
}



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

character_sprite: spr_glue.SpriteKarl2d = {
    animation_set = character_animations,
    position = {0, 0},
    offset = {-8, -16},
    scale = {1, 1},
    rotation = 0.0,
}

// Actor Pool
MAX_ACTORS :: 16
actor_buffer: [MAX_ACTORS]Actor
actor_count: int
// For Y sorting
sorted_list: [MAX_ACTORS]^Actor

Reset :: proc() {
    actor_count = 0
}

GetNew :: proc()->(actor:^Actor, ok:bool) {
    if actor_count >= len(actor_buffer) {
        return
    }
    actor = &actor_buffer[actor_count]
    sorted_list[actor_count] = actor
    actor.id = actor_count
    actor_count += 1
    ok = true
    return
}

Init :: proc(actor: ^Actor, visuals: spr_glue.SpriteKarl2d, anim: u32) {
    assert(actor != nil)
    actor.visuals = visuals
    actor.visible = true
    actor.tint = karl2d.WHITE
    spr.ChangeAnimation(&actor.sprite.animation_set, anim)
}

Update :: proc(delta_time: f32) {
    actor:^Actor

    for i:int = 0; i < actor_count; i += 1 {
        actor = &actor_buffer[i]
        if actor.update_callback != nil {
            actor.update_callback(actor, delta_time)
        }
    }
}

UpdateCharacter :: proc(actor: ^Actor, delta_time:f32) {
    is_moving:bool = (actor.move_dir.x * actor.move_dir.x) + (actor.move_dir.y * actor.move_dir.y) > 0.01
    if is_moving {
        actor.velocity = LerpVelocity(actor.velocity, actor.move_dir * actor.max_speed, actor.acceleration * delta_time)
    } else {
        actor.velocity = LerpVelocity(actor.velocity, 0, actor.deacceleration * delta_time)
    }

    // Flip
    if actor.aim_dir.x > 0.01 {
        actor.scale.x = 1
    } else if actor.aim_dir.x < -0.01 {
        actor.scale.x = -1
    }
    UpdateAnimation(&actor.sprite.animation_set, is_moving)
    spr.UpdateSprite(&actor.sprite, delta_time)

    actor.position += actor.velocity * delta_time

    if actor.weapon != nil { UpdateActorWeapon(actor, delta_time) }
}

UpdateAnimation :: proc(anim_set: ^spr.AnimationSet, is_walking: bool) {
    if is_walking == (anim_set.animation_index == cast(u32)ActorAnimations.char_walk) {
        return
    }
    if is_walking{
        spr.ChangeAnimation(anim_set, cast(u32)ActorAnimations.char_walk)
    } else {
        spr.ChangeAnimation(anim_set, cast(u32)ActorAnimations.char_idle)
    }
}

LerpVelocity :: proc(from, to: vec2, t:f32)->vec2 {
    return from + (to - from) * t
}

Draw :: proc() {
    sort.quick_sort_proc(sorted_list[:actor_count], Ysort)

    for i:int = 0; i < actor_count; i += 1 {
        actor:^Actor = sorted_list[i]
        spr_glue.DrawSpriteKarl2d(actor)
        if actor.draw_callback == nil { continue }
        actor.draw_callback(actor)
    }
}

Ysort :: proc(a: ^Actor, b: ^Actor)->int {
    return (a.position.y > b.position.y) ? 1 : (a.position.y < b.position.y) ? -1 : 0
}

UpdateActorWeapon :: proc(actor: ^Actor, delta_time: f32) {
    if !actor.attack {
        actor.attack_timer += actor.weapon.fire_rate * delta_time
        if actor.attack_timer > 1 { 
            actor.attack_timer = 1
        }
        return
    }
    actor.attack_timer += actor.weapon.fire_rate * delta_time
    if actor.attack_timer < 1 { return }

    count:i32 = i32(actor.attack_timer)
    actor.attack_timer -= f32(count)
    for i:i32 = 0; i < count; i += 1 {
        actor.velocity += delta_time * actor.weapon.kickback * -actor.aim_dir
        for angle in actor.weapon.angles {
            projectile.SpawnProjectile(projectile.bullet1, actor.position + actor.aim_dir * 8, cool_math.Vec2Rotate(actor.aim_dir, angle), actor.weapon.spread)
        }
        // TODO: spawn spread
        if i < 1 { continue }
        // TODO: pre-heat projectile update by fire_rate
    }
}