// Port of the Geometric Mover sample of box2d/samples/sample_character.cpp (Dynamic Mover and Ghost Culling are not ported yet).
// The mover itself is box2d_odin/geometric_mover.odin, this file is the level, the input and the drawing.
package box2d_samples

import "core:math"
import b2 "vendor:box2d"
import b2o ".."

@(init)
register_character :: proc "contextless" () {
    b2o.RegisterSample({category = "Character", name = "Geometric Mover", create = mover_create, step = mover_step, draw = mover_draw, controls = mover_controls})
}

@(private="file") STATIC_BIT :: u64(0x0001)
@(private="file") MOVER_BIT :: u64(0x0002)
@(private="file") DYNAMIC_BIT :: u64(0x0004)
@(private="file") ALL_BITS :: u64(0xFFFFFFFF)

@(private="file") ELEVATOR_BASE :: Vec2{112, 10}
@(private="file") ELEVATOR_AMPLITUDE :: f32(4)

@(private="file") mover: b2o.GeometricMover
@(private="file") elevator_id: b2.BodyId
@(private="file") friendly_shape: b2o.MoverShapeUserData
@(private="file") elevator_shape: b2o.MoverShapeUserData
@(private="file") mover_time: f32
@(private="file") jump_released: bool
@(private="file") lock_camera: bool

@(private="file")
create_chain_ground :: proc(world: b2.WorldId, position: Vec2, path: string, offset: Vec2) -> b2.BodyId {
    body_def: b2.BodyDef = b2.DefaultBodyDef()
    body_def.position = position
    ground: b2.BodyId = b2.CreateBody(world, body_def)

    points: [64]Vec2
    count: int = b2o.ParsePath(path, offset, points[:], 0.2, false)

    chain_def: b2.ChainDef = b2.DefaultChainDef()
    chain_def.points = raw_data(points[:])
    chain_def.pointCount = i32(count)
    chain_def.isLoop = true
    _ = b2.CreateChain(ground, chain_def)
    return ground
}

