package box2d_odin

// Port of box2d/samples/geometric_mover.h and geometric_mover.cpp
//
// Geometric character mover. The capsule is moved by casting and by solving collision planes, so the game keeps full
// control of the motion. A pogo spring holds the capsule above the ground so it can move up steps.
// Fixed capacity, no allocations.

import "core:sync"
import "core:testing"
import b2 "vendor:box2d"

MOVER_PLANE_CAPACITY :: 8

GeometricMoverDef :: struct {
    position: Vec2,
    capsule: b2.Capsule,        // relative to the mover position
    filter: b2.QueryFilter,
    jump_speed: f32,
    max_speed: f32,
    min_speed: f32,
    stop_speed: f32,
    accelerate: f32,
    air_steer: f32,
    friction: f32,
    gravity: f32,
    pogo_rest_length: f32,
    pogo_hertz: f32,
    pogo_damping_ratio: f32,
}

// Optional shape user data read by the mover when it gathers collision planes.
// Shapes without user data are treated as rigid and fully clipping.
MoverShapeUserData :: struct {
    // Distance limit on the push this surface may apply to the mover. max(f32) is rigid.
    // Use a small value for surfaces that must not shove the mover, such as an elevator
    // that would otherwise push it through the floor.
    max_push: f32,

    // False keeps the velocity along this surface, which is what soft collision needs.
    clip_velocity: bool,
}

// Extra data kept alongside each collision plane so the mover can push rigid bodies.
PlaneExtra :: struct {
    point: Vec2,
    shape: b2.ShapeId,
}

GeometricMover :: struct {
    jump_speed: f32,
    max_speed: f32,
    min_speed: f32,
    stop_speed: f32,
    accelerate: f32,

    // Fraction of the ground acceleration available in the air.
    air_steer: f32,

    // Ground friction in units of 1/time.
    friction: f32,

    // The mover is not simulated so it needs its own gravity.
    gravity: f32,

    pogo_rest_length: f32,
    pogo_hertz: f32,
    pogo_damping_ratio: f32,

    // Downward force applied to whatever the pogo stick is resting on.
    pogo_ground_force: f32,

    // Surfaces steeper than this are not ground.
    min_ground_normal_y: f32,

    // Push touched rigid bodies out of the way by solving a normal constraint against each collision plane.
    // Without this the mover slides along a crate instead of shoving it.
    push_bodies: bool,

    // The capsule is relative to the mover position.
    capsule: b2.Capsule,
    filter: b2.QueryFilter,
    world: b2.WorldId,

    // The center of the capsule.
    position: Vec2,
    velocity: Vec2,
    pogo_velocity: f32,
    on_ground: bool,

    // Planes from the last solve, kept for debug drawing.
    planes: [MOVER_PLANE_CAPACITY]b2.CollisionPlane,
    plane_extras: [MOVER_PLANE_CAPACITY]PlaneExtra,
    plane_count: int,
    total_iterations: int,

    // The last ground probe, kept for debug drawing.
    pogo_origin: Vec2,
    pogo_translation: Vec2,
    pogo_fraction: f32,
    pogo_hit: bool,
}

// Same values as the C++ GeometricMoverDef member initializers
GeometricMoverDefaultDef :: proc() -> GeometricMoverDef {
    return {
        capsule = {center1 = {0, -0.5}, center2 = {0, 0.5}, radius = 0.3},
        filter = b2.DefaultQueryFilter(),
        jump_speed = 10,
        max_speed = 6,
        min_speed = 0.1,
        stop_speed = 3,
        accelerate = 20,
        air_steer = 0.2,
        friction = 8,
        gravity = 30,
        pogo_rest_length = 0.9,
        pogo_hertz = 5,
        pogo_damping_ratio = 0.8,
    }
}

