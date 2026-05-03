#+ private file
package game

// import "core:fmt"
import "core:math"
import "../karl2d"
// import "ui"

// import "assets"
import "actor"
import "weapon"
import "projectile"
import "../cool_math"
// import spr "../sprite"
// import spr_glue "../sprite/karl2d"


@(private="package")
screen_game_state: GameState = {
    init,
    finit,
    process,
    draw,
    gui,
}

player_actor: ^actor.Actor
npc_actor: ^actor.Actor

npc_shotgun: weapon.Weapon


init :: proc() {
    background_color = karl2d.WHITE
    // Resets Actor pool
    actor.Load()
    actor.Reset()
    projectile.Load()
    projectile.Reset()
    weapon.Load()

    npc_shotgun = weapon.shotgun

    // character_sprite_tmp: = actor.character_sprite
    actor_new, ok: = actor.NewInstance(actor.prefab_plumber, {})
    if ok {
        player_actor = actor_new
    }
    actor_new, ok = actor.NewInstance(actor.prefab_electrician, {30,30})
    if ok {
        npc_actor = actor_new
        actor_new.weapon = &npc_shotgun
    }
}

finit :: proc() {
    actor.Destroy()
    weapon.Destroy()
    projectile.Destroy()
}

process :: proc() {
    delta_time: f32 = karl2d.get_frame_time()

    // PLAYER
    player_dir:Vec2 = get_player_direction()
    player_actor.input.move_dir = player_dir
    player_actor.input.aim_dir = player_dir

    npc_dir:Vec2 = get_npc_direction()
    npc_actor.input.move_dir = npc_dir
    
    mouse_position: = get_world_mouse_position()
    mouse_distance:Vec2 = mouse_position - (npc_actor.position + {0, -5})
    npc_actor.input.aim_dir = cool_math.Vec2Norm(mouse_distance)
    npc_actor.input.attack = karl2d.mouse_button_is_held(.Left)

    actor.Update(delta_time)
    projectile.Update(delta_time)

    camera.target = player_actor.position
}

draw :: proc() {
    // karl2d.clear(background_color)
    karl2d.set_camera(camera)

    karl2d.draw_rect_outline({-16, -16, 32, 32}, 2, karl2d.GRAY)

    actor.Draw()
    draw_rope(player_actor.position, npc_actor.position)

    projectile.Draw()
    
    karl2d.set_camera(nil)
}

gui :: proc() {
    // window_size: = get_window_size()
    // title_size:f32 = window_size.y * 0.1
    // measure_title:Vec2 = karl2d.measure_text(TITLE, title_size, karl2d.FONT_DEFAULT)
    // title_position:Vec2 = ui.GetElementPosition(transmute(ui.Rect)projected_rect, measure_title, {0.5, 0.3})

	// karl2d.draw_text(TITLE, {projected_rect.x, projected_rect.y} + title_position, title_size, karl2d.DARK_BLUE)
}

get_player_direction :: proc()->Vec2 {
    axis:Vec2 = {
        cast(f32)cast(i32)karl2d.key_is_held(.D) - cast(f32)cast(i32)karl2d.key_is_held(.A),
        cast(f32)cast(i32)karl2d.key_is_held(.S) - cast(f32)cast(i32)karl2d.key_is_held(.W),
    }
    result:Vec2 = cool_math.Vec2Norm(axis)
    return result
}

get_npc_direction :: proc()->Vec2 {
    distance:Vec2 = player_actor.position - npc_actor.position
    distance_len:f32 = cool_math.Vec2Mag(distance)
    DISTANCE_MIN :: 40
    if distance_len < DISTANCE_MIN {
        return {}
    }
    distance_len -= DISTANCE_MIN
    STRENGTH_DEFAULT :: 32
    ratio:f32 = distance_len / STRENGTH_DEFAULT
    dir:Vec2 = cool_math.Vec2Norm(distance)
    return dir * ratio
}

draw_rope :: proc(from, to: Vec2) {
    a:Vec2 = {from.x, from.y - 7}
    b:Vec2 = {to.x, to.y - 7}
    distance:Vec2 = b - a
    c:Vec2 = from + distance * 0.5 + {0, -7}

    curve:f32 = 50 + (10 - 50) * math.min(1, cool_math.Vec2Mag2(distance * 0.5 * 0.1))

    SEGMENT_COUNT :: 20
    for i:int=0; i < SEGMENT_COUNT-1; i += 1 {
        t1:f32 = cast(f32)i/ SEGMENT_COUNT
        t2:f32 = cast(f32)(i+1)/ SEGMENT_COUNT
        p1: Vec2 = cool_math.Vec2Lerp(a, cool_math.Vec2Lerp(c + {0, curve}, b, t1), t1)
        p2: Vec2 = cool_math.Vec2Lerp(a, cool_math.Vec2Lerp(c + {0, curve}, b, t2), t2)
        karl2d.draw_line(p1, p2, 1, karl2d.LIGHT_GRAY)
    }
}

draw_actor_callback :: proc(actor_ptr: ^actor.Actor) {
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