mover_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {20, 9}, 10)

    mover_def: b2o.GeometricMoverDef = b2o.GeometricMoverDefaultDef()
    mover_def.position = {0, 8}
    mover_def.capsule = {center1 = {0, -0.5}, center2 = {0, 0.5}, radius = 0.3}
    mover_def.filter = {categoryBits = MOVER_BIT, maskBits = STATIC_BIT | DYNAMIC_BIT | MOVER_BIT}
    b2o.GeometricMoverCreate(&mover, ctx.world, mover_def)

    ground1: b2.BodyId = create_chain_ground(ctx.world, {0, 0},
        "M -34.395834,201.08333 H 293.68751 v -47.625 h -2.64584 l -10.58333,7.9375 -13.22916,7.9375 -13.24648,5.29167 " +
        "-31.73269,7.9375 -21.16667,2.64583 -23.8125,10.58333 -15.875,2e-5 v -3.96875 l -17.19792,2e-5 v 2.64582 l " +
        "-17.19791,0 v -1.32292 h -3.96875 v -1.32292 h -3.96875 v -1.32292 h -3.96875 v -1.32291 h -3.96875 v -1.32292 " +
        "h -3.96875 v -1.32292 h -3.96875 v -1.32291 l -3.968754,0 v -1.32292 h -3.96875 v -1.32292 h -3.968751 v " +
        "-1.32291 h -3.96875 v -1.32292 h -3.96875 v -1.32292 h -3.96875 v -1.32291 h -3.96875 v -1.32292 l -3.96875,0 v " +
        "-1.32292 h -3.968751 v -1.32291 h -3.96875 l -2e-6,-1.32294 H 52.916669 L 39.6875,177.27083 h -5.291667 l " +
        "-7.937499,5.29167 H 15.875001 l -47.625002,-50.27083 v -26.45834 h -2.645834 l 10e-7,95.25",
        {-50, -200})

    ground2: b2.BodyId = create_chain_ground(ctx.world, {98, 0},
        "M 2.6458333,201.08333 H 399.52085 v -23.8125 h -23.8125 l 21.16667,18.52084 -232.83335,-1e-5 -0.0575,2.64584 h " +
        "-5.29166 v -2.64583 l -7.86855,-1e-5 -0.0114,-2.64583 h -2.64583 l -2.64583,2.64584 h -7.9375 l " +
        "-2.64584,2.64583 -2.58891,-2.64584 -10.64031,2e-5 v -2.64583 l -7.9375,0 v -2.64584 l -7.9375,0 v -2.64583 l " +
        "-7.9375,0 v -2.64583 l -7.9375,0 v -2.64583 l -7.937501,-1e-5 v -2.64584 l -7.9375,1e-5 v -2.64583 l " +
        "-7.937501,-2e-5 V 174.625 l -7.937501,1e-5 v -2.64584 l -5.291669,0 -7.9375,-2.64584 -7.9375,-2.64583 " +
        "-5.291667,-5.29167 H 21.166667 L 13.229167,158.75 5.2916668,153.45833 H 2.6458334 l -10e-8,47.625",
        {0, -200})

    // A static capsule the size of the mover that is soft: it only nudges the mover and does not clip its velocity
    {
        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.position = {32, 4.5}
        friendly_shape = {max_push = 0.025, clip_velocity = false}
        shape_def: b2.ShapeDef = b2.DefaultShapeDef()
        shape_def.filter = {categoryBits = u64(MOVER_BIT), maskBits = ALL_BITS}
        shape_def.userData = &friendly_shape
        body: b2.BodyId = b2.CreateBody(ctx.world, body_def)
        _ = b2.CreateCapsuleShape(body, shape_def, mover.capsule)
    }

    // Rope bridge between the two grounds
    {
        box: b2.Polygon = b2.MakeBox(0.55, 0.125)
        joint_def: b2.RevoluteJointDef = b2.DefaultRevoluteJointDef()
        joint_def.maxMotorTorque = 10
        joint_def.enableMotor = true
        joint_def.hertz = 3
        joint_def.dampingRatio = 0.8
        joint_def.enableSpring = true

        x_base: f32 = 48.7
        y_base: f32 = 9.2
        count :: 50
        previous: b2.BodyId = ground1
        for i in 0 ..< count {
            body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {x_base + 0.5 + f32(i), y_base})
            b2.Body_SetAngularDamping(body, 0.2)
            b2o.AddPolygon(body, box)
            b2o.CreateRevoluteAt(ctx.world, previous, body, {x_base + f32(i), y_base}, joint_def)
            previous = body
        }
        b2o.CreateRevoluteAt(ctx.world, previous, ground2, {x_base + f32(count), y_base}, joint_def)
    }

    // Small bouncy balls
    for i in 0 ..< 5 {
        body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {7, 7 + 0.5 * f32(i)})
        shape_def: b2.ShapeDef = b2.DefaultShapeDef()
        shape_def.filter = {categoryBits = DYNAMIC_BIT, maskBits = ALL_BITS}
        shape_def.material.restitution = 0.7
        shape_def.material.rollingResistance = 0.2
        b2o.AddCircle(body, 0.25, def = shape_def)
    }

    // Elevator: kinematic, may only push the mover a little so it does not squeeze it through the floor
    {
        elevator_id = b2o.CreateBodyAt(ctx.world, .kinematicBody, {ELEVATOR_BASE.x, ELEVATOR_BASE.y - ELEVATOR_AMPLITUDE})
        elevator_shape = {max_push = 0.1, clip_velocity = true}
        shape_def: b2.ShapeDef = b2.DefaultShapeDef()
        shape_def.filter = {categoryBits = DYNAMIC_BIT, maskBits = ALL_BITS}
        shape_def.userData = &elevator_shape
        b2o.AddBox(elevator_id, 2, 0.1, shape_def)
    }

    // A column of boxes to push around
    {
        a: f32 = 0.25
        shape_def: b2.ShapeDef = b2.DefaultShapeDef()
        shape_def.filter = {categoryBits = DYNAMIC_BIT, maskBits = ALL_BITS}
        for i in 0 ..< 10 {
            body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {140, (2 * f32(i) + 1) * a + 1})
            b2o.AddPolygon(body, b2.MakeSquare(a), shape_def)
        }
    }

    // A motorised paddle on the second ground
    {
        position: Vec2 = {160, 5}
        body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, position)
        b2o.AddPolygon(body, b2.MakeBox(0.1, 4), b2.DefaultShapeDef())

        joint_def: b2.RevoluteJointDef = b2.DefaultRevoluteJointDef()
        joint_def.enableMotor = true
        joint_def.motorSpeed = 1
        joint_def.maxMotorTorque = 500
        b2o.CreateRevoluteAt(ctx.world, ground2, body, position + Vec2{0, 4}, joint_def)
    }

    jump_released = true
    lock_camera = true
    mover_time = 0
}