// Place the mover. The capsule and tuning may be changed at any time afterwards.
GeometricMoverCreate :: proc(mover: ^GeometricMover, world: b2.WorldId, def: GeometricMoverDef) {
    mover^ = {
        capsule = def.capsule,
        filter = def.filter,
        jump_speed = def.jump_speed,
        max_speed = def.max_speed,
        min_speed = def.min_speed,
        stop_speed = def.stop_speed,
        accelerate = def.accelerate,
        air_steer = def.air_steer,
        friction = def.friction,
        gravity = def.gravity,
        pogo_rest_length = def.pogo_rest_length,
        pogo_hertz = def.pogo_hertz,
        pogo_damping_ratio = def.pogo_damping_ratio,
        pogo_ground_force = 50,
        min_ground_normal_y = 0.7,
        push_bodies = true,
        world = world,
        position = def.position,
        pogo_fraction = 1,
    }
}

// Jump if grounded. Returns false when airborne.
GeometricMoverJump :: proc(mover: ^GeometricMover) -> bool {
    if !mover.on_ground {
        return false
    }
    mover.velocity.y = mover.jump_speed
    mover.on_ground = false
    return true
}

@(private="file")
MoverCastResult :: struct {
    point: Vec2,
    normal: Vec2,
    body: b2.BodyId,
    fraction: f32,
    hit: bool,
}

@(private="file")
mover_cast_callback :: proc "c" (shape: b2.ShapeId, point: b2.Pos, normal: Vec2, fraction: f32, user_context: rawptr) -> f32 {
    result: ^MoverCastResult = cast(^MoverCastResult)user_context
    result^ = {point = point, normal = normal, body = b2.Shape_GetBody(shape), fraction = fraction, hit = true}
    return fraction
}

@(private="file")
mover_plane_callback :: proc "c" (shape: b2.ShapeId, plane_result: ^b2.PlaneResult, user_context: rawptr) -> bool {
    mover: ^GeometricMover = cast(^GeometricMover)user_context
    max_push: f32 = max(f32)
    clip_velocity: bool = true
    user_data: ^MoverShapeUserData = cast(^MoverShapeUserData)b2.Shape_GetUserData(shape)
    if user_data != nil {
        max_push = user_data.max_push
        clip_velocity = user_data.clip_velocity
    }

    if mover.plane_count < MOVER_PLANE_CAPACITY {
        mover.planes[mover.plane_count] = {plane = plane_result.plane, pushLimit = max_push, push = 0, clipVelocity = clip_velocity}
        // The plane point is relative to the origin passed to the collide call
        mover.plane_extras[mover.plane_count] = {point = mover.position + plane_result.point, shape = shape}
        mover.plane_count += 1
    }
    return true
}

// Solve a normal constraint between the mover and each touched rigid body. This is the same velocity constraint the solver
// uses for a contact, except the mover is treated as having infinite mass, so all of the impulse lands on the body.
@(private="file")
mover_push_bodies :: proc(mover: ^GeometricMover) {
    for i in 0 ..< mover.plane_count {
        body: b2.BodyId = b2.Shape_GetBody(mover.plane_extras[i].shape)
        if b2.Body_GetType(body) != .dynamicBody {
            continue
        }

        // Plane normals point at the mover
        point: Vec2 = mover.plane_extras[i].point
        normal: Vec2 = -mover.planes[i].plane.normal

        inv_mass_a: f32 = 0
        mass_b: f32 = b2.Body_GetMass(body)
        inv_mass_b: f32 = 1 / mass_b if mass_b > 0 else 0
        inertia_b: f32 = b2.Body_GetRotationalInertia(body)
        inv_i_b: f32 = 1 / inertia_b if inertia_b > 0 else 0

        center_b: Vec2 = b2.Body_GetWorldCenter(body)
        r_b: Vec2 = point - center_b

        rn_b: f32 = b2.Cross(r_b, normal)
        k_normal: f32 = inv_mass_a + inv_mass_b + inv_i_b * rn_b * rn_b
        normal_mass: f32 = 1 / k_normal if k_normal > 0 else 0

        v_b: Vec2 = b2.Body_GetLinearVelocity(body)
        omega_b: f32 = b2.Body_GetAngularVelocity(body)
        vr_b: Vec2 = v_b + b2.CrossSV(omega_b, r_b)
        vn: f32 = b2.Dot(vr_b - mover.velocity, normal)

        // Push only, a separating body is left alone
        impulse: f32 = max(-normal_mass * vn, 0)

        p: Vec2 = impulse * normal
        mover.velocity -= inv_mass_a * p

        b2.Body_ApplyLinearImpulse(body, p, point, true)
    }
}

