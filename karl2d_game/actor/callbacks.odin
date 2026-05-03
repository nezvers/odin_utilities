package actor


import spr "../../sprite"
import "../weapon"
import "../../cool_math"
import "../projectile"

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
            projectile.SpawnProjectile(projectile.prefab_bullet1, actor.position + actor.aim_dir * 8, cool_math.Vec2Rotate(actor.aim_dir, angle), actor.weapon.spread)
        }
        // TODO: spawn spread
        if i < 1 { continue }
        // TODO: pre-heat projectile update by fire_rate
    }
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

// TODO: remove gameplay logic
DrawActorCallback :: proc(actor_ptr: ^Actor) {
    #partial switch actor_ptr.type {
    case .Player :

    case .NPC :
        shotgun: = actor_ptr.weapon^
        shotgun.position = actor_ptr.position + {0, -5}
        shotgun.rotation = cool_math.Vec2Angle(actor_ptr.aim_dir)
        
        if actor_ptr.aim_dir.x < 0 {
            shotgun.scale.y = -1
            // shotgun.offset.y = -shotgun.offset.y + 16
        }
        weapon.Draw(&shotgun)
        
        // karl2d.draw_circle_outline(mouse_position, 3, 1, karl2d.LIGHT_GRAY)
    }
}