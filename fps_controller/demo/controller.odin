#+private file
package demo
// https://github.com/raysan5/raylib/blob/master/examples/core/core_3d_camera_fps.c

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"
Camera :: rl.Camera3D
Vector3 :: rl.Vector3
Vector2 :: rl.Vector2
Color :: rl.Color

@(private="package")
state_controller:State = {
    init,
    finit,
    update,
    draw,
}

CYCLE_MULTIPLY :: 1
BLEND_SPEED :: 3
GRAVITY :: 32
MAX_SPEED :: 20
CROUCH_SPEED :: 5
JUMP_FORCE :: 12
MAX_ACCEL :: 150
FRICTION :: 0.86
AIR_DRAG :: 0.98
CONTROL :: 15
STAND_HEIGHT :: 1
CROUCH_HEIGHT :: 0.5 
STEP_HEIGHT :: 0.02
STEP_SIDE :: 0.02
STEP_ROTATION :: 0.005
FRONT_ROTATION :: 0.02
STRAFE_ROTATION :: 0.02

sensitivity : Vector2 = { 0.001, 0.001, }

Player :: struct {
    position: Vector3,
    velocity : Vector3,
    move_dir : Vector3,
    look : Vector2,
    lean : Vector2,
    head_height: f32,
    step: Vector2,
    walk_cycle: f32,
    walk_blend: f32,
    input : struct {
        x : i8,
        y : i8,
        crouch : bool,
        jump: bool,
    },
    is_grounded : bool,
}
player : Player = {}

player_camera:Camera = {
    fovy = 60,
    projection = .PERSPECTIVE,
}

lerp :: proc(a,b,t: f32)->f32 {
    return a + (b - a) * t
}

init :: proc() {
    rl.DisableCursor() // Capture mouse

    player = {}
    player.head_height = STAND_HEIGHT

    player_camera.up = {0, 1, 0}
    player_camera.target = {0, 0, -1}
}

finit :: proc() {
    
}

