package box2d_odin

import b2 "vendor:box2d"
import "core:sync"
import "core:testing"

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

// --- Tests ---

@(private="file")
make_test_world :: proc() -> b2.WorldId {
    world_def: b2.WorldDef = b2.DefaultWorldDef()
    world_def.gravity = {0, -10}
    return b2.CreateWorld(world_def)
}

@(test)
test_shape_helpers_create_the_right_shapes :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    world: b2.WorldId = make_test_world()
    defer b2.DestroyWorld(world)
    body: b2.BodyId = CreateBodyAt(world, .dynamicBody, {1, 2})

    testing.expect_value(t, b2.Shape_GetType(AddBox(body, 1, 1)), b2.ShapeType.polygonShape)
    testing.expect_value(t, b2.Shape_GetType(AddCircle(body, 0.5)), b2.ShapeType.circleShape)
    testing.expect_value(t, b2.Shape_GetType(AddCapsule(body, {0, 0}, {0, 1}, 0.25)), b2.ShapeType.capsuleShape)
    testing.expect_value(t, b2.Shape_GetType(AddSegment(body, {0, 0}, {1, 0})), b2.ShapeType.segmentShape)
    testing.expect_value(t, b2.Shape_GetType(AddPolygon(body, b2.MakeSquare(1))), b2.ShapeType.polygonShape)
    testing.expect_value(t, b2.Body_GetShapeCount(body), i32(5))
    testing.expect_value(t, b2.Body_GetPosition(body), b2.Vec2{1, 2})

    circle: b2.ShapeId = AddCircle(body, 0.5, {3, 0})
    testing.expect_value(t, b2.Shape_GetCircle(circle).center, b2.Vec2{3, 0})
}

@(test)
test_shape_def_helpers :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    def: b2.ShapeDef = MakeShapeDef(2, 0.3, 0.8)
    testing.expect_value(t, def.density, f32(2))
    testing.expect_value(t, def.material.friction, f32(0.3))
    testing.expect_value(t, def.material.restitution, f32(0.8))
    testing.expect_value(t, ShapeDefOrDefault(nil).density, b2.DefaultShapeDef().density)
    testing.expect_value(t, ShapeDefOrDefault(def).density, f32(2))

    world: b2.WorldId = make_test_world()
    defer b2.DestroyWorld(world)
    body: b2.BodyId = CreateBodyAt(world, .dynamicBody, {0, 0})
    shape: b2.ShapeId = AddBox(body, 1, 1, def)                                            // the def given to the helper is used
    testing.expect_value(t, b2.Shape_GetFriction(shape), f32(0.3))
    testing.expect_value(t, b2.Shape_GetRestitution(shape), f32(0.8))
}

@(test)
test_body_helpers :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    world: b2.WorldId = make_test_world()
    defer b2.DestroyWorld(world)

    ground: b2.BodyId = CreateGroundSegment(world)
    testing.expect_value(t, b2.Body_GetType(ground), b2.BodyType.staticBody)
    testing.expect_value(t, b2.Body_GetShapeCount(ground), i32(1))

    box: b2.BodyId = CreateStaticBox(world, {5, 5}, {1, 2}, 0)
    testing.expect_value(t, b2.Body_GetType(box), b2.BodyType.staticBody)
    testing.expect_value(t, b2.Body_GetPosition(box), b2.Vec2{5, 5})

    tilted: b2.BodyId = CreateBodyAt(world, .dynamicBody, {0, 0}, 0.5)
    testing.expect(t, abs(b2.Rot_GetAngle(b2.Body_GetRotation(tilted)) - 0.5) < 5e-3, "box2d approximates sine and cosine")

    polygon: b2.BodyId = CreateDynamicPolygon(world, {1, 1}, b2.MakeBox(0.5, 0.5), 4)
    testing.expect_value(t, b2.Body_GetType(polygon), b2.BodyType.dynamicBody)
    testing.expect(t, abs(b2.Body_GetMass(polygon) - 4) < 1e-3, "a unit box of density 4 weighs 4")
}

@(test)
test_joint_helpers_pin_at_a_world_point :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    world: b2.WorldId = make_test_world()
    defer b2.DestroyWorld(world)
    anchor_body: b2.BodyId = CreateBodyAt(world, .staticBody, {0, 10})
    swinging: b2.BodyId = CreateBodyAt(world, .dynamicBody, {2, 10})
    AddCircle(swinging, 0.25)

    joint: b2.JointId = CreateRevoluteAt(world, anchor_body, swinging, {0, 10})
    testing.expect(t, b2.Joint_IsValid(joint))
    testing.expect_value(t, b2.Joint_GetBodyA(joint), anchor_body)
    testing.expect_value(t, b2.Joint_GetBodyB(joint), swinging)

    for _ in 0 ..< 120 { b2.World_Step(world, 1.0 / 60, 4) }                               // a pendulum keeps its distance to the pivot
    position: b2.Vec2 = b2.Body_GetPosition(swinging)
    testing.expect(t, abs(b2.Length(position - b2.Vec2{0, 10}) - 2) < 0.05, "still two metres from the pivot")

    slider: b2.BodyId = CreateBodyAt(world, .dynamicBody, {10, 10})
    AddBox(slider, 0.5, 0.5)
    rail: b2.BodyId = CreateBodyAt(world, .staticBody, {10, 10})
    prismatic: b2.JointId = CreatePrismaticAt(world, rail, slider, {10, 10})
    testing.expect(t, b2.Joint_IsValid(prismatic))
}
