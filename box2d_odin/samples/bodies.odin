// Port of box2d/samples/sample_bodies.cpp
package box2d_samples

import "core:math"
import b2 "vendor:box2d"
import b2o ".."

Vec2 :: b2.Vec2

@(init)
register_bodies :: proc "contextless" () {
    b2o.RegisterSample({category = "Bodies", name = "Body Type", create = body_type_create, step = body_type_step, controls = body_type_controls})
    b2o.RegisterSample({category = "Bodies", name = "Weeble", create = weeble_create, step = weeble_step, draw = nil, controls = weeble_controls})
    b2o.RegisterSample({category = "Bodies", name = "Sleep", create = sleep_create, draw = sleep_draw, controls = sleep_controls})
    b2o.RegisterSample({category = "Bodies", name = "Bad", create = bad_body_create, step = bad_body_step, draw = bad_body_draw})
    b2o.RegisterSample({category = "Bodies", name = "Pivot", create = pivot_create, draw = pivot_draw})
    b2o.RegisterSample({category = "Bodies", name = "Kinematic", create = kinematic_create, step = kinematic_step})
    b2o.RegisterSample({category = "Bodies", name = "Mixed Locks", create = mixed_locks_create})
    b2o.RegisterSample({category = "Bodies", name = "Set Velocity", create = set_velocity_create, step = set_velocity_step, draw = set_velocity_draw})
    b2o.RegisterSample({category = "Bodies", name = "Wake Touching", create = wake_touching_create, controls = wake_touching_controls})
}

// ------------------------------------------------------------------------------------------------
// Body Type
// ------------------------------------------------------------------------------------------------

@(private="file") body_type: b2.BodyType
@(private="file") body_type_enabled: bool
@(private="file") body_type_speed: f32
@(private="file") body_attachment, body_second_attachment, body_platform: b2.BodyId
@(private="file") body_second_payload, body_touching, body_floating: b2.BodyId

body_type_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0.8, 6.4}, 10)
    world: b2.WorldId = ctx.world

    body_type = .staticBody
    body_type_enabled = true
    body_type_speed = 3

    ground: b2.BodyId = b2o.CreateGroundSegment(world)

    // Define attachment
    body_attachment = b2o.CreateBodyAt(world, .dynamicBody, {-2, 3})
    b2o.AddPolygon(body_attachment, b2.MakeBox(0.5, 2), b2o.MakeShapeDef(1))

    // Define second attachment
    body_second_attachment = b2o.CreateBodyAt(world, body_type, {3, 3})
    b2o.AddPolygon(body_second_attachment, b2.MakeBox(0.5, 2), b2o.MakeShapeDef(1))

    // Define platform
    body_platform = b2o.CreateBodyAt(world, body_type, {-4, 5})
    b2o.AddPolygon(body_platform, b2.MakeOffsetBox(0.5, 4, {4, 0}, b2.MakeRot(0.5 * math.PI)), b2o.MakeShapeDef(2))

    revolute: b2.RevoluteJointDef = b2.DefaultRevoluteJointDef()
    revolute.maxMotorTorque = 50
    revolute.enableMotor = true
    b2o.CreateRevoluteAt(world, body_attachment, body_platform, {-2, 5}, revolute)
    b2o.CreateRevoluteAt(world, body_second_attachment, body_platform, {3, 5}, revolute)

    prismatic: b2.PrismaticJointDef = b2.DefaultPrismaticJointDef()
    prismatic.maxMotorForce = 1000
    prismatic.motorSpeed = 0
    prismatic.enableMotor = true
    prismatic.lowerTranslation = -10
    prismatic.upperTranslation = 10
    prismatic.enableLimit = true
    b2o.CreatePrismaticAt(world, ground, body_platform, {0, 5}, prismatic)

    // Payloads
    crate1: b2.BodyId = b2o.CreateBodyAt(world, .dynamicBody, {-3, 8})
    b2o.AddPolygon(crate1, b2.MakeBox(0.75, 0.75), b2o.MakeShapeDef(2))

    body_second_payload = b2o.CreateBodyAt(world, body_type, {2, 8})
    b2o.AddPolygon(body_second_payload, b2.MakeBox(0.75, 0.75), b2o.MakeShapeDef(2))

    // Separate bodies on the ground
    body_touching = b2o.CreateBodyAt(world, body_type, {8, 0.2})
    b2o.AddCapsule(body_touching, {0, 0}, {1, 0}, 0.25, b2o.MakeShapeDef(2))

    debris: b2.BodyId = b2o.CreateBodyAt(world, .staticBody, {8.5, 0.2})
    b2o.AddCapsule(debris, {0, 0}, {1, 0}, 0.5)

    // Floating body
    body_floating = b2o.CreateBodyAt(world, body_type, {-8, 12})
    b2.Body_SetGravityScale(body_floating, 0)
    b2o.AddCircle(body_floating, 0.25, {0, 0.5}, b2o.MakeShapeDef(2))
}

