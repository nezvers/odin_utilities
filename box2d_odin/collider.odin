package box2d_odin

import b2 "vendor:box2d"

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
    body_def.type = .staticBody
    body_def.fixedRotation = true
    body_def.name = name
    body:b2.BodyId = b2.CreateBody(ctx.world, body_def)
    return body
}

BodyLinearVelocity :: proc(body:b2.BodyId, velocity: Vec2){
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
    enableSensorEvents:bool = false,
    density: f32 = 1,
    userData: rawptr = nil, // rawptr(uintptr(SensorKind.coin))
)->b2.ShapeId {
    shape_def: = b2.DefaultShapeDef()
    shape_def.filter.categoryBits = categoryBits
    shape_def.filter.maskBits = maskBits
    shape_def.density = density
    shape_def.enableSensorEvents = enableSensorEvents
    shape_def.userData = userData
    
    box:b2.Polygon = b2.MakeBox(size.x * 0.5 - 1, size.y * 0.5 - 1)
    shape:b2.ShapeId = b2.CreatePolygonShape(body, shape_def, box)
    return shape
}

CreateShapeCircle :: proc(
    body: b2.BodyId,
    radius: f32, 
    categoryBits: u64,       // entity kind
    maskBits: u64 = BITMASK_ALL,       // collides against
    enableSensorEvents: bool = false,
    density: f32 = 1,
    userData: rawptr = nil, // rawptr(uintptr(SensorKind.coin))
)->b2.ShapeId {
    shape_def: = b2.DefaultShapeDef()
    shape_def.filter.categoryBits = categoryBits
    shape_def.filter.maskBits = maskBits
    shape_def.density = density
    shape_def.enableSensorEvents = enableSensorEvents
    shape_def.userData = userData
    
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
    enableSensorEvents: bool = false,
    density: f32 = 1,
    userData: rawptr = nil, // rawptr(uintptr(SensorKind.coin))
)->b2.ShapeId {
    shape_def: = b2.DefaultShapeDef()
    shape_def.filter.categoryBits = categoryBits
    shape_def.filter.maskBits = maskBits
    shape_def.density = density
    shape_def.enableSensorEvents = enableSensorEvents
    shape_def.userData = userData
    
    circle:b2.Circle
    circle.radius = radius
    shape:b2.ShapeId = b2.CreateCircleShape(body, shape_def, circle)
    return shape
}