update :: proc() {
    delta_time:f32 = rl.GetFrameTime()
    update_input(&player, delta_time)
    update_velocity(&player, delta_time)
    update_collisions(&player, delta_time)
    
    // CAMERA
    update_camera_animations(&player, delta_time)
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

update_input :: proc(player: ^Player, delta_time: f32) {
    player.input.x = cast(i8)rl.IsKeyDown(rl.KeyboardKey.D) - cast(i8)rl.IsKeyDown(rl.KeyboardKey.A)
    player.input.y = cast(i8)rl.IsKeyDown(rl.KeyboardKey.W) - cast(i8)rl.IsKeyDown(rl.KeyboardKey.S)
    player.input.crouch = rl.IsKeyDown(rl.KeyboardKey.LEFT_CONTROL)
    player.input.jump = rl.IsKeyPressed(rl.KeyboardKey.SPACE)

    mouse_delta:Vector2 = rl.GetMouseDelta()
    player.look.x -= mouse_delta.x * sensitivity.x
    player.look.y += mouse_delta.y * sensitivity.y
}

update_velocity :: proc(player: ^Player, delta_time: f32) {
    // Jump
    player.velocity.y -= delta_time * GRAVITY
    if player.is_grounded && player.input.jump {
        player.velocity.y = JUMP_FORCE
        player.is_grounded = false
    }

    // Direction
    front:Vector2 = {math.sin(player.look.x), math.cos(player.look.x)}
    right:Vector2 = {math.cos(-player.look.x), math.sin(-player.look.x)}
    input:Vector2 = {cast(f32)player.input.x, cast(f32)-player.input.y}
    desired_dir:Vector3 = {
        input.x * right.x + input.y * front.x,
        0,
        input.x * right.y + input.y * front.y,
    }
    player.move_dir = linalg.lerp(player.move_dir, desired_dir, delta_time * CONTROL)
    
    // Acceleration
    decel: f32 = player.is_grounded ? FRICTION : AIR_DRAG
    hvel: Vector3 = {player.velocity.x * decel, 0, player.velocity.z * decel}
    hvel_length: f32 = linalg.length(hvel)
    if hvel_length < (MAX_SPEED * 0.01) { hvel = {} }

    // This is what creates strafing
    speed: f32 = linalg.dot(hvel, player.move_dir)

    // Whenever the amount of acceleration to add is clamped by the maximum acceleration constant,
    // a Player can make the speed faster by bringing the direction closer to horizontal velocity angle
    // More info here: https://youtu.be/v3zT3Z5apaM?t=165
    max_speed: f32 = player.input.crouch ? CROUCH_SPEED : MAX_SPEED
    accel: f32 = math.clamp(max_speed - speed, 0, MAX_ACCEL * delta_time)
    hvel.x += player.move_dir.x * accel
    hvel.z += player.move_dir.z * accel

    player.velocity.x = hvel.x
    player.velocity.z = hvel.z
}

// Replace with physics engine
update_collisions :: proc(player: ^Player, delta_time: f32) {
    player.position += player.velocity * delta_time

    // Fancy collision against floor
    if player.position.y <= 0 {
        player.position.y = 0
        player.velocity.y = 0
        player.is_grounded = true
    }
}

update_camera_animations :: proc(player: ^Player, delta_time: f32) {
    // Crouch height
    player.head_height = lerp(
        player.head_height,
        player.input.crouch ? 0 : STAND_HEIGHT,
        delta_time * 20,
    )
    
    // Head bobbing
    if player.input.x != 0 || player.input.y != 0 {
        player.walk_cycle += delta_time * CYCLE_MULTIPLY
        player.walk_cycle -= math.floor(player.walk_cycle)
        player.walk_blend = math.min(player.walk_blend + delta_time * BLEND_SPEED, 1)
    } else {
        player.walk_blend = math.max(player.walk_blend - delta_time * BLEND_SPEED, 0)
    }

    step_sin: f32 = math.sin(player.walk_cycle * math.TAU)
    player.step.x = step_sin * STEP_SIDE * player.walk_blend

    step_cos_2: f32 = math.cos(player.walk_cycle * math.TAU * 2)
    player.step.y = step_cos_2 * STEP_HEIGHT * player.walk_blend

    player.lean.x = lerp(player.lean.x, cast(f32)player.input.x * STRAFE_ROTATION, delta_time * 10)
    player.lean.y = lerp(player.lean.y, cast(f32)player.input.y * FRONT_ROTATION, delta_time * 10)
    
    // FOV walk=55 normal=60
}

update_camera :: proc(camera: ^Camera, look: ^Vector2, lean: ^Vector2, step: ^Vector2){
    UP :Vector3: {0, 1, 0}
    TARGET :Vector3: {0, 0, -1}
    MAX_ANGLE :: 1.5706 // rl.Vector3Angle(UP, yaw) - 0.001

    if -look.y > MAX_ANGLE { look.y = -MAX_ANGLE}
    if -look.y < -MAX_ANGLE { look.y = MAX_ANGLE}
    
    yaw:Vector3 = rl.Vector3RotateByAxisAngle(TARGET, UP, look.x)
    right:Vector3 = rl.Vector3Normalize(rl.Vector3CrossProduct(yaw, UP))

    pitch_angle:f32 = -look.y - lean.y
    pitch_angle = rl.Clamp(pitch_angle, -rl.PI/2 + 0.0001, rl.PI/2 - 0.0001)
    pitch:Vector3 = rl.Vector3RotateByAxisAngle(yaw, right, pitch_angle)
    
    step_offset:Vector3 = right * step.x
    step_offset.y += step.y

    camera.up = rl.Vector3RotateByAxisAngle(UP, pitch, lean.x)
    camera.position += step_offset
    camera.target = camera.position + pitch
}