package fps_controller

// First person movement and camera animation, framework agnostic: no input device, no drawing. A game (or a demo) reads its input
// into a PlayerInput, calls the procs below each frame and draws a camera from the View.
// Based on https://github.com/raysan5/raylib/blob/master/examples/core/core_3d_camera_fps.c
//
//     PlayerLook(&player, mouse_delta)
//     player.input = {x = 1, y = 0, jump = true}
//     jumped := PlayerUpdateVelocity(&player, dt)
//     player.position += player.velocity * dt          // your collision goes here, or PlayerCollideFloor for a flat floor
//     PlayerUpdateCameraAnimations(&player, &fov, dt)
//     PlayerView(&player, &view)                        // view.position, view.target, view.up for any renderer
//
// Y is up, -Z is forward at look 0. Strafe jumping works the way a boomer shooter does: the acceleration is clamped per frame, so
// turning the view while moving sideways in the air adds speed past the ground limit.

import "core:math"
import "core:math/ease"
import "core:math/linalg"

Vec2 :: [2]f32
Vec3 :: [3]f32

CYCLE_MULTIPLY :: 1
BLEND_SPEED :: 3
RECOIL_SPEED :: 40
RECOIL_ROTATION :: 0.03
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
FRONT_ROTATION :: 0.02
STRAFE_ROTATION :: 0.02
FOV_STANDING :: 60
FOV_MOVING :: 55
MAX_PITCH :: 1.5706

SENSITIVITY :: Vec2{0.001, 0.001}

PlayerInput :: struct {
    x: i8,              // -1 left, 1 right
    y: i8,              // -1 back, 1 forward
    crouch: bool,
    jump: bool,         // pressed this frame
    shoot: bool,        // pressed this frame, drives the recoil animation
}

Player :: struct {
    position: Vec3,
    velocity: Vec3,
    move_dir: Vec3,
    look: Vec2,         // mouse camera rotation: yaw, pitch
    lean: Vec2,         // movement camera rotation
    head_height: f32,   // lerp between crouch and standing
    step: Vec2,         // head movement: side and vertical
    walk_cycle: f32,    // 0..1 animation time
    walk_blend: f32,
    recoil_timer: f32,
    input: PlayerInput,
    is_grounded: bool,
}

// What a renderer needs of the camera
View :: struct {
    position: Vec3,
    target: Vec3,
    up: Vec3,
    fov_y: f32,         // degrees
}

PlayerInit :: proc(player: ^Player, position: Vec3 = {}) {
    player^ = {position = position, head_height = STAND_HEIGHT}
}

// Turn the view by a mouse movement in pixels
PlayerLook :: proc(player: ^Player, mouse_delta: Vec2) {
    player.look.x -= mouse_delta.x * SENSITIVITY.x
    player.look.y += mouse_delta.y * SENSITIVITY.y
}

// Gravity, jump, the wanted direction and the acceleration. Returns true when the player jumped in this call (play the sound).
PlayerUpdateVelocity :: proc(player: ^Player, delta_time: f32) -> (jumped: bool) {
    player.velocity.y -= delta_time * GRAVITY
    if player.is_grounded && player.input.jump {
        player.velocity.y = JUMP_FORCE
        player.is_grounded = false
        jumped = true
    }

    // Direction
    front: Vec2 = {math.sin(player.look.x), math.cos(player.look.x)}
    right: Vec2 = {math.cos(-player.look.x), math.sin(-player.look.x)}
    input: Vec2 = {f32(player.input.x), f32(-player.input.y)}
    desired_dir: Vec3 = {
        input.x * right.x + input.y * front.x,
        0,
        input.x * right.y + input.y * front.y,
    }
    player.move_dir = linalg.lerp(player.move_dir, desired_dir, delta_time * CONTROL)

    // Acceleration
    decel: f32 = FRICTION if player.is_grounded else AIR_DRAG
    hvel: Vec3 = {player.velocity.x * decel, 0, player.velocity.z * decel}
    if linalg.length(hvel) < MAX_SPEED * 0.01 { hvel = {} }

    // This is what creates strafing: the acceleration to add is clamped by the maximum acceleration, so a player can make the speed
    // faster by bringing the direction closer to the angle of the horizontal velocity. https://youtu.be/v3zT3Z5apaM?t=165
    speed: f32 = linalg.dot(hvel, player.move_dir)
    max_speed: f32 = CROUCH_SPEED if player.input.crouch else MAX_SPEED
    accel: f32 = clamp(max_speed - speed, 0, MAX_ACCEL * delta_time)
    hvel.x += player.move_dir.x * accel
    hvel.z += player.move_dir.z * accel
    player.velocity.x = hvel.x
    player.velocity.z = hvel.z
    return
}

