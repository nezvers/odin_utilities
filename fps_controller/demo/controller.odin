#+private file
package demo
// https://github.com/raysan5/raylib/blob/master/examples/core/core_3d_camera_fps.c

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

GRAVITY :: 32
MAX_SPEED :: 20
CROUCH_SPEED :: 5
JUMP_FORCE :: 12
MAX_ACCEL :: 150
FRICTION :: 0.86
AIR_DRAG :: 0.98
CONTROL :: 15
CROUCH_HEIGHT :: 0
STAND_HEIGHT :: 1
BOTTOM_HEIGHT :: 0.5

sensitivity : Vector2 = { 0.001, 0.001, }

Player :: struct {
    position: Vector3,
    velocity : Vector3,
    dir : Vector3,
    look : Vector2,
    head_height: f32,
    walk_cycle: f32,
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
    // INPUT
    player.input.x = cast(i8)rl.IsKeyDown(rl.KeyboardKey.D) - cast(i8)rl.IsKeyDown(rl.KeyboardKey.A)
    player.input.y = cast(i8)rl.IsKeyDown(rl.KeyboardKey.W) - cast(i8)rl.IsKeyDown(rl.KeyboardKey.S)
    player.input.crouch = rl.IsKeyDown(rl.KeyboardKey.LEFT_CONTROL)
    player.input.jump = rl.IsKeyPressed(rl.KeyboardKey.SPACE)
    mouse_delta:Vector2 = rl.GetMouseDelta()
    player.look.x -= mouse_delta.x * sensitivity.x
    player.look.y += mouse_delta.y * sensitivity.y
    player.head_height = lerp(
        player.head_height,
        player.input.crouch ? CROUCH_HEIGHT : STAND_HEIGHT,
        delta_time * 20,
    )

    // CAMERA
    player_camera.position = {
        player.position.x,
        player.position.y + (BOTTOM_HEIGHT + player.head_height),
        player.position.z,
    }
    update_camera(&player_camera, &player.look)
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

update_camera :: proc(camera: ^Camera, look: ^Vector2){
    UP :Vector3: {0, 1, 0}
    TARGET :Vector3: {0, 0, -1}
    MAX_ANGLE :: 1.5706 // rl.Vector3Angle(UP, yaw) - 0.001

    if -look.y > MAX_ANGLE { look.y = -MAX_ANGLE}
    if -look.y < -MAX_ANGLE { look.y = MAX_ANGLE}
    
    yaw:Vector3 = rl.Vector3RotateByAxisAngle(TARGET, UP, look.x)
    right:Vector3 = rl.Vector3Normalize(rl.Vector3CrossProduct(yaw, UP))

    pitch_angle:f32 = -look.y // -lean.y
    pitch_angle = rl.Clamp(pitch_angle, -rl.PI/2 + 0.0001, rl.PI/2 - 0.0001)
    pitch:Vector3 = rl.Vector3RotateByAxisAngle(yaw, right, pitch_angle)

    camera.target = camera.position + pitch
}