@(private="file")
body_type_set :: proc(type: b2.BodyType) {
    body_type = type
    b2.Body_SetType(body_platform, type)
    b2.Body_SetType(body_second_attachment, type)
    b2.Body_SetType(body_second_payload, type)
    b2.Body_SetType(body_touching, type)
    b2.Body_SetType(body_floating, type)
}

body_type_controls :: proc(ctx: ^b2o.SampleContext) {
    ui: ^b2o.Ui = ctx.ui
    if b2o.UiButton(ui, "Static", body_type == .staticBody) {
        body_type_set(.staticBody)
    }
    if b2o.UiButton(ui, "Kinematic", body_type == .kinematicBody) {
        body_type_set(.kinematicBody)
        b2.Body_SetLinearVelocity(body_platform, {-body_type_speed, 0})
        b2.Body_SetAngularVelocity(body_platform, 0)
        b2.Body_SetLinearVelocity(body_second_attachment, {})
        b2.Body_SetAngularVelocity(body_second_attachment, 0)
    }
    if b2o.UiButton(ui, "Dynamic", body_type == .dynamicBody) {
        body_type_set(.dynamicBody)
    }
    if b2o.UiCheckbox(ui, "Enable", &body_type_enabled) {
        if body_type_enabled {
            b2.Body_Enable(body_attachment)
            b2.Body_Enable(body_second_payload)
            b2.Body_Enable(body_floating)
        } else {
            b2.Body_Disable(body_attachment)
            b2.Body_Disable(body_second_payload)
            b2.Body_Disable(body_floating)
        }
    }
}

body_type_step :: proc(ctx: ^b2o.SampleContext, dt: f32) {
    // Drive the kinematic body
    if body_type == .kinematicBody {
        p: Vec2 = b2.Body_GetPosition(body_platform)
        v: Vec2 = b2.Body_GetLinearVelocity(body_platform)
        if (p.x < -14 && v.x < 0) || (p.x > 6 && v.x > 0) {
            v.x = -v.x
            b2.Body_SetLinearVelocity(body_platform, v)
        }
    }
}

// ------------------------------------------------------------------------------------------------
// Weeble
// ------------------------------------------------------------------------------------------------

@(private="file") weeble_body: b2.BodyId
@(private="file") weeble_explosion_position: Vec2
@(private="file") weeble_explosion_radius: f32
@(private="file") weeble_explosion_magnitude: f32

weeble_friction_callback :: proc "c" (friction_a: f32, id_a: u64, friction_b: f32, id_b: u64) -> f32 {
    return 0.1
}

weeble_restitution_callback :: proc "c" (restitution_a: f32, id_a: u64, restitution_b: f32, id_b: u64) -> f32 {
    return 1
}

weeble_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {2.3, 10}, 12.5)
    world: b2.WorldId = ctx.world

    // Test friction and restitution callbacks
    b2.World_SetFrictionCallback(world, weeble_friction_callback)
    b2.World_SetRestitutionCallback(world, weeble_restitution_callback)

    b2o.CreateGroundSegment(world)

    // Build weeble
    weeble_body = b2o.CreateBodyAt(world, .dynamicBody, {0, 3}, 0.25 * math.PI)
    b2o.AddCapsule(weeble_body, {0, -1}, {0, 1}, 1)

    mass: f32 = b2.Body_GetMass(weeble_body)
    inertia: f32 = b2.Body_GetRotationalInertia(weeble_body)
    offset: f32 = 1.5

    // See: https://en.wikipedia.org/wiki/Parallel_axis_theorem
    inertia += mass * offset * offset
    b2.Body_SetMassData(weeble_body, {mass, {0, -offset}, inertia})

    weeble_explosion_position = {0, 0}
    weeble_explosion_radius = 2
    weeble_explosion_magnitude = 8
}

weeble_controls :: proc(ctx: ^b2o.SampleContext) {
    ui: ^b2o.Ui = ctx.ui
    if b2o.UiButton(ui, "Teleport") {
        b2.Body_SetTransform(weeble_body, {0, 5}, b2.MakeRot(0.95 * math.PI))
    }
    if b2o.UiButton(ui, "Explode") {
        def: b2.ExplosionDef = b2.DefaultExplosionDef()
        def.position = weeble_explosion_position
        def.radius = weeble_explosion_radius
        def.falloff = 0.1
        def.impulsePerLength = weeble_explosion_magnitude
        b2.World_Explode(ctx.world, def)
    }
    b2o.UiSlider(ui, "Magnitude", &weeble_explosion_magnitude, -100, 100)
}

