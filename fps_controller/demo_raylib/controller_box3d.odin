#+private file
package demo_raylib
// Same player as controller.odin, but collision is done by Box3D (vendor:box3d):
// the player is a capsule mover that gathers collision planes (World_CollideMover), solves them (SolvePlanes),
// casts the move (World_CastMover) and pushes dynamic bodies. Crates and spheres are simulated by the world.
// Based on the character mover in box2d/samples/geometric_mover.cpp

import "core:c"
import "core:math/linalg"
import b3 "vendor:box3d"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

@(private="package")
state_box3d:State = {
    init,
    finit,
    update,
    draw,
}

PHYSICS_GRAVITY :: 25
SUB_STEPS :: 4

MOVER_RADIUS :: 0.4
MOVER_BOTTOM :: 0.4
PLANE_CAPACITY :: 32
MIN_GROUND_NORMAL_Y :: 0.7

CRATE_COLUMNS :: 5
CRATE_ROWS :: 5
CRATE_COUNT :: CRATE_COLUMNS * CRATE_ROWS
SPHERE_COUNT :: 32
SPHERE_RADIUS :: 0.3
SHOT_SPEED :: 40

player : Player = {}
player_camera:Camera = {
    fovy = 60,
    projection = .PERSPECTIVE,
}

world: b3.WorldId

// Hulls have to stay alive as long as the shapes that use them
ground_hull: b3.BoxHull
tower_hull: b3.BoxHull
crate_hull: b3.BoxHull

crates: [CRATE_COUNT]b3.BodyId
spheres: [SPHERE_COUNT]b3.BodyId
next_sphere: int

TOWER_POSITIONS :[4]Vector3: {{16, 16, 16}, {-16, 16, 16}, {-16, 16, -16}, {16, 16, -16}}
TOWER_HALF :Vector3: {8, 16, 8}
GROUND_HALF :Vector3: {125, 0.5, 125}
CRATE_HALF :f32: 0.5

// Collision planes gathered by the mover
PlaneBuffer :: struct {
    planes: [PLANE_CAPACITY]b3.CollisionPlane,
    shapes: [PLANE_CAPACITY]b3.ShapeId,
    points: [PLANE_CAPACITY]Vector3,   // world position of the closest point
    origin: Vector3,
    count: int,
}
plane_buffer: PlaneBuffer
total_iterations: int

init :: proc() {
    rl.DisableCursor() // Capture mouse
    player_audio_init()

    player = {}
    player.head_height = STAND_HEIGHT
    player.position = {0, 0.1, 0}

    player_camera.up = {0, 1, 0}
    player_camera.target = {0, 0, -1}

    create_world()
}

finit :: proc() {
    destroy_world()
    player_audio_close()
}

create_world :: proc() {
    world_def: b3.WorldDef = b3.DefaultWorldDef()
    world_def.gravity = {0, -PHYSICS_GRAVITY, 0}
    world = b3.CreateWorld(world_def)

    shape_def: b3.ShapeDef = b3.DefaultShapeDef()

    // Ground, top surface at y = 0
    ground_hull = b3.MakeBoxHull(GROUND_HALF.x, GROUND_HALF.y, GROUND_HALF.z)
    body_def: b3.BodyDef = b3.DefaultBodyDef()
    body_def.position = {0, -GROUND_HALF.y, 0}
    ground: b3.BodyId = b3.CreateBody(world, body_def)
    _ = b3.CreateHullShape(ground, shape_def, &ground_hull.base)

    // Towers
    tower_hull = b3.MakeBoxHull(TOWER_HALF.x, TOWER_HALF.y, TOWER_HALF.z)
    for position in TOWER_POSITIONS {
        body_def = b3.DefaultBodyDef()
        body_def.position = position
        tower: b3.BodyId = b3.CreateBody(world, body_def)
        _ = b3.CreateHullShape(tower, shape_def, &tower_hull.base)
    }

    // A wall of crates to knock down
    crate_hull = b3.MakeCubeHull(CRATE_HALF)
    shape_def.density = 1
    for row in 0..<CRATE_ROWS {
        for column in 0..<CRATE_COLUMNS {
            body_def = b3.DefaultBodyDef()
            body_def.type = .dynamicBody
            body_def.position = {(f32(column) - 0.5 * (CRATE_COLUMNS - 1)) * 1.05, CRATE_HALF + f32(row) * 1.02, -12}
            crate: b3.BodyId = b3.CreateBody(world, body_def)
            _ = b3.CreateHullShape(crate, shape_def, &crate_hull.base)
            crates[row * CRATE_COLUMNS + column] = crate
        }
    }

    spheres = {}
    next_sphere = 0
}