// Advance the mover. Throttle is the horizontal input on [-1, 1].
// Movement follows the Quake ground and air model: https://github.com/id-Software/Quake/blob/master/QW/client/pmove.c#L390
GeometricMoverUpdate :: proc(mover: ^GeometricMover, time_step: f32, throttle: f32) {
    // Friction
    speed: f32 = b2.Length(mover.velocity)
    if speed < mover.min_speed {
        mover.velocity = {}
    } else if mover.on_ground {
        // Linear damping above stop_speed and fixed reduction below stop_speed
        control: f32 = mover.stop_speed if speed < mover.stop_speed else speed

        // friction has units of 1/time
        drop: f32 = control * mover.friction * time_step
        new_speed: f32 = max(0, speed - drop)
        mover.velocity *= new_speed / speed
    }

    desired_velocity: Vec2 = {mover.max_speed * throttle, 0}
    desired_speed, desired_direction := b2.GetLengthAndNormalize(desired_velocity)
    if desired_speed > mover.max_speed {
        desired_speed = mover.max_speed
    }

    // Accelerate
    current_speed: f32 = b2.Dot(mover.velocity, desired_direction)
    add_speed: f32 = desired_speed - current_speed
    if add_speed > 0 {
        steer: f32 = 1 if mover.on_ground else mover.air_steer
        accel_speed: f32 = steer * mover.accelerate * mover.max_speed * time_step
        if accel_speed > add_speed {
            accel_speed = add_speed
        }
        mover.velocity += accel_speed * desired_direction
    }

    // The probe reaches past the rest length so the spring can be stretched
    ray_length: f32 = 2 * mover.pogo_rest_length if mover.on_ground else mover.pogo_rest_length
    translation: Vec2 = {0, -ray_length}
    origin: Vec2 = mover.position + mover.capsule.center1

    cast_result: MoverCastResult
    _ = b2.World_CastRay(mover.world, origin, translation, mover.filter, mover_cast_callback, &cast_result)

    mover.pogo_origin = origin
    mover.pogo_translation = translation
    mover.pogo_fraction = cast_result.fraction if cast_result.hit else 1
    mover.pogo_hit = cast_result.hit

    // Avoid snapping to ground if still going up
    have_ground: bool = cast_result.hit && cast_result.normal.y > mover.min_ground_normal_y

    if !mover.on_ground {
        mover.on_ground = have_ground && mover.velocity.y <= 0.01
    } else {
        mover.on_ground = have_ground
    }

    if !mover.on_ground {
        mover.velocity.y -= mover.gravity * time_step
        mover.pogo_velocity = 0
    } else {
        mover.velocity.y = 0

        pogo_current_length: f32 = cast_result.fraction * ray_length
        offset: f32 = pogo_current_length - mover.pogo_rest_length
        mover.pogo_velocity = b2.SpringDamper(mover.pogo_hertz, mover.pogo_damping_ratio, offset, mover.pogo_velocity, time_step)

        b2.Body_ApplyForce(cast_result.body, {0, -mover.pogo_ground_force}, cast_result.point, true)
    }

    target: Vec2 = mover.position + time_step * mover.velocity + time_step * mover.pogo_velocity * Vec2{0, 1}

    mover.total_iterations = 0
    tolerance: f32 = 0.01

    // Don't cast against other movers.
    cast_filter: b2.QueryFilter = {
        categoryBits = mover.filter.categoryBits,
        maskBits = mover.filter.maskBits & ~mover.filter.categoryBits,
    }

    for _ in 0 ..< 5 {
        mover.plane_count = 0

        b2.World_CollideMover(mover.world, mover.position, mover.capsule, mover.filter, mover_plane_callback, mover)
        result: b2.PlaneSolverResult = b2.SolvePlanes(target - mover.position, mover.planes[:mover.plane_count])

        mover.total_iterations += int(result.iterationCount)

        fraction: f32 = b2.World_CastMover(mover.world, mover.position, mover.capsule, result.delta, cast_filter)

        delta: Vec2 = fraction * result.delta
        mover.position += delta

        if b2.LengthSquared(delta) < tolerance * tolerance {
            break
        }
    }

    if mover.push_bodies {
        mover_push_bodies(mover)
    }

    // Stop pushing into surfaces so speed can't accumulate against a wall
    mover.velocity = b2.ClipVector(mover.velocity, raw_data(mover.planes[:]), i32(mover.plane_count))
}