weeble_step :: proc(ctx: ^b2o.SampleContext, dt: f32) {
}

// ------------------------------------------------------------------------------------------------
// Sleep
// ------------------------------------------------------------------------------------------------

@(private="file") sleep_pendulum: b2.BodyId
@(private="file") sleep_static_body: b2.BodyId
@(private="file") sleep_ground_shape: b2.ShapeId
@(private="file") sleep_sensors: [2]b2.ShapeId
@(private="file") sleep_sensor_touching: [2]bool

sleep_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {3, 50}, 55)
    world: b2.WorldId = ctx.world

    ground: b2.BodyId = b2.CreateBody(world, b2.DefaultBodyDef())
    ground_def: b2.ShapeDef = b2.DefaultShapeDef()
    ground_def.enableSensorEvents = true
    sleep_ground_shape = b2o.AddSegment(ground, {-40, 0}, {40, 0}, ground_def)

    // Sleeping body with sensors
    for i in 0..<2 {
        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.type = .dynamicBody
        body_def.position = {-4, 3 + 2 * f32(i)}
        body_def.isAwake = false
        body_def.enableSleep = true
        body: b2.BodyId = b2.CreateBody(world, body_def)

        b2o.AddCapsule(body, {0, 1}, {1, 1}, 0.75)

        sensor_def: b2.ShapeDef = b2.DefaultShapeDef()
        sensor_def.isSensor = true
        sensor_def.enableSensorEvents = true
        sleep_sensors[i] = b2o.AddCapsule(body, {0, 1}, {1, 1}, 1, sensor_def)
        sleep_sensor_touching[i] = false
    }

    // Sleeping body but sleep is disabled
    {
        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.type = .dynamicBody
        body_def.position = {0, 3}
        body_def.isAwake = false
        body_def.enableSleep = false
        body: b2.BodyId = b2.CreateBody(world, body_def)
        b2o.AddCircle(body, 1, {1, 1})
    }

    // Awake body and sleep is disabled
    {
        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.type = .dynamicBody
        body_def.position = {5, 3}
        body_def.isAwake = true
        body_def.enableSleep = false
        body: b2.BodyId = b2.CreateBody(world, body_def)
        b2o.AddPolygon(body, b2.MakeOffsetBox(1, 1, {0, 1}, b2.MakeRot(0.25 * math.PI)))
    }

    // A sleeping body to test waking on collision
    {
        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.type = .dynamicBody
        body_def.position = {5, 1}
        body_def.isAwake = false
        body_def.enableSleep = true
        body: b2.BodyId = b2.CreateBody(world, body_def)
        b2o.AddPolygon(body, b2.MakeSquare(1))
    }

    // A long pendulum
    {
        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.type = .dynamicBody
        body_def.position = {0, 100}
        body_def.angularDamping = 0.5
        body_def.sleepThreshold = 0.05
        sleep_pendulum = b2.CreateBody(world, body_def)
        b2o.AddCapsule(sleep_pendulum, {0, 0}, {90, 0}, 0.25)
        b2o.CreateRevoluteAt(world, ground, sleep_pendulum, body_def.position)
    }

    // A sleeping body to test waking on contact destroyed
    {
        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.type = .dynamicBody
        body_def.position = {-10, 1}
        body_def.isAwake = false
        body_def.enableSleep = true
        body: b2.BodyId = b2.CreateBody(world, body_def)
        b2o.AddPolygon(body, b2.MakeSquare(1))
    }

    sleep_static_body = {}
}

@(private="file")
sleep_toggle_invoker :: proc(ctx: ^b2o.SampleContext) {
    if !b2.Body_IsValid(sleep_static_body) {
        sleep_static_body = b2o.CreateBodyAt(ctx.world, .staticBody, {-10.5, 3})
        shape_def: b2.ShapeDef = b2.DefaultShapeDef()
        shape_def.invokeContactCreation = true
        b2o.AddPolygon(sleep_static_body, b2.MakeOffsetBox(2, 0.1, {0, 0}, b2.MakeRot(0.25 * math.PI)), shape_def)
    } else {
        b2.DestroyBody(sleep_static_body)
        sleep_static_body = {}
    }
}