destroy_world :: proc() {
    if b3.World_IsValid(world) {
        b3.DestroyWorld(world)
    }
    world = {}
}

shoot :: proc(origin: Vector3, direction: Vector3) {
    if b3.Body_IsValid(spheres[next_sphere]) {
        b3.DestroyBody(spheres[next_sphere])
    }

    body_def: b3.BodyDef = b3.DefaultBodyDef()
    body_def.type = .dynamicBody
    body_def.position = origin + direction
    body_def.linearVelocity = direction * SHOT_SPEED
    body: b3.BodyId = b3.CreateBody(world, body_def)

    shape_def: b3.ShapeDef = b3.DefaultShapeDef()
    shape_def.density = 4
    sphere: b3.Sphere = {radius = SPHERE_RADIUS}
    _ = b3.CreateSphereShape(body, shape_def, &sphere)

    spheres[next_sphere] = body
    next_sphere = (next_sphere + 1) % SPHERE_COUNT
}

// Capsule in the local space of the player position (feet). It shrinks when crouching.
mover_capsule :: proc(player: ^Player) -> b3.Capsule {
    top: f32 = MOVER_BOTTOM + 0.1 + 0.9 * player.head_height
    return {center1 = {0, MOVER_BOTTOM, 0}, center2 = {0, top, 0}, radius = MOVER_RADIUS}
}

collect_planes :: proc "c" (shape_id: b3.ShapeId, results: [^]b3.PlaneResult, count: c.int, user_context: rawptr) -> bool {
    buffer: ^PlaneBuffer = cast(^PlaneBuffer)user_context
    for i in 0..<int(count) {
        if buffer.count >= PLANE_CAPACITY { break }
        buffer.planes[buffer.count] = {plane = results[i].plane, pushLimit = max(f32), clipVelocity = true}
        buffer.shapes[buffer.count] = shape_id
        // The point is relative to the origin passed to CollideMover
        buffer.points[buffer.count] = buffer.origin + results[i].point
        buffer.count += 1
    }
    return true
}

update :: proc() {
    delta_time: f32 = rl.GetFrameTime()
    update_input(&player, delta_time)

    if rl.IsKeyPressed(.R) {
        destroy_world()
        create_world()
        player.position = {0, 0.1, 0}
        player.velocity = {}
    }

    if player.input.shoot {
        rl.PlaySound(sound_gun)
        forward: Vector3 = linalg.normalize(player_camera.target - player_camera.position)
        shoot(player_camera.position, forward)
    }

    update_velocity(&player, delta_time)
    update_mover(&player, delta_time)
    b3.World_Step(world, delta_time, SUB_STEPS)

    // CAMERA
    update_camera_animations(&player, &player_camera.fovy, delta_time)
    player_camera.position = {
        player.position.x,
        player.position.y + (CROUCH_HEIGHT + player.head_height),
        player.position.z,
    }
    update_camera(&player_camera, &player.look, &player.lean, &player.step)
}

// Quake like movement with Box3D collision, port of GeometricMover::Update
update_mover :: proc(player: ^Player, delta_time: f32) {
    capsule: b3.Capsule = mover_capsule(player)
    filter: b3.QueryFilter = b3.DefaultQueryFilter()
    target: Vector3 = player.position + player.velocity * delta_time
    tolerance: f32 = 0.01
    total_iterations = 0

    for _ in 0..<5 {
        plane_buffer.count = 0
        plane_buffer.origin = player.position
        b3.World_CollideMover(world, player.position, capsule, filter, collect_planes, &plane_buffer)
        result: b3.PlaneSolverResult = b3.SolvePlanes(target - player.position, raw_data(plane_buffer.planes[:]), i32(plane_buffer.count))
        total_iterations += int(result.iterationCount)

        fraction: f32 = b3.World_CastMover(world, player.position, capsule, result.delta, filter, nil, nil)
        delta: Vector3 = fraction * result.delta
        player.position += delta
        if linalg.dot(delta, delta) < tolerance * tolerance {
            break
        }
    }

    // Planes of the last iteration tell if the player stands on something
    was_grounded: bool = player.is_grounded
    have_ground: bool
    for i in 0..<plane_buffer.count {
        if plane_buffer.planes[i].plane.normal.y > MIN_GROUND_NORMAL_Y {
            have_ground = true
        }
    }
    // Avoid snapping to ground while still going up
    player.is_grounded = have_ground && player.velocity.y <= 0.01
    if player.is_grounded && !was_grounded {
        rl.PlaySound(sound_land)
    }

    push_bodies(player)

    // Stop pushing into surfaces so speed can't accumulate against a wall
    player.velocity = b3.ClipVector(player.velocity, raw_data(plane_buffer.planes[:]), i32(plane_buffer.count))
}

