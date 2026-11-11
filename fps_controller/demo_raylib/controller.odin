#+private file
package demo_raylib
// https://github.com/raysan5/raylib/blob/master/examples/core/core_3d_camera_fps.c
// No actual physics, just movement. Player code is in player.odin, see controller_box3d.odin for physics

import rl "vendor:raylib"
Color :: rl.Color

@(private="package")
state_controller:State = {
    init,
    finit,
    update,
    draw,
}

player : Player = {}

player_camera:Camera = {
    fovy = 60,
    projection = .PERSPECTIVE,
}

init :: proc() {
    rl.DisableCursor() // Capture mouse
    player_audio_init()

    player = {}
    player.head_height = STAND_HEIGHT

    player_camera.up = {0, 1, 0}
    player_camera.target = {0, 0, -1}
}

finit :: proc() {
    player_audio_close()
}

update :: proc() {
    delta_time:f32 = rl.GetFrameTime()
    update_input(&player, delta_time)
    if player.input.shoot {
        rl.PlaySound(sound_gun)
    }
    update_velocity(&player, delta_time)
    update_collisions(&player, delta_time)

    // CAMERA
    update_camera_animations(&player, &player_camera.fovy, delta_time)
    player_camera.position = {
        player.position.x,
        player.position.y + (CROUCH_HEIGHT + player.head_height), // +bobbing
        player.position.z,
    }
    update_camera(&player_camera, &player.look, &player.lean, &player.step)
}

draw :: proc() {
    rl.BeginMode3D(player_camera)
    draw_level()
    rl.EndMode3D()
}

// Some kind of visual treat and movement reference
draw_level :: proc() {
    FLOOR_EXTENT :: 25
    TILE_SIZE :: 5
    TILE_COLOR1 :Color: { 150, 200, 200, 255 }
    TILE_COLOR2 :Color: rl.LIGHTGRAY

    for y:int = -FLOOR_EXTENT; y < FLOOR_EXTENT; y += 1 {
        for x:int = -FLOOR_EXTENT; x < FLOOR_EXTENT; x += 1 {
            if (y & 1 == 1) && (x & 1 == 1) {
                rl.DrawPlane(
                    {cast(f32)(x * TILE_SIZE), 0, cast(f32)(y * TILE_SIZE)},
                    {TILE_SIZE, TILE_SIZE},
                    TILE_COLOR1,
                )
            } else
            if (y & 1 == 0) && (x & 1 == 0) {
                rl.DrawPlane(
                    {cast(f32)(x * TILE_SIZE), 0, cast(f32)(y * TILE_SIZE)},
                    {TILE_SIZE, TILE_SIZE},
                    TILE_COLOR2,
                )
            }
        }
    }

    TOWER_SIZE :Vector3: {16, 32, 16}
    TOWER_COLOR :Color: { 150, 200, 200, 255 }

    tower_pos:Vector3 = {16, 16, 16}
    rl.DrawCubeV(tower_pos, TOWER_SIZE, TOWER_COLOR)
    rl.DrawCubeWiresV(tower_pos, TOWER_SIZE, TOWER_COLOR)

    tower_pos.x *= -1
    rl.DrawCubeV(tower_pos, TOWER_SIZE, TOWER_COLOR)
    rl.DrawCubeWiresV(tower_pos, TOWER_SIZE, TOWER_COLOR)

    tower_pos.z *= -1
    rl.DrawCubeV(tower_pos, TOWER_SIZE, TOWER_COLOR)
    rl.DrawCubeWiresV(tower_pos, TOWER_SIZE, TOWER_COLOR)

    tower_pos.x *= -1
    rl.DrawCubeV(tower_pos, TOWER_SIZE, TOWER_COLOR)
    rl.DrawCubeWiresV(tower_pos, TOWER_SIZE, TOWER_COLOR)

    rl.DrawSphere({300, 300, 0}, 100, {255, 0, 0, 255})
}

// Replace with physics engine implementation, see controller_box3d.odin
update_collisions :: proc(player: ^Player, delta_time: f32) {
    player.position += player.velocity * delta_time

    // Fancy collision against floor
    if player.position.y <= 0 {
        player.position.y = 0
        player.velocity.y = 0
        if !player.is_grounded {
            player.is_grounded = true
            rl.PlaySound(sound_land)
        }
    }
}