sleep_controls :: proc(ctx: ^b2o.SampleContext) {
    ui: ^b2o.Ui = ctx.ui
    b2o.UiLabel(ui, "Pendulum Tuning")

    sleep_velocity: f32 = b2.Body_GetSleepThreshold(sleep_pendulum)
    if b2o.UiSlider(ui, "sleep velocity", &sleep_velocity, 0, 1) {
        b2.Body_SetSleepThreshold(sleep_pendulum, sleep_velocity)
        b2.Body_SetAwake(sleep_pendulum, true)
    }

    angular_damping: f32 = b2.Body_GetAngularDamping(sleep_pendulum)
    if b2o.UiSlider(ui, "angular damping", &angular_damping, 0, 2) {
        b2.Body_SetAngularDamping(sleep_pendulum, angular_damping)
    }

    if b2o.UiButton(ui, "Destroy" if b2.Body_IsValid(sleep_static_body) else "Create") {
        sleep_toggle_invoker(ctx)
    }
}

sleep_draw :: proc(ctx: ^b2o.SampleContext) {
    // Detect sensors touching the ground
    events: b2.SensorEvents = b2.World_GetSensorEvents(ctx.world)
    for event in events.beginEvents[:events.beginCount] {
        if event.visitorShapeId == sleep_ground_shape {
            for i in 0..<2 {
                if event.sensorShapeId == sleep_sensors[i] { sleep_sensor_touching[i] = true }
            }
        }
    }
    for event in events.endEvents[:events.endCount] {
        if event.visitorShapeId == sleep_ground_shape {
            for i in 0..<2 {
                if event.sensorShapeId == sleep_sensors[i] { sleep_sensor_touching[i] = false }
            }
        }
    }
    for i in 0..<2 {
        b2o.ScreenText(ctx, "sensor touch %d = %v", i, sleep_sensor_touching[i])
    }
}

// ------------------------------------------------------------------------------------------------
// Bad body
// ------------------------------------------------------------------------------------------------

@(private="file") bad_body: b2.BodyId

bad_body_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {2.3, 10}, 12.5)
    world: b2.WorldId = ctx.world
    b2o.CreateGroundSegment(world)

    // Build a bad body
    body_def: b2.BodyDef = b2.DefaultBodyDef()
    body_def.type = .dynamicBody
    body_def.position = {0, 3}
    body_def.angularVelocity = 0.5
    body_def.rotation = b2.MakeRot(0.25 * math.PI)
    bad_body = b2.CreateBody(world, body_def)
    // density set to zero intentionally to create a bad body
    b2o.AddCapsule(bad_body, {0, -1}, {0, 1}, 1, b2o.MakeShapeDef(0))

    // Build a normal body
    normal: b2.BodyId = b2o.CreateBodyAt(world, .dynamicBody, {2, 3}, 0.25 * math.PI)
    b2o.AddCapsule(normal, {0, -1}, {0, 1}, 1)
}

bad_body_step :: proc(ctx: ^b2o.SampleContext, dt: f32) {
    // For science
    b2.Body_ApplyForceToCenter(bad_body, {0, 10}, true)
}

bad_body_draw :: proc(ctx: ^b2o.SampleContext) {
    b2o.ScreenText(ctx, "A bad body is a dynamic body with no mass and behaves like a kinematic body.")
    b2o.ScreenText(ctx, "Bad bodies are considered invalid and a user bug. Behavior is not guaranteed.")
}

// ------------------------------------------------------------------------------------------------
// Pivot: shows how to set the initial angular velocity to get a specific movement
// ------------------------------------------------------------------------------------------------

@(private="file") pivot_body: b2.BodyId
@(private="file") pivot_lever: f32

pivot_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0.8, 6.4}, 10)
    b2o.CreateGroundSegment(ctx.world)

    v: Vec2 = {5, 0}
    body_def: b2.BodyDef = b2.DefaultBodyDef()
    body_def.type = .dynamicBody
    body_def.position = {0, 3}
    body_def.gravityScale = 1
    body_def.linearVelocity = v
    pivot_body = b2.CreateBody(ctx.world, body_def)

    pivot_lever = 3
    r: Vec2 = {0, -pivot_lever}
    omega: f32 = b2.Cross(v, r) / b2.Dot(r, r)
    b2.Body_SetAngularVelocity(pivot_body, omega)
    b2o.AddBox(pivot_body, 0.1, pivot_lever)
}

pivot_draw :: proc(ctx: ^b2o.SampleContext) {
    v: Vec2 = b2.Body_GetLinearVelocity(pivot_body)
    omega: f32 = b2.Body_GetAngularVelocity(pivot_body)
    r: Vec2 = b2.Body_GetWorldVector(pivot_body, {0, -pivot_lever})
    vp: Vec2 = v + b2.CrossSV(omega, r)
    b2o.ScreenText(ctx, "pivot velocity = (%g, %g)", vp.x, vp.y)
}