// The simplest collision: a floor at y = 0. Moves the player, returns true on the frame it lands.
PlayerCollideFloor :: proc(player: ^Player, delta_time: f32) -> (landed: bool) {
    player.position += player.velocity * delta_time
    if player.position.y <= 0 {
        player.position.y = 0
        player.velocity.y = 0
        if !player.is_grounded {
            player.is_grounded = true
            landed = true
        }
    }
    return
}

// Crouch, head bob, lean, recoil and the field of view. `fov` is in degrees.
PlayerUpdateCameraAnimations :: proc(player: ^Player, fov: ^f32, delta_time: f32) {
    player.head_height = linalg.lerp(player.head_height, 0 if player.input.crouch else f32(STAND_HEIGHT), delta_time * 20)

    if player.input.shoot {
        player.recoil_timer = 1
    } else if player.recoil_timer > 0 {
        player.recoil_timer = max(player.recoil_timer - delta_time * RECOIL_SPEED, 0)
    }

    moving: bool = player.input.x != 0 || player.input.y != 0
    if moving {
        player.walk_cycle += delta_time * CYCLE_MULTIPLY
        player.walk_cycle -= math.floor(player.walk_cycle)
        player.walk_blend = min(player.walk_blend + delta_time * BLEND_SPEED, 1)
    } else {
        player.walk_blend = max(player.walk_blend - delta_time * BLEND_SPEED, 0)
    }

    // Head bobbing
    step_sin: f32 = math.sin(player.walk_cycle * math.TAU)
    player.step.x = step_sin * STEP_SIDE * player.walk_blend
    step_cos_2: f32 = math.cos(player.walk_cycle * math.TAU * 2)
    player.step.y = step_cos_2 * STEP_HEIGHT * player.walk_blend

    player.lean.x = linalg.lerp(player.lean.x, f32(player.input.x) * STRAFE_ROTATION, delta_time * 10)
    player.lean.y = linalg.lerp(player.lean.y, f32(player.input.y) * FRONT_ROTATION, delta_time * 10)
    player.lean.y -= RECOIL_ROTATION * ease.cubic_in(player.recoil_timer)

    target_fov: f32 = FOV_MOVING if player.is_grounded && moving else FOV_STANDING
    fov^ = linalg.lerp(fov^, target_fov, delta_time * BLEND_SPEED)
}

// The camera of the player: at the head, looking where the mouse says, tilted by the lean, shaken by the steps
PlayerView :: proc(player: ^Player, view: ^View) {
    UP :: Vec3{0, 1, 0}
    FORWARD :: Vec3{0, 0, -1}

    // looking straight up or down is the limit
    player.look.y = clamp(player.look.y, -MAX_PITCH, MAX_PITCH)

    yaw: Vec3 = rotate(FORWARD, UP, player.look.x)
    right: Vec3 = linalg.normalize(linalg.cross(yaw, UP))
    pitch_angle: f32 = clamp(-player.look.y - player.lean.y, -math.PI / 2 + 0.0001, math.PI / 2 - 0.0001)
    pitch: Vec3 = rotate(yaw, right, pitch_angle)

    step_offset: Vec3 = right * player.step.x
    step_offset.y += player.step.y

    view.up = rotate(UP, pitch, player.lean.x)
    view.position = player.position + {0, CROUCH_HEIGHT + player.head_height, 0} + step_offset
    view.target = view.position + pitch
}

// A vector turned around an axis
rotate :: proc(vector: Vec3, axis: Vec3, angle: f32) -> Vec3 {
    q: quaternion128 = linalg.quaternion_angle_axis(angle, axis)
    return linalg.quaternion_mul_vector3(q, vector)
}

// The forward direction of the view on the ground plane
PlayerForward :: proc(player: ^Player) -> Vec3 {
    return {-math.sin(player.look.x), 0, -math.cos(player.look.x)}
}

PlayerHorizontalSpeed :: proc(player: ^Player) -> f32 {
    return linalg.length(Vec3{player.velocity.x, 0, player.velocity.z})
}