// --- Tests ---

@(private="file")
make_mover_world :: proc() -> b2.WorldId {
    world_def: b2.WorldDef = b2.DefaultWorldDef()
    world_def.gravity = {0, -10}
    return b2.CreateWorld(world_def)
}

@(private="file")
settle :: proc(mover: ^GeometricMover, steps: int, throttle: f32 = 0) {
    for _ in 0 ..< steps {
        GeometricMoverUpdate(mover, 1.0 / 60, throttle)
        b2.World_Step(mover.world, 1.0 / 60, 4)
    }
}

@(test)
test_mover_falls_and_stands_on_the_pogo :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    world: b2.WorldId = make_mover_world()
    defer b2.DestroyWorld(world)
    CreateGroundSegment(world, {-50, 0}, {50, 0})

    mover: GeometricMover
    def: GeometricMoverDef = GeometricMoverDefaultDef()
    def.position = {0, 4}
    GeometricMoverCreate(&mover, world, def)
    testing.expect(t, !mover.on_ground)

    settle(&mover, 15)
    testing.expect(t, !mover.on_ground, "still in the air after a quarter second")
    testing.expect(t, mover.velocity.y < 0, "gravity pulls it down")

    settle(&mover, 240)
    testing.expect(t, mover.on_ground, "landed")
    testing.expect(t, abs(mover.velocity.y) < 0.01, "no vertical speed on the ground")
    // the pogo holds the capsule bottom (centre - 0.5) one rest length above the ground
    testing.expect(t, abs(mover.position.y - (mover.pogo_rest_length + 0.5)) < 0.1, "held at the rest length above the floor")
    testing.expect(t, mover.pogo_hit)
}

@(test)
test_mover_runs_jumps_and_stops :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    world: b2.WorldId = make_mover_world()
    defer b2.DestroyWorld(world)
    CreateGroundSegment(world, {-50, 0}, {50, 0})

    mover: GeometricMover
    def: GeometricMoverDef = GeometricMoverDefaultDef()
    def.position = {0, 1.4}
    GeometricMoverCreate(&mover, world, def)
    settle(&mover, 60)
    testing.expect(t, mover.on_ground)

    start_x: f32 = mover.position.x
    settle(&mover, 60, 1)
    testing.expect(t, abs(mover.velocity.x - mover.max_speed) < 0.1, "reaches the maximum speed and no more")
    testing.expect(t, mover.position.x > start_x + 3, "ran to the right")

    settle(&mover, 90, 0)
    testing.expect(t, abs(mover.velocity.x) < 0.2, "ground friction brings it to a stop")

    testing.expect(t, GeometricMoverJump(&mover), "can jump from the ground")
    testing.expect_value(t, mover.velocity.y, mover.jump_speed)
    testing.expect(t, !mover.on_ground)
    testing.expect(t, !GeometricMoverJump(&mover), "no second jump in the air")

    peak: f32 = mover.position.y
    for _ in 0 ..< 60 {
        settle(&mover, 1)
        peak = max(peak, mover.position.y)
    }
    testing.expect(t, peak > 1.4 + 0.5 * 10 * 10 / 30 - 0.4, "the jump rises about v^2 / 2g")
}