// Dynamic bodies that touch the mover get an impulse from the speed the mover moves into them
push_bodies :: proc(player: ^Player) {
    for i in 0..<plane_buffer.count {
        body: b3.BodyId = b3.Shape_GetBody(plane_buffer.shapes[i])
        if b3.Body_GetType(body) != .dynamicBody { continue }

        // Plane normals point at the mover
        normal: Vector3 = plane_buffer.planes[i].plane.normal
        approach: f32 = max(-linalg.dot(player.velocity, normal), 0)
        if approach > 0 {
            impulse: Vector3 = -normal * (b3.Body_GetMass(body) * approach * 0.5)
            b3.Body_ApplyLinearImpulse(body, impulse, plane_buffer.points[i], true)
        }
    }
}

draw :: proc() {
    rl.BeginMode3D(player_camera)
    draw_world()
    rl.EndMode3D()

    rl.DrawText("Box3D capsule mover: WASD, SPACE jump, CTRL crouch, LMB shoot, R reset", 10, 10, 20, rl.BLACK)
    rl.DrawText(rl.TextFormat("planes %d, solver iterations %d, %s", i32(plane_buffer.count), i32(total_iterations), "grounded" if player.is_grounded else "air"), 10, 36, 20, rl.DARKGRAY)
}

draw_world :: proc() {
    FLOOR_EXTENT :: 25
    TILE_SIZE :: 5
    for y in -FLOOR_EXTENT..<FLOOR_EXTENT {
        for x in -FLOOR_EXTENT..<FLOOR_EXTENT {
            if (y & 1 == 1) && (x & 1 == 1) {
                rl.DrawPlane({f32(x * TILE_SIZE), 0, f32(y * TILE_SIZE)}, {TILE_SIZE, TILE_SIZE}, {150, 200, 200, 255})
            } else if (y & 1 == 0) && (x & 1 == 0) {
                rl.DrawPlane({f32(x * TILE_SIZE), 0, f32(y * TILE_SIZE)}, {TILE_SIZE, TILE_SIZE}, rl.LIGHTGRAY)
            }
        }
    }

    for position in TOWER_POSITIONS {
        rl.DrawCubeV(position, TOWER_HALF * 2, {150, 200, 200, 255})
        rl.DrawCubeWiresV(position, TOWER_HALF * 2, {100, 150, 150, 255})
    }

    for crate in crates {
        if b3.Body_IsValid(crate) {
            draw_body(crate, proc() { rl.DrawCubeV({}, CRATE_HALF * 2, rl.BEIGE); rl.DrawCubeWiresV({}, CRATE_HALF * 2, rl.BROWN) })
        }
    }
    for sphere in spheres {
        if b3.Body_IsValid(sphere) {
            draw_body(sphere, proc() { rl.DrawSphere({}, SPHERE_RADIUS, rl.RED) })
        }
    }
}

// Draw at the transform of the body, drawing happens around the origin
draw_body :: proc(body: b3.BodyId, draw_shape: proc()) {
    position: Vector3 = b3.Body_GetPosition(body)
    axis, angle: = rl.QuaternionToAxisAngle(b3.Body_GetRotation(body))

    rlgl.PushMatrix()
    rlgl.Translatef(position.x, position.y, position.z)
    rlgl.Rotatef(angle * rl.RAD2DEG, axis.x, axis.y, axis.z)
    draw_shape()
    rlgl.PopMatrix()
}
