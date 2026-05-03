package actor

import spr "../../sprite"
import spr_glue "../../sprite/karl2d"
import karl2d "../../karl2d"
import "../weapon"
import "core:sort"
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



// Actor Pool
MAX_ACTORS :: 32
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

Remove :: proc(actor:^Actor) {
    if actor.id >= actor_count { return }
    if actor.id != actor_buffer[actor.id].id { return }
    if actor_count == 0 { return }
    if actor.id == actor_count - 1 {
        actor_count -= 1
        return
    }
    new_actor: ^Actor = &actor_buffer[actor_count - 1]
    new_actor.id = actor.id
    actor_buffer[actor.id] = new_actor^
    actor_count -= 1
}

NewInstance :: proc(preset:Actor, pos:vec2)->(actor:^Actor, ok:bool) {
    actor,ok = GetNew()
    if !ok { return }
    actor^ = preset
    actor.position = pos
    // TODO: on spawn event - vfx, sound
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