mover_step :: proc(ctx: ^b2o.SampleContext, dt: f32) {
    if dt <= 0 { return }

    point: Vec2 = {ELEVATOR_BASE.x, ELEVATOR_AMPLITUDE * math.cos(mover_time + math.PI) + ELEVATOR_BASE.y}
    b2.Body_SetTargetTransform(elevator_id, {p = point, q = {1, 0}}, dt, true)
    mover_time += dt

    throttle: f32
    if ctx.input.key_down[.A] { throttle -= 1 }
    if ctx.input.key_down[.D] { throttle += 1 }

    if ctx.input.key_down[.SPACE] {
        if jump_released && b2o.GeometricMoverJump(&mover) {
            jump_released = false
        }
    } else {
        jump_released = true
    }

    b2o.GeometricMoverUpdate(&mover, dt, throttle)
}

mover_draw :: proc(ctx: ^b2o.SampleContext) {
    b2o.ScreenText(ctx, "left/right/jump = A/D/Space")

    // The ground probe
    probe_color: b2.HexColor = .Plum if mover.pogo_hit else .Gray
    probe_end: Vec2 = mover.pogo_origin + mover.pogo_fraction * mover.pogo_translation
    b2o.DrawLine(ctx, mover.pogo_origin, probe_end, .Gray)
    b2o.DrawPoint(ctx, probe_end, 10, probe_color)

    b2o.DrawTransform(ctx, {p = mover.position, q = {1, 0}})

    capsule: b2.Capsule = mover.capsule
    for i in 0 ..< mover.plane_count {
        plane: b2.Plane = mover.planes[i].plane
        p1: Vec2 = mover.position + (plane.offset - capsule.radius) * plane.normal
        b2o.DrawPoint(ctx, p1, 5, .Yellow)
        b2o.DrawLine(ctx, p1, p1 + 0.1 * plane.normal, .Yellow)
    }

    color: b2.HexColor = .Orange if mover.on_ground else .Aquamarine
    ctx.debug_draw.DrawSolidCapsuleFcn(mover.position + capsule.center1, mover.position + capsule.center2, capsule.radius, color, ctx.debug_draw.userContext)
    b2o.DrawLine(ctx, mover.position, mover.position + mover.velocity, .Purple)

    b2o.ScreenText(ctx, "position %.2f %.2f", mover.position.x, mover.position.y)
    b2o.ScreenText(ctx, "velocity %.2f %.2f", mover.velocity.x, mover.velocity.y)
    b2o.ScreenText(ctx, "iterations %d", mover.total_iterations)

    if lock_camera {
        ctx.camera.center.x = mover.position.x
    }
}

mover_controls :: proc(ctx: ^b2o.SampleContext) {
    b2o.UiSlider(ctx.ui, "Jump Speed", &mover.jump_speed, 0, 40)
    b2o.UiSlider(ctx.ui, "Min Speed", &mover.min_speed, 0, 1)
    b2o.UiSlider(ctx.ui, "Max Speed", &mover.max_speed, 0, 20)
    b2o.UiSlider(ctx.ui, "Stop Speed", &mover.stop_speed, 0, 10)
    b2o.UiSlider(ctx.ui, "Accelerate", &mover.accelerate, 0, 100)
    b2o.UiSlider(ctx.ui, "Friction", &mover.friction, 0, 10)
    b2o.UiSlider(ctx.ui, "Gravity", &mover.gravity, 0, 100)
    b2o.UiSlider(ctx.ui, "Air Steer", &mover.air_steer, 0, 1)
    b2o.UiSlider(ctx.ui, "Pogo Hertz", &mover.pogo_hertz, 0, 30)
    b2o.UiSlider(ctx.ui, "Pogo Damping", &mover.pogo_damping_ratio, 0, 4)
    b2o.UiSpace(ctx.ui)
    b2o.UiCheckbox(ctx.ui, "Push Bodies", &mover.push_bodies)
    b2o.UiCheckbox(ctx.ui, "Lock Camera", &lock_camera)
}
