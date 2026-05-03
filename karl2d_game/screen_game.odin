#+ private file
package game

import "core:fmt"
import "core:math"
import "../karl2d"
import "ui"

// import "assets"
import "actor"
import "weapon"
import "projectile"
import "enemies"
import "sfx"
import "vfx"
import "assets"
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
music:karl2d.Audio_Stream

@(private="package")
kill_count:u64

init :: proc() {
    kill_count = 0
    background_color.r = 0xcf
    background_color.g = 0x96
    background_color.b = 0x8c
    // Resets Actor pool
    sfx.Load()
    vfx.Load()
    projectile.Load()
    projectile.Reset()
    weapon.Load()
    actor.Load()
    actor.Reset()


    // Spawn players
    actor_new, ok: = actor.NewInstance(actor.prefab_plumber, {})
    if ok {
        player_actor = actor_new
    }
    actor_new, ok = actor.NewInstance(actor.prefab_electrician, {30,30})
    if ok {
        npc_actor = actor_new
        npc_shotgun = weapon.prefab_shotgun
        actor_new.weapon = &npc_shotgun
    }

    enemies.Start()

    music = karl2d.load_audio_stream_from_bytes(assets.music_deeper_dungeon)
    karl2d.set_audio_stream_loop(music, true)
    karl2d.play_audio_stream(music)
    karl2d.set_audio_stream_volume(music, 0.4)
}

finit :: proc() {
    actor.Destroy()
    weapon.Destroy()
    projectile.Destroy()
    sfx.Destroy()
    vfx.Destroy()

    karl2d.stop_audio_stream(music)
    karl2d.destroy_audio_stream(music)
}

process :: proc() {
    karl2d.update_audio_stream(music)

    delta_time: f32 = karl2d.get_frame_time()

    update_player()
    // TODO: update enemies
    actor.Update(delta_time)
    projectile.Update(delta_time)
    vfx.Update(delta_time)

    // TODO: refactor out collision logic

    for i:int = (projectile.projectile_count - 1); i > -1; i -= 1 {
        proj:^projectile.Projectile = &projectile.projectile_pool[i]
        for a:int = (actor.actor_count - 1); a > -1; a -= 1 {
            act:^actor.Actor = &actor.actor_buffer[a]
            if (cast(u32)act.type & proj.collide) == 0 { continue }

            if cool_math.Vec2Mag2(act.position - proj.position) < 9 {
                act.health.value -= proj.damage
                if act.health.value <= 0 {
                    if act == player_actor || act == npc_actor {
                        change_game_state(screen_menu_state)
                    } else {
                        actor.Remove(act)
                        kill_count += 1
                    }
                    // TODO: death VFX
                } else {
                    act.velocity += proj.move_dir * proj.kickback
                    if act.damage_sound != nil {
                        sfx.Play(act.damage_sound)
                    }
                }
                if proj.vfx_impact != nil {
                    pos:Vec2 = proj.position - proj.height
                    _, _ = vfx.NewInstance(proj.vfx_impact^, pos)
                }
                if proj.sfx_impact != nil {
                    sfx.Play(proj.sfx_impact)
                }
                // TODO: impact VFX
                if !proj.stay{
                    projectile.Remove(proj)
                } else {
                    proj.damage = 0
                    proj.collide = 0
                }
                break
            }
        }
    }
    enemies.Update(delta_time)
    camera.target = player_actor.position
}

draw :: proc() {
    // karl2d.clear(background_color)
    karl2d.set_camera(camera)

    karl2d.draw_rect_outline({-16, -16, 32, 32}, 2, karl2d.GRAY)

    vfx.DrawBackground()
    actor.Draw()
    draw_rope(player_actor.position, npc_actor.position)

    projectile.Draw()
    vfx.DrawForeground()
    
    karl2d.set_camera(nil)
}

gui :: proc() {
    window_size: = get_window_size()
    score_size:f32 = window_size.y * 0.07
    score_text:string = fmt.tprintf("KILL COUNT: %v", kill_count)
    score_measure:Vec2 = karl2d.measure_text(score_text, score_size, karl2d.FONT_DEFAULT)
    score_position:Vec2 = ui.GetElementPosition({0,0,window_size.x, window_size.y}, score_measure, {0.001, 0.001}, {0,0})
	karl2d.draw_text(score_text, score_position, score_size, karl2d.DARK_BLUE)

}

update_player :: proc() {
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