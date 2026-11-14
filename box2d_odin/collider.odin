package box2d_odin

import b2 "vendor:box2d"
import "core:sync"
import "core:testing"

BITMASK_ALL :: ~u64(0)

CreateBody :: proc(
    ctx: ^WorldContext, 
    position: Vec2, 
    size: Vec2,      // 
    type: b2.BodyType = .staticBody,
    fixed_rotation:bool = true,
    name:cstring = "",
)->b2.BodyId {
    pos:b2.Vec2 = pos_to_b2(position, size)

    body_def: = b2.DefaultBodyDef()
    body_def.position = pos
    body_def.type = type
    body_def.motionLocks = {angularZ = fixed_rotation}
    body_def.name = name
    body:b2.BodyId = b2.CreateBody(ctx.world, body_def)
    return body
}

BodyLinearVelocity :: proc(body:b2.BodyId, velocity: Vec2) {
    b2.Body_SetLinearVelocity(body, {velocity.x, -velocity.y})
}

DestroyBody :: proc(body: b2.BodyId) {
    b2.DestroyBody(body)
}

DestroyShape :: proc(shape: b2.ShapeId) {
    b2.DestroyShape(shape, false)
}

CreateShapeBox :: proc(
    body: b2.BodyId,
    size: Vec2, 
    categoryBits: u64,       // entity kind
    maskBits: u64 = BITMASK_ALL,       // collides against
    density: f32 = 1,
    userData: rawptr = nil, // rawptr(uintptr(SensorKind.coin))
    isSensor: bool = false,
    enableSensorEvents:bool = false,
    enablePreSolveEvents:bool = false,
    enableContactEvents: bool = false,
    enableHitEvents: bool = false,
)->b2.ShapeId {
    shape_def: = b2.DefaultShapeDef()
    shape_def.filter.categoryBits = categoryBits
    shape_def.filter.maskBits = maskBits
    shape_def.density = density
    shape_def.userData = userData
    shape_def.isSensor = isSensor
    shape_def.enableSensorEvents = enableSensorEvents
    shape_def.enablePreSolveEvents = enablePreSolveEvents
    shape_def.enableContactEvents = enableContactEvents
    shape_def.enableHitEvents = enableHitEvents
    
    box:b2.Polygon = b2.MakeBox(size.x * 0.5 - 1, size.y * 0.5 - 1)
    shape:b2.ShapeId = b2.CreatePolygonShape(body, shape_def, box)
    return shape
}

CreateShapeCircle :: proc(
    body: b2.BodyId,
    radius: f32, 
    categoryBits: u64,       // entity kind
    maskBits: u64 = BITMASK_ALL,       // collides against
    density: f32 = 1,
    userData: rawptr = nil, // rawptr(uintptr(SensorKind.coin))
    isSensor: bool = false,
    enableSensorEvents: bool = false,
    enablePreSolveEvents:bool = false,
    enableContactEvents: bool = false,
    enableHitEvents: bool = false,
)->b2.ShapeId {
    shape_def: = b2.DefaultShapeDef()
    shape_def.filter.categoryBits = categoryBits
    shape_def.filter.maskBits = maskBits
    shape_def.density = density
    shape_def.userData = userData
    shape_def.isSensor = isSensor
    shape_def.enableSensorEvents = enableSensorEvents
    shape_def.enablePreSolveEvents = enablePreSolveEvents
    shape_def.enableContactEvents = enableContactEvents
    shape_def.enableHitEvents = enableHitEvents
    
    circle:b2.Circle
    circle.radius = radius
    shape:b2.ShapeId = b2.CreateCircleShape(body, shape_def, circle)
    return shape
}

CreateShapeCapsule :: proc(
    body:b2.BodyId,
    radius: f32, 
    categoryBits: u64,       // entity kind
    maskBits: u64 = BITMASK_ALL,       // collides against
    density: f32 = 1,
    userData: rawptr = nil, // rawptr(uintptr(SensorKind.coin))
    isSensor: bool = false,
    enableSensorEvents: bool = false,
    enablePreSolveEvents:bool = false,
    enableContactEvents: bool = false,
    enableHitEvents: bool = false,
)->b2.ShapeId {
    shape_def: = b2.DefaultShapeDef()
    shape_def.filter.categoryBits = categoryBits
    shape_def.filter.maskBits = maskBits
    shape_def.density = density
    shape_def.userData = userData
    shape_def.isSensor = isSensor
    shape_def.enableSensorEvents = enableSensorEvents
    shape_def.enablePreSolveEvents = enablePreSolveEvents
    shape_def.enableContactEvents = enableContactEvents
    shape_def.enableHitEvents = enableHitEvents
    
    circle:b2.Circle
    circle.radius = radius
    shape:b2.ShapeId = b2.CreateCircleShape(body, shape_def, circle)
    return shape
}

// --- Tests ---

@(test)
test_collider_body_creation :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    ctx: WorldContext
    WorldInit(&ctx, 1, {0, 0})
    defer WorldFinit(&ctx)

    body: b2.BodyId = CreateBody(&ctx, {10, 20}, {8, 6}, .dynamicBody)
    testing.expect_value(t, b2.Body_GetPosition(body), pos_to_b2({10, 20}, {8, 6}))
    testing.expect_value(t, b2.Body_GetType(body), b2.BodyType.dynamicBody)
    testing.expect(t, b2.Body_GetMotionLocks(body).angularZ, "rotation is locked by default")
    free_turning: b2.BodyId = CreateBody(&ctx, {0, 0}, {8, 6}, .dynamicBody, false)
    testing.expect(t, !b2.Body_GetMotionLocks(free_turning).angularZ)

    BodyLinearVelocity(body, {3, 4})                                                       // screen y points down, physics y up
    testing.expect_value(t, b2.Body_GetLinearVelocity(body), b2.Vec2{3, -4})
}

@(test)
test_collider_shapes_carry_filters_and_flags :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    ctx: WorldContext
    WorldInit(&ctx, 1, {0, 0})
    defer WorldFinit(&ctx)
    body: b2.BodyId = CreateBody(&ctx, {0, 0}, {10, 10}, .dynamicBody)

    box: b2.ShapeId = CreateShapeBox(body, {10, 10}, 0b01, 0b10, userData = rawptr(uintptr(7)))
    filter: b2.Filter = b2.Shape_GetFilter(box)
    testing.expect_value(t, filter.categoryBits, u64(0b01))
    testing.expect_value(t, filter.maskBits, u64(0b10))
    testing.expect_value(t, b2.Shape_GetUserData(box), rawptr(uintptr(7)))
    testing.expect_value(t, b2.Shape_GetType(box), b2.ShapeType.polygonShape)
    testing.expect(t, !b2.Shape_IsSensor(box))
    testing.expect_value(t, b2.Shape_GetFilter(CreateShapeCircle(body, 2, 0b100)).maskBits, BITMASK_ALL)   // collides with everything by default

    sensor: b2.ShapeId = CreateShapeCircle(body, 2, 0b100, isSensor = true, enableSensorEvents = true)
    testing.expect(t, b2.Shape_IsSensor(sensor))
    testing.expect(t, b2.Shape_AreSensorEventsEnabled(sensor))
    testing.expect_value(t, b2.Shape_GetType(sensor), b2.ShapeType.circleShape)

    shapes: i32 = b2.Body_GetShapeCount(body)
    DestroyShape(sensor)
    testing.expect_value(t, b2.Body_GetShapeCount(body), shapes - 1)
    DestroyBody(body)
    testing.expect(t, !b2.Body_IsValid(body))
}
