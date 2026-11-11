package box2d_odin

import b2 "vendor:box2d"

// Helpers for patterns that repeat in almost every Box2D sample.
// Shape creation wrappers don't require handling the result, a nil shape def means b2.DefaultShapeDef().

ShapeDefOrDefault :: proc(def: Maybe(b2.ShapeDef)) -> b2.ShapeDef {
    return def.? or_else b2.DefaultShapeDef()
}

AddSegment :: proc(body: b2.BodyId, p1: Vec2, p2: Vec2, def: Maybe(b2.ShapeDef) = nil) -> b2.ShapeId {
    return b2.CreateSegmentShape(body, ShapeDefOrDefault(def), b2.Segment{p1, p2})
}

AddPolygon :: proc(body: b2.BodyId, polygon: b2.Polygon, def: Maybe(b2.ShapeDef) = nil) -> b2.ShapeId {
    return b2.CreatePolygonShape(body, ShapeDefOrDefault(def), polygon)
}

AddBox :: proc(body: b2.BodyId, half_width: f32, half_height: f32, def: Maybe(b2.ShapeDef) = nil) -> b2.ShapeId {
    return b2.CreatePolygonShape(body, ShapeDefOrDefault(def), b2.MakeBox(half_width, half_height))
}

AddCircle :: proc(body: b2.BodyId, radius: f32, center: Vec2 = {}, def: Maybe(b2.ShapeDef) = nil) -> b2.ShapeId {
    return b2.CreateCircleShape(body, ShapeDefOrDefault(def), b2.Circle{center, radius})
}

AddCapsule :: proc(body: b2.BodyId, p1: Vec2, p2: Vec2, radius: f32, def: Maybe(b2.ShapeDef) = nil) -> b2.ShapeId {
    return b2.CreateCapsuleShape(body, ShapeDefOrDefault(def), b2.Capsule{p1, p2, radius})
}

// Shape def with density, friction and restitution, the values samples change the most
MakeShapeDef :: proc(density: f32 = 1, friction: f32 = 0.6, restitution: f32 = 0) -> b2.ShapeDef {
    def: b2.ShapeDef = b2.DefaultShapeDef()
    def.density = density
    def.material.friction = friction
    def.material.restitution = restitution
    return def
}

// Static body with one segment shape, usual ground
CreateGroundSegment :: proc(world: b2.WorldId, p1: Vec2 = {-20, 0}, p2: Vec2 = {20, 0}, def: Maybe(b2.ShapeDef) = nil) -> b2.BodyId {
    body: b2.BodyId = b2.CreateBody(world, b2.DefaultBodyDef())
    AddSegment(body, p1, p2, def)
    return body
}

// Static body with one box, center position and half size
CreateStaticBox :: proc(world: b2.WorldId, center: Vec2, half: Vec2, angle: f32 = 0) -> b2.BodyId {
    body: b2.BodyId = CreateBodyAt(world, .staticBody, center, angle)
    AddBox(body, half.x, half.y)
    return body
}

// Body of a type at a position. Add shapes with AddBox, AddCircle ...
CreateBodyAt :: proc(world: b2.WorldId, type: b2.BodyType, position: Vec2, angle: f32 = 0) -> b2.BodyId {
    body_def: b2.BodyDef = b2.DefaultBodyDef()
    body_def.type = type
    body_def.position = position
    body_def.rotation = b2.MakeRot(angle)
    return b2.CreateBody(world, body_def)
}

// Dynamic body with a polygon, returns the body
CreateDynamicPolygon :: proc(world: b2.WorldId, position: Vec2, polygon: b2.Polygon, density: f32 = 1, angle: f32 = 0) -> b2.BodyId {
    body: b2.BodyId = CreateBodyAt(world, .dynamicBody, position, angle)
    AddPolygon(body, polygon, MakeShapeDef(density))
    return body
}

// Revolute joint with the pivot given in world coordinates (the C++ samples repeat this setup)
CreateRevoluteAt :: proc(world: b2.WorldId, body_a: b2.BodyId, body_b: b2.BodyId, pivot: Vec2, def: Maybe(b2.RevoluteJointDef) = nil) -> b2.JointId {
    joint_def: b2.RevoluteJointDef = def.? or_else b2.DefaultRevoluteJointDef()
    joint_def.base.bodyIdA = body_a
    joint_def.base.bodyIdB = body_b
    joint_def.base.localFrameA.p = b2.Body_GetLocalPoint(body_a, pivot)
    joint_def.base.localFrameB.p = b2.Body_GetLocalPoint(body_b, pivot)
    return b2.CreateRevoluteJoint(world, joint_def)
}

// Prismatic joint with the anchor in world coordinates, axis comes from the joint frames
CreatePrismaticAt :: proc(world: b2.WorldId, body_a: b2.BodyId, body_b: b2.BodyId, anchor: Vec2, def: Maybe(b2.PrismaticJointDef) = nil) -> b2.JointId {
    joint_def: b2.PrismaticJointDef = def.? or_else b2.DefaultPrismaticJointDef()
    joint_def.base.bodyIdA = body_a
    joint_def.base.bodyIdB = body_b
    joint_def.base.localFrameA.p = b2.Body_GetLocalPoint(body_a, anchor)
    joint_def.base.localFrameB.p = b2.Body_GetLocalPoint(body_b, anchor)
    return b2.CreatePrismaticJoint(world, joint_def)
}