@(test)
test_mover_is_stopped_by_a_wall_and_pushes_a_crate :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    world: b2.WorldId = make_mover_world()
    defer b2.DestroyWorld(world)
    CreateGroundSegment(world, {-50, 0}, {50, 0})
    CreateStaticBox(world, {8, 3}, {0.5, 3})                                               // a wall at x = 8

    crate: b2.BodyId = CreateBodyAt(world, .dynamicBody, {3, 0.5})
    AddBox(crate, 0.5, 0.5, MakeShapeDef(0.2))                                             // a light crate in the way

    mover: GeometricMover
    def: GeometricMoverDef = GeometricMoverDefaultDef()
    def.position = {0, 1.4}
    GeometricMoverCreate(&mover, world, def)
    settle(&mover, 30)

    settle(&mover, 300, 1)
    testing.expect(t, b2.Body_GetPosition(crate).x > 3.5, "the crate was shoved along")
    testing.expect(t, mover.position.x < 8 - 0.5 - mover.capsule.radius + 0.05, "the wall stops the mover")
    testing.expect(t, mover.velocity.x < 1, "speed does not build up against the wall")

    // the same run without pushing leaves the crate where physics alone puts it
    other_world: b2.WorldId = make_mover_world()
    defer b2.DestroyWorld(other_world)
    CreateGroundSegment(other_world, {-50, 0}, {50, 0})
    other_crate: b2.BodyId = CreateBodyAt(other_world, .dynamicBody, {3, 0.5})
    AddBox(other_crate, 0.5, 0.5, MakeShapeDef(0.2))
    other: GeometricMover
    GeometricMoverCreate(&other, other_world, def)
    other.position = {0, 1.4}
    other.push_bodies = false
    settle(&other, 30)
    settle(&other, 120, 1)
    testing.expect(t, other.position.x > 2, "it still moves")
    pushed_x: f32 = b2.Body_GetPosition(crate).x
    testing.expect(t, pushed_x > b2.Body_GetPosition(other_crate).x, "pushing moves the crate further than not pushing")
}

@(test)
test_mover_soft_surface_user_data :: proc(t: ^testing.T) {
    // A surface with a small max_push cannot shove the mover out of its way
    sync.guard(&test_box2d_lock)
    world: b2.WorldId = make_mover_world()
    defer b2.DestroyWorld(world)
    CreateGroundSegment(world, {-50, 0}, {50, 0})

    soft: MoverShapeUserData = {max_push = 0.01, clip_velocity = false}
    body: b2.BodyId = CreateBodyAt(world, .staticBody, {0.1, 1.4})
    shape_def: b2.ShapeDef = b2.DefaultShapeDef()
    shape_def.userData = &soft
    mover: GeometricMover
    def: GeometricMoverDef = GeometricMoverDefaultDef()
    def.position = {0, 1.4}
    GeometricMoverCreate(&mover, world, def)
    soft_shape: b2.ShapeId = AddCapsule(body, mover.capsule.center1, mover.capsule.center2, mover.capsule.radius, shape_def)   // overlaps the mover, slightly to the side

    GeometricMoverUpdate(&mover, 1.0 / 60, 0)
    testing.expect(t, mover.plane_count > 0, "the overlapping shape produced planes")
    for i in 0 ..< mover.plane_count {
        if mover.plane_extras[i].shape == soft_shape {
            testing.expect_value(t, mover.planes[i].pushLimit, f32(0.01))
            testing.expect(t, !mover.planes[i].clipVelocity)
        }
    }
}
