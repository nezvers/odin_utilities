package fps_controller_box3d

// Glue for Box3D (vendor:box3d): the Player of fps_controller with real collision. The player is a capsule mover. Every frame it gathers
// collision planes (World_CollideMover), solves them (SolvePlanes), casts the move (World_CastMover), clips the velocity (ClipVector) and
// pushes the dynamic bodies it touches. Ported from the Box2D GeometricMover sample. Physics, so no raylib or Karl2D in here.

import "core:c"
import "core:math/linalg"
import b3 "vendor:box3d"
import fps ".."

MOVER_RADIUS :: 0.4
MOVER_BOTTOM :: 0.4
PLANE_CAPACITY :: 32
MIN_GROUND_NORMAL_Y :: 0.7
SOLVER_PASSES :: 5

// Collision planes gathered by the mover
PlaneBuffer :: struct {
    planes: [PLANE_CAPACITY]b3.CollisionPlane,
    shapes: [PLANE_CAPACITY]b3.ShapeId,
    points: [PLANE_CAPACITY]fps.Vec3,       // world position of the closest point
    origin: fps.Vec3,
    count: int,
}

MoverResult :: struct {
    landed: bool,           // it was in the air and now stands on something
    iterations: int,        // iterations of the plane solver, all passes
}

// The capsule in the local space of the player position (feet). It shrinks when crouching.
MoverCapsule :: proc(player: ^fps.Player) -> b3.Capsule {
    top: f32 = MOVER_BOTTOM + 0.1 + 0.9 * player.head_height
    return {center1 = {0, MOVER_BOTTOM, 0}, center2 = {0, top, 0}, radius = MOVER_RADIUS}
}

// Quake like movement with Box3D collision: moves player.position by player.velocity and sets is_grounded. Call it where the flat
// floor collision of the controller would be, then step the world.
MoverUpdate :: proc(world: b3.WorldId, player: ^fps.Player, planes: ^PlaneBuffer, delta_time: f32) -> (result: MoverResult) {
    capsule: b3.Capsule = MoverCapsule(player)
    filter: b3.QueryFilter = b3.DefaultQueryFilter()
    target: fps.Vec3 = player.position + player.velocity * delta_time
    tolerance: f32 = 0.01

    for _ in 0 ..< SOLVER_PASSES {
        planes.count = 0
        planes.origin = player.position
        b3.World_CollideMover(world, player.position, capsule, filter, collectPlanes, planes)
        solved: b3.PlaneSolverResult = b3.SolvePlanes(target - player.position, raw_data(planes.planes[:]), i32(planes.count))
        result.iterations += int(solved.iterationCount)

        fraction: f32 = b3.World_CastMover(world, player.position, capsule, solved.delta, filter, nil, nil)
        delta: fps.Vec3 = fraction * solved.delta
        player.position += delta
        if linalg.dot(delta, delta) < tolerance * tolerance { break }
    }

    // Planes of the last pass tell if the player stands on something
    was_grounded: bool = player.is_grounded
    have_ground: bool = false
    for i in 0 ..< planes.count {
        if planes.planes[i].plane.normal.y > MIN_GROUND_NORMAL_Y { have_ground = true }
    }
    // Avoid snapping to ground while still going up
    player.is_grounded = have_ground && player.velocity.y <= 0.01
    result.landed = player.is_grounded && !was_grounded

    MoverPushBodies(player, planes)

    // Stop pushing into surfaces so speed cannot accumulate against a wall
    player.velocity = b3.ClipVector(player.velocity, raw_data(planes.planes[:]), i32(planes.count))
    return
}

// Dynamic bodies that touch the mover get an impulse from the speed the mover moves into them
MoverPushBodies :: proc(player: ^fps.Player, planes: ^PlaneBuffer) {
    for i in 0 ..< planes.count {
        body: b3.BodyId = b3.Shape_GetBody(planes.shapes[i])
        if b3.Body_GetType(body) != .dynamicBody { continue }

        // Plane normals point at the mover
        normal: fps.Vec3 = planes.planes[i].plane.normal
        approach: f32 = max(-linalg.dot(player.velocity, normal), 0)
        if approach > 0 {
            impulse: fps.Vec3 = -normal * (b3.Body_GetMass(body) * approach * 0.5)
            b3.Body_ApplyLinearImpulse(body, impulse, planes.points[i], true)
        }
    }
}

@(private)
collectPlanes :: proc "c" (shape_id: b3.ShapeId, results: [^]b3.PlaneResult, count: c.int, user_context: rawptr) -> bool {
    buffer: ^PlaneBuffer = cast(^PlaneBuffer)user_context
    for i in 0 ..< int(count) {
        if buffer.count >= PLANE_CAPACITY { break }
        buffer.planes[buffer.count] = {plane = results[i].plane, pushLimit = max(f32), clipVelocity = true}
        buffer.shapes[buffer.count] = shape_id
        // The point is relative to the origin passed to CollideMover
        buffer.points[buffer.count] = buffer.origin + results[i].point
        buffer.count += 1
    }
    return true
}