// ------------------------------------------------------------------------------------------------
// Kinematic: shows how to drive a kinematic body to reach a target
// ------------------------------------------------------------------------------------------------

@(private="file") kinematic_body: b2.BodyId
@(private="file") kinematic_amplitude: f32
@(private="file") kinematic_time: f32

kinematic_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 0}, 4)
    kinematic_amplitude = 2
    kinematic_body = b2o.CreateBodyAt(ctx.world, .kinematicBody, {2 * kinematic_amplitude, 0})
    b2o.AddBox(kinematic_body, 0.1, 1)
    kinematic_time = 0
}

kinematic_step :: proc(ctx: ^b2o.SampleContext, dt: f32) {
    if dt > 0 {
        point: Vec2 = {2 * kinematic_amplitude * math.cos(kinematic_time), kinematic_amplitude * math.sin(2 * kinematic_time)}
        rotation: b2.Rot = b2.MakeRot(2 * kinematic_time)

        axis: Vec2 = b2.RotateVector(rotation, {0, 1})
        b2o.DrawLine(ctx, point - 0.5 * axis, point + 0.5 * axis, .Plum)
        b2o.DrawPoint(ctx, point, 10, .Plum)

        b2.Body_SetTargetTransform(kinematic_body, {point, rotation}, dt, true)
    }
    kinematic_time += dt
}

// ------------------------------------------------------------------------------------------------
// Mixed locks: motion locking can be a bit squishy
// ------------------------------------------------------------------------------------------------

mixed_locks_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 2.5}, 3.5)
    world: b2.WorldId = ctx.world
    b2o.CreateGroundSegment(world, {-40, 0}, {40, 0})

    box: b2.Polygon = b2.MakeSquare(0.5)

    // static
    static_body: b2.BodyId = b2o.CreateBodyAt(world, .staticBody, {2, 1})
    b2o.AddPolygon(static_body, box)

    spawn :: proc(world: b2.WorldId, position: Vec2, locks: b2.MotionLocks, box: b2.Polygon) {
        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.type = .dynamicBody
        body_def.position = position
        body_def.motionLocks = locks
        body: b2.BodyId = b2.CreateBody(world, body_def)
        b2o.AddPolygon(body, box)
    }
    spawn(world, {1, 1}, {}, box)
    spawn(world, {1, 3}, {}, box)
    spawn(world, {-1, 1}, {angularZ = true}, box)
    spawn(world, {-2, 2}, {linearX = true}, box)
    spawn(world, {-1, 2.5}, {linearY = true, angularZ = true}, box)
    spawn(world, {0, 1}, {linearX = true, linearY = true, angularZ = true}, box)
}

// ------------------------------------------------------------------------------------------------
// Set Velocity
// ------------------------------------------------------------------------------------------------

@(private="file") set_velocity_body: b2.BodyId

set_velocity_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 2.5}, 3.5)
    ground: b2.BodyId = b2o.CreateBodyAt(ctx.world, .staticBody, {0, -0.25})
    b2o.AddBox(ground, 20, 0.25)

    set_velocity_body = b2o.CreateBodyAt(ctx.world, .dynamicBody, {0, 0.5})
    b2o.AddPolygon(set_velocity_body, b2.MakeSquare(0.5))
}

set_velocity_step :: proc(ctx: ^b2o.SampleContext, dt: f32) {
    b2.Body_SetLinearVelocity(set_velocity_body, {0, -20})
}

set_velocity_draw :: proc(ctx: ^b2o.SampleContext) {
    position: Vec2 = b2.Body_GetPosition(set_velocity_body)
    b2o.ScreenText(ctx, "(x, y) = (%.2g, %.2g)", position.x, position.y)
}

// ------------------------------------------------------------------------------------------------
// Wake Touching
// ------------------------------------------------------------------------------------------------

@(private="file") wake_touching_ground: b2.BodyId
WAKE_TOUCHING_COUNT :: 10

wake_touching_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 4}, 8)
    wake_touching_ground = b2o.CreateGroundSegment(ctx.world)

    x: f32 = -1 * f32(WAKE_TOUCHING_COUNT - 1)
    for _ in 0..<WAKE_TOUCHING_COUNT {
        b2o.CreateDynamicPolygon(ctx.world, {x, 4}, b2.MakeBox(0.5, 0.5), 1)
        x += 2
    }
}

wake_touching_controls :: proc(ctx: ^b2o.SampleContext) {
    if b2o.UiButton(ctx.ui, "Wake Touching") {
        b2.Body_WakeTouching(wake_touching_ground)
    }
}
