package box2d_odin

// Box2D bodies, shapes and joints as plain data that can be saved and loaded (a chunk of a serial file, see ../serial), and created
// in a world. A level editor works on a PhysicsDesc: it edits the arrays, saves them, and the game creates the bodies from the
// loaded description. Characters, props and level geometry are all the same: a body, shapes on it, `user_id` to link it back to
// the entity (a prefab instance of a scene level) it belongs to.
//
// Descriptions are values (no pointers, no ids of a world), so they survive saving, hot reload and being created in several worlds.
// Reading a file validates everything (finite numbers, ranges, indices, counts) before a world sees it, so a bad file fails to
// load instead of corrupting a simulation. Loading fills the slices the user provides, nothing allocates.

import "core:math"
import "core:testing"
import "core:sync"
import b2 "vendor:box2d"
import "../serial"

PHYSICS_CHUNK_VERSION :: u16(1)
PHYSICS_MAX_POLYGON :: b2.MAX_POLYGON_VERTICES
PHYSICS_MAX_CHAIN :: 64
// What a file may claim, so bad data cannot ask for an absurd amount
PHYSICS_MAX_BODIES :: 1 << 14
PHYSICS_MAX_SHAPES :: 1 << 15
PHYSICS_MAX_JOINTS :: 1 << 13
// The smallest size of one item in the file: the reader checks that the data left can hold the claimed count
PHYSICS_BODY_BYTES :: 44
PHYSICS_SHAPE_MIN_BYTES :: 83       // without any of its points
PHYSICS_JOINT_BYTES :: 39

PHYSICS_TAG :: #force_inline proc "contextless" () -> serial.Tag { return serial.MakeTag('P', 'H', 'Y', 'S') }

PhysicsBodyDesc :: struct {
    type: b2.BodyType,
    position: Vec2,
    angle: f32,                 // radians
    linear_velocity: Vec2,
    angular_velocity: f32,
    linear_damping: f32,
    angular_damping: f32,
    gravity_scale: f32,
    fixed_rotation: bool,       // a character that must not tip over
    bullet: bool,
    awake: bool,
    user_id: u32,               // the entity this body belongs to, 0 - none
}

PhysicsShapeKind :: enum u8 {
    CIRCLE,
    BOX,
    CAPSULE,
    POLYGON,
    SEGMENT,
    CHAIN,
}

PhysicsShapeDesc :: struct {
    kind: PhysicsShapeKind,
    body: u32,                  // index in PhysicsDesc.bodies
    a: Vec2,                    // circle and box: center. capsule and segment: first point
    b: Vec2,                    // capsule and segment: second point
    half: Vec2,                 // box: half width and half height
    angle: f32,                 // box: rotation
    radius: f32,                // circle, capsule, and the rounding of a polygon
    point_count: u8,            // polygon (3 to 8) and chain (2 to 64)
    points: [PHYSICS_MAX_CHAIN]Vec2,
    is_loop: bool,              // chain
    density: f32,
    friction: f32,
    restitution: f32,
    rolling_resistance: f32,
    category: u64,
    mask: u64,
    group: i32,
    sensor: bool,
    sensor_events: bool,
    contact_events: bool,
    hit_events: bool,
    user_id: u32,
}

// A revolute joint (a hinge). Bodies by index, the anchor in world coordinates like CreateRevoluteAt
PhysicsJointDesc :: struct {
    body_a: u32,
    body_b: u32,
    anchor: Vec2,
    enable_limit: bool,
    lower_angle: f32,
    upper_angle: f32,
    enable_motor: bool,
    motor_speed: f32,
    max_motor_torque: f32,
    collide_connected: bool,
    user_id: u32,
}

// The slices belong to the user. `*_count` is how much of each is used
PhysicsDesc :: struct {
    bodies: []PhysicsBodyDesc,
    body_count: int,
    shapes: []PhysicsShapeDesc,
    shape_count: int,
    joints: []PhysicsJointDesc,
    joint_count: int,
}

// --- Building descriptions (for the editor and for code) ---

PhysicsAddBody :: proc(desc: ^PhysicsDesc, type: b2.BodyType, position: Vec2, angle: f32 = 0, user_id: u32 = 0) -> (index: u32, ok: bool) {
    if desc.body_count >= len(desc.bodies) { return }
    index = u32(desc.body_count)
    desc.bodies[desc.body_count] = {type = type, position = position, angle = angle, gravity_scale = 1, awake = true, user_id = user_id}
    desc.body_count += 1
    return index, true
}

// A shape with the defaults of Box2D (density 1, friction 0.6, collides with everything), to adjust afterwards
@(private)
PhysicsNewShape :: proc(desc: ^PhysicsDesc, kind: PhysicsShapeKind, body: u32) -> ^PhysicsShapeDesc {
    if desc.shape_count >= len(desc.shapes) { return nil }
    defaults: b2.ShapeDef = b2.DefaultShapeDef()
    shape: ^PhysicsShapeDesc = &desc.shapes[desc.shape_count]
    shape^ = {
        kind = kind,
        body = body,
        density = defaults.density,
        friction = defaults.material.friction,
        restitution = defaults.material.restitution,
        rolling_resistance = defaults.material.rollingResistance,
        category = defaults.filter.categoryBits,
        mask = defaults.filter.maskBits,
        group = defaults.filter.groupIndex,
    }
    desc.shape_count += 1
    return shape
}

PhysicsAddCircle :: proc(desc: ^PhysicsDesc, body: u32, radius: f32, center: Vec2 = {}) -> ^PhysicsShapeDesc {
    shape: ^PhysicsShapeDesc = PhysicsNewShape(desc, .CIRCLE, body)
    if shape != nil { shape.radius = radius; shape.a = center }
    return shape
}

PhysicsAddBox :: proc(desc: ^PhysicsDesc, body: u32, half_width: f32, half_height: f32, center: Vec2 = {}, angle: f32 = 0) -> ^PhysicsShapeDesc {
    shape: ^PhysicsShapeDesc = PhysicsNewShape(desc, .BOX, body)
    if shape != nil { shape.half = {half_width, half_height}; shape.a = center; shape.angle = angle }
    return shape
}

PhysicsAddCapsule :: proc(desc: ^PhysicsDesc, body: u32, p1: Vec2, p2: Vec2, radius: f32) -> ^PhysicsShapeDesc {
    shape: ^PhysicsShapeDesc = PhysicsNewShape(desc, .CAPSULE, body)
    if shape != nil { shape.a = p1; shape.b = p2; shape.radius = radius }
    return shape
}

PhysicsAddSegment :: proc(desc: ^PhysicsDesc, body: u32, p1: Vec2, p2: Vec2) -> ^PhysicsShapeDesc {
    shape: ^PhysicsShapeDesc = PhysicsNewShape(desc, .SEGMENT, body)
    if shape != nil { shape.a = p1; shape.b = p2 }
    return shape
}

// A convex polygon of 3 to 8 points (the hull of them is made when the shape is created)
PhysicsAddPolygon :: proc(desc: ^PhysicsDesc, body: u32, points: []Vec2, radius: f32 = 0) -> ^PhysicsShapeDesc {
    if len(points) < 3 || len(points) > PHYSICS_MAX_POLYGON { return nil }
    shape: ^PhysicsShapeDesc = PhysicsNewShape(desc, .POLYGON, body)
    if shape != nil {
        shape.radius = radius
        shape.point_count = u8(len(points))
        copy(shape.points[:], points)
    }
    return shape
}

// A chain is solid on one side only: walking along the points, the solid side is on the right. For ground that is under the points,
// list them from right to left. A loop is solid on the outside when it winds clockwise.
PhysicsAddChain :: proc(desc: ^PhysicsDesc, body: u32, points: []Vec2, is_loop: bool = false) -> ^PhysicsShapeDesc {
    if len(points) < 2 || len(points) > PHYSICS_MAX_CHAIN { return nil }
    shape: ^PhysicsShapeDesc = PhysicsNewShape(desc, .CHAIN, body)
    if shape != nil {
        shape.point_count = u8(len(points))
        shape.is_loop = is_loop
        copy(shape.points[:], points)
    }
    return shape
}

PhysicsAddRevolute :: proc(desc: ^PhysicsDesc, body_a: u32, body_b: u32, anchor: Vec2) -> ^PhysicsJointDesc {
    if desc.joint_count >= len(desc.joints) { return nil }
    joint: ^PhysicsJointDesc = &desc.joints[desc.joint_count]
    joint^ = {body_a = body_a, body_b = body_b, anchor = anchor}
    desc.joint_count += 1
    return joint
}

// --- Saving ---

@(private)
WriteVec2 :: proc(writer: ^serial.Writer, value: Vec2) {
    serial.WriteF32(writer, value.x)
    serial.WriteF32(writer, value.y)
}

@(private)
ReadVec2 :: proc(reader: ^serial.Reader) -> Vec2 {
    return {serial.ReadF32(reader), serial.ReadF32(reader)}
}

// One chunk with everything of the description
PhysicsDescWrite :: proc(writer: ^serial.Writer, desc: PhysicsDesc) {
    serial.ChunkBegin(writer, PHYSICS_TAG(), PHYSICS_CHUNK_VERSION)

    serial.WriteU32(writer, u32(desc.body_count))
    for i in 0 ..< desc.body_count {
        body: PhysicsBodyDesc = desc.bodies[i]
        serial.WriteU8(writer, u8(body.type))
        WriteVec2(writer, body.position)
        serial.WriteF32(writer, body.angle)
        WriteVec2(writer, body.linear_velocity)
        serial.WriteF32(writer, body.angular_velocity)
        serial.WriteF32(writer, body.linear_damping)
        serial.WriteF32(writer, body.angular_damping)
        serial.WriteF32(writer, body.gravity_scale)
        serial.WriteBool(writer, body.fixed_rotation)
        serial.WriteBool(writer, body.bullet)
        serial.WriteBool(writer, body.awake)
        serial.WriteU32(writer, body.user_id)
    }

    serial.WriteU32(writer, u32(desc.shape_count))
    for i in 0 ..< desc.shape_count {
        shape: ^PhysicsShapeDesc = &desc.shapes[i]
        serial.WriteU8(writer, u8(shape.kind))
        serial.WriteU32(writer, shape.body)
        WriteVec2(writer, shape.a)
        WriteVec2(writer, shape.b)
        WriteVec2(writer, shape.half)
        serial.WriteF32(writer, shape.angle)
        serial.WriteF32(writer, shape.radius)
        serial.WriteU8(writer, shape.point_count)
        for p in 0 ..< int(shape.point_count) { WriteVec2(writer, shape.points[p]) }      // only the points in use
        serial.WriteBool(writer, shape.is_loop)
        serial.WriteF32(writer, shape.density)
        serial.WriteF32(writer, shape.friction)
        serial.WriteF32(writer, shape.restitution)
        serial.WriteF32(writer, shape.rolling_resistance)
        serial.WriteU64(writer, shape.category)
        serial.WriteU64(writer, shape.mask)
        serial.WriteI32(writer, shape.group)
        serial.WriteBool(writer, shape.sensor)
        serial.WriteBool(writer, shape.sensor_events)
        serial.WriteBool(writer, shape.contact_events)
        serial.WriteBool(writer, shape.hit_events)
        serial.WriteU32(writer, shape.user_id)
    }

    serial.WriteU32(writer, u32(desc.joint_count))
    for i in 0 ..< desc.joint_count {
        joint: PhysicsJointDesc = desc.joints[i]
        serial.WriteU32(writer, joint.body_a)
        serial.WriteU32(writer, joint.body_b)
        WriteVec2(writer, joint.anchor)
        serial.WriteBool(writer, joint.enable_limit)
        serial.WriteF32(writer, joint.lower_angle)
        serial.WriteF32(writer, joint.upper_angle)
        serial.WriteBool(writer, joint.enable_motor)
        serial.WriteF32(writer, joint.motor_speed)
        serial.WriteF32(writer, joint.max_motor_torque)
        serial.WriteBool(writer, joint.collide_connected)
        serial.WriteU32(writer, joint.user_id)
    }
    serial.ChunkEnd(writer)
}

// --- Loading ---

@(private)
Finite :: proc(value: f32) -> bool {
    return !math.is_nan(value) && !math.is_inf(value)
}

@(private)
FiniteVec2 :: proc(value: Vec2) -> bool {
    return Finite(value.x) && Finite(value.y)
}

// Read the description into the slices of `desc` (set them up first: the length of each is the capacity). Returns false for a
// file without the chunk or with anything that a simulation should not get. `desc` holds what was read before the problem.
PhysicsDescRead :: proc(file: serial.Reader, desc: ^PhysicsDesc) -> bool {
    version, payload, found := serial.ChunkFind(file, PHYSICS_TAG())
    if !found || version > PHYSICS_CHUNK_VERSION { return false }
    desc.body_count = 0
    desc.shape_count = 0
    desc.joint_count = 0

    body_count: int = serial.ReadCount(&payload, min(PHYSICS_MAX_BODIES, len(desc.bodies)), PHYSICS_BODY_BYTES)
    for _ in 0 ..< body_count {
        body: PhysicsBodyDesc
        type: u8 = serial.ReadU8(&payload)
        if type > u8(b2.BodyType.dynamicBody) { return false }
        body.type = b2.BodyType(type)
        body.position = ReadVec2(&payload)
        body.angle = serial.ReadF32(&payload)
        body.linear_velocity = ReadVec2(&payload)
        body.angular_velocity = serial.ReadF32(&payload)
        body.linear_damping = serial.ReadF32(&payload)
        body.angular_damping = serial.ReadF32(&payload)
        body.gravity_scale = serial.ReadF32(&payload)
        body.fixed_rotation = serial.ReadBool(&payload)
        body.bullet = serial.ReadBool(&payload)
        body.awake = serial.ReadBool(&payload)
        body.user_id = serial.ReadU32(&payload)
        if !serial.ReaderOk(&payload) { return false }
        finite: bool = FiniteVec2(body.position) && Finite(body.angle) && FiniteVec2(body.linear_velocity) && Finite(body.angular_velocity)
        finite &&= Finite(body.linear_damping) && Finite(body.angular_damping) && Finite(body.gravity_scale)
        if !finite || body.linear_damping < 0 || body.angular_damping < 0 { return false }
        desc.bodies[desc.body_count] = body
        desc.body_count += 1
    }

    shape_count: int = serial.ReadCount(&payload, min(PHYSICS_MAX_SHAPES, len(desc.shapes)), PHYSICS_SHAPE_MIN_BYTES)
    for _ in 0 ..< shape_count {
        shape: PhysicsShapeDesc
        kind: u8 = serial.ReadU8(&payload)
        if kind > u8(PhysicsShapeKind.CHAIN) { return false }
        shape.kind = PhysicsShapeKind(kind)
        shape.body = serial.ReadU32(&payload)
        shape.a = ReadVec2(&payload)
        shape.b = ReadVec2(&payload)
        shape.half = ReadVec2(&payload)
        shape.angle = serial.ReadF32(&payload)
        shape.radius = serial.ReadF32(&payload)
        shape.point_count = serial.ReadU8(&payload)
        if int(shape.point_count) > PHYSICS_MAX_CHAIN { return false }
        for p in 0 ..< int(shape.point_count) { shape.points[p] = ReadVec2(&payload) }
        shape.is_loop = serial.ReadBool(&payload)
        shape.density = serial.ReadF32(&payload)
        shape.friction = serial.ReadF32(&payload)
        shape.restitution = serial.ReadF32(&payload)
        shape.rolling_resistance = serial.ReadF32(&payload)
        shape.category = serial.ReadU64(&payload)
        shape.mask = serial.ReadU64(&payload)
        shape.group = serial.ReadI32(&payload)
        shape.sensor = serial.ReadBool(&payload)
        shape.sensor_events = serial.ReadBool(&payload)
        shape.contact_events = serial.ReadBool(&payload)
        shape.hit_events = serial.ReadBool(&payload)
        shape.user_id = serial.ReadU32(&payload)
        if !serial.ReaderOk(&payload) { return false }

        if int(shape.body) >= desc.body_count { return false }
        finite: bool = FiniteVec2(shape.a) && FiniteVec2(shape.b) && FiniteVec2(shape.half) && Finite(shape.angle) && Finite(shape.radius)
        finite &&= Finite(shape.density) && Finite(shape.friction) && Finite(shape.restitution) && Finite(shape.rolling_resistance)
        for p in 0 ..< int(shape.point_count) { finite &&= FiniteVec2(shape.points[p]) }
        if !finite || shape.radius < 0 || shape.density < 0 || shape.friction < 0 || shape.half.x < 0 || shape.half.y < 0 { return false }
        switch shape.kind {
        case .POLYGON:
            if shape.point_count < 3 || int(shape.point_count) > PHYSICS_MAX_POLYGON { return false }
        case .CHAIN:
            if shape.point_count < 2 || (shape.is_loop && shape.point_count < 3) { return false }
        case .CIRCLE, .BOX, .CAPSULE, .SEGMENT:
        }
        desc.shapes[desc.shape_count] = shape
        desc.shape_count += 1
    }

    joint_count: int = serial.ReadCount(&payload, min(PHYSICS_MAX_JOINTS, len(desc.joints)), PHYSICS_JOINT_BYTES)
    for _ in 0 ..< joint_count {
        joint: PhysicsJointDesc
        joint.body_a = serial.ReadU32(&payload)
        joint.body_b = serial.ReadU32(&payload)
        joint.anchor = ReadVec2(&payload)
        joint.enable_limit = serial.ReadBool(&payload)
        joint.lower_angle = serial.ReadF32(&payload)
        joint.upper_angle = serial.ReadF32(&payload)
        joint.enable_motor = serial.ReadBool(&payload)
        joint.motor_speed = serial.ReadF32(&payload)
        joint.max_motor_torque = serial.ReadF32(&payload)
        joint.collide_connected = serial.ReadBool(&payload)
        joint.user_id = serial.ReadU32(&payload)
        if !serial.ReaderOk(&payload) { return false }
        finite: bool = FiniteVec2(joint.anchor) && Finite(joint.lower_angle) && Finite(joint.upper_angle)
        finite &&= Finite(joint.motor_speed) && Finite(joint.max_motor_torque)
        if !finite || int(joint.body_a) >= desc.body_count || int(joint.body_b) >= desc.body_count || joint.body_a == joint.body_b { return false }
        if joint.enable_limit && joint.lower_angle > joint.upper_angle { return false }
        desc.joints[desc.joint_count] = joint
        desc.joint_count += 1
    }
    return serial.ReaderOk(&payload)
}

// --- Creating ---

// Create the bodies, shapes and joints in `world`. `bodies_out[i]` is the body of `desc.bodies[i]` (it has to hold body_count).
// Body and shape user data is the user_id as a pointer value. A shape that Box2D cannot make (a polygon whose points are in a line)
// is skipped and counted, the rest is created.
PhysicsCreate :: proc(world: b2.WorldId, desc: PhysicsDesc, bodies_out: []b2.BodyId) -> (skipped_shapes: int, ok: bool) {
    if len(bodies_out) < desc.body_count { return }

    for i in 0 ..< desc.body_count {
        body: PhysicsBodyDesc = desc.bodies[i]
        def: b2.BodyDef = b2.DefaultBodyDef()
        def.type = body.type
        def.position = body.position
        def.rotation = b2.MakeRot(body.angle)
        def.linearVelocity = body.linear_velocity
        def.angularVelocity = body.angular_velocity
        def.linearDamping = body.linear_damping
        def.angularDamping = body.angular_damping
        def.gravityScale = body.gravity_scale
        def.motionLocks = {angularZ = body.fixed_rotation}
        def.isBullet = body.bullet
        def.isAwake = body.awake
        bodies_out[i] = b2.CreateBody(world, def)
        b2.Body_SetUserData(bodies_out[i], rawptr(uintptr(body.user_id)))
    }

    for i in 0 ..< desc.shape_count {
        shape: ^PhysicsShapeDesc = &desc.shapes[i]
        body: b2.BodyId = bodies_out[shape.body]
        def: b2.ShapeDef = b2.DefaultShapeDef()
        def.density = shape.density
        def.material.friction = shape.friction
        def.material.restitution = shape.restitution
        def.material.rollingResistance = shape.rolling_resistance
        def.filter = {categoryBits = shape.category, maskBits = shape.mask, groupIndex = shape.group}
        def.isSensor = shape.sensor
        def.enableSensorEvents = shape.sensor_events
        def.enableContactEvents = shape.contact_events
        def.enableHitEvents = shape.hit_events
        def.userData = rawptr(uintptr(shape.user_id))

        switch shape.kind {
        case .CIRCLE:
            _ = b2.CreateCircleShape(body, def, b2.Circle{center = shape.a, radius = shape.radius})
        case .BOX:
            _ = b2.CreatePolygonShape(body, def, b2.MakeOffsetBox(shape.half.x, shape.half.y, shape.a, b2.MakeRot(shape.angle)))
        case .CAPSULE:
            _ = b2.CreateCapsuleShape(body, def, b2.Capsule{center1 = shape.a, center2 = shape.b, radius = shape.radius})
        case .POLYGON:
            hull: b2.Hull = b2.ComputeHull(shape.points[:shape.point_count])
            if hull.count == 0 {
                skipped_shapes += 1
            } else {
                _ = b2.CreatePolygonShape(body, def, b2.MakePolygon(hull, shape.radius))
            }
        case .SEGMENT:
            _ = b2.CreateSegmentShape(body, def, b2.Segment{point1 = shape.a, point2 = shape.b})
        case .CHAIN:
            material: b2.SurfaceMaterial = def.material
            chain: b2.ChainDef = b2.DefaultChainDef()
            chain.points = raw_data(shape.points[:])
            chain.pointCount = i32(shape.point_count)
            chain.isLoop = shape.is_loop
            if !shape.is_loop {
                // an open chain needs its neighbours, they stop a body from catching on the ends: continue each end in its own direction
                last: int = int(shape.point_count) - 1
                chain.ghost1 = shape.points[0] + (shape.points[0] - shape.points[1])
                chain.ghost2 = shape.points[last] + (shape.points[last] - shape.points[last - 1])
            }
            chain.filter = def.filter
            chain.materials = &material
            chain.materialCount = 1
            _ = b2.CreateChain(body, chain)
        }
    }

    for i in 0 ..< desc.joint_count {
        joint: PhysicsJointDesc = desc.joints[i]
        def: b2.RevoluteJointDef = b2.DefaultRevoluteJointDef()
        def.enableLimit = joint.enable_limit
        def.lowerAngle = joint.lower_angle
        def.upperAngle = joint.upper_angle
        def.enableMotor = joint.enable_motor
        def.motorSpeed = joint.motor_speed
        def.maxMotorTorque = joint.max_motor_torque
        def.collideConnected = joint.collide_connected
        CreateRevoluteAt(world, bodies_out[joint.body_a], bodies_out[joint.body_b], joint.anchor, def)
    }
    return skipped_shapes, true
}

// Take the state of live bodies back into the description: position, angle and velocities. For an editor that lets the physics
// settle (props that fall into place) and saves the result.
PhysicsDescUpdateFromWorld :: proc(desc: ^PhysicsDesc, bodies: []b2.BodyId) {
    for i in 0 ..< min(desc.body_count, len(bodies)) {
        body: ^PhysicsBodyDesc = &desc.bodies[i]
        body.position = b2.Body_GetPosition(bodies[i])
        body.angle = b2.Rot_GetAngle(b2.Body_GetRotation(bodies[i]))
        body.linear_velocity = b2.Body_GetLinearVelocity(bodies[i])
        body.angular_velocity = b2.Body_GetAngularVelocity(bodies[i])
    }
}

// --- Tests ---

@(private="file")
make_test_world :: proc() -> b2.WorldId {
    world_def: b2.WorldDef = b2.DefaultWorldDef()
    world_def.gravity = {0, -10}
    return b2.CreateWorld(world_def)
}

@(private="file")
TestDesc :: struct {
    bodies: [8]PhysicsBodyDesc,
    shapes: [16]PhysicsShapeDesc,
    joints: [4]PhysicsJointDesc,
    desc: PhysicsDesc,
}

@(private="file")
test_desc_init :: proc(storage: ^TestDesc) {
    storage.desc = {bodies = storage.bodies[:], shapes = storage.shapes[:], joints = storage.joints[:]}
}

// A small level: a ground chain, a character (capsule, fixed rotation), a crate, a ball, a pendulum with a hinge, a sensor
@(private="file")
build_level :: proc(storage: ^TestDesc) {
    test_desc_init(storage)
    desc: ^PhysicsDesc = &storage.desc

    ground, _ := PhysicsAddBody(desc, .staticBody, {0, 0})
    PhysicsAddChain(desc, ground, {{20, 0.5}, {5, 0.5}, {-5, 0}, {-20, 0}})      // a chain is one sided: right to left is solid on top
    PhysicsAddSegment(desc, ground, {-20, 10}, {-20, 0})

    character, _ := PhysicsAddBody(desc, .dynamicBody, {-8, 3}, 0, 100)
    desc.bodies[character].fixed_rotation = true
    desc.bodies[character].linear_damping = 0.1
    feet := PhysicsAddCapsule(desc, character, {0, -0.5}, {0, 0.5}, 0.3)
    feet.friction = 0.9
    feet.user_id = 101

    crate, _ := PhysicsAddBody(desc, .dynamicBody, {-4, 2}, 0.3, 200)
    PhysicsAddBox(desc, crate, 0.5, 0.5, {}, 0).restitution = 0.2
    PhysicsAddPolygon(desc, crate, {{-0.6, -0.1}, {0.6, -0.1}, {0.6, 0.1}, {-0.6, 0.1}}, 0.02)

    ball, _ := PhysicsAddBody(desc, .dynamicBody, {2, 5})
    PhysicsAddCircle(desc, ball, 0.4).restitution = 0.8
    desc.bodies[ball].bullet = true
    desc.bodies[ball].linear_velocity = {1, 0}

    pivot, _ := PhysicsAddBody(desc, .staticBody, {10, 6})
    arm, _ := PhysicsAddBody(desc, .dynamicBody, {12, 6})
    PhysicsAddBox(desc, arm, 1, 0.1)
    hinge := PhysicsAddRevolute(desc, pivot, arm, {10, 6})
    hinge.enable_limit = true
    hinge.lower_angle = -1
    hinge.upper_angle = 1
    hinge.user_id = 300

    trigger, _ := PhysicsAddBody(desc, .staticBody, {0, 1})
    zone := PhysicsAddBox(desc, trigger, 2, 1)
    zone.sensor = true
    zone.sensor_events = true
    zone.category = 8
    zone.mask = 2
    zone.group = -3
}

@(private="file")
save_desc :: proc(desc: PhysicsDesc, buffer: []byte) -> []byte {
    writer: serial.Writer
    serial.WriterInit(&writer, buffer)
    serial.FileBegin(&writer)
    PhysicsDescWrite(&writer, desc)
    return serial.FileEnd(&writer)
}

@(test)
test_physics_description_round_trip_is_exact :: proc(t: ^testing.T) {
    original := new(TestDesc)
    loaded := new(TestDesc)
    defer { free(original); free(loaded) }
    build_level(original)

    buffer := make([]byte, 16384)
    defer delete(buffer)
    bytes: []byte = save_desc(original.desc, buffer)
    testing.expect(t, bytes != nil)
    file, _, opened := serial.FileOpen(bytes)
    testing.expect(t, opened)

    test_desc_init(loaded)
    testing.expect(t, PhysicsDescRead(file, &loaded.desc))
    testing.expect_value(t, loaded.desc.body_count, original.desc.body_count)
    testing.expect_value(t, loaded.desc.shape_count, original.desc.shape_count)
    testing.expect_value(t, loaded.desc.joint_count, original.desc.joint_count)
    for i in 0 ..< original.desc.body_count { testing.expectf(t, loaded.bodies[i] == original.bodies[i], "body %d", i) }
    for i in 0 ..< original.desc.shape_count {
        // the points that are not in use are not saved, compare what matters
        a: PhysicsShapeDesc = original.shapes[i]
        b: PhysicsShapeDesc = loaded.shapes[i]
        same: bool = a.kind == b.kind && a.body == b.body && a.a == b.a && a.b == b.b && a.half == b.half && a.angle == b.angle
        same &&= a.radius == b.radius && a.point_count == b.point_count && a.is_loop == b.is_loop && a.density == b.density
        same &&= a.friction == b.friction && a.restitution == b.restitution && a.rolling_resistance == b.rolling_resistance
        same &&= a.category == b.category && a.mask == b.mask && a.group == b.group && a.sensor == b.sensor
        same &&= a.sensor_events == b.sensor_events && a.contact_events == b.contact_events && a.hit_events == b.hit_events && a.user_id == b.user_id
        for p in 0 ..< int(a.point_count) { same &&= a.points[p] == b.points[p] }
        testing.expectf(t, same, "shape %d", i)
    }
    for i in 0 ..< original.desc.joint_count { testing.expectf(t, loaded.joints[i] == original.joints[i], "joint %d", i) }
}

@(test)
test_created_from_a_loaded_file_behaves_exactly_like_the_original :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    original := new(TestDesc)
    loaded := new(TestDesc)
    defer { free(original); free(loaded) }
    build_level(original)
    buffer := make([]byte, 16384)
    defer delete(buffer)
    file, _, _ := serial.FileOpen(save_desc(original.desc, buffer))
    test_desc_init(loaded)
    testing.expect(t, PhysicsDescRead(file, &loaded.desc))

    world_a: b2.WorldId = make_test_world()
    world_b: b2.WorldId = make_test_world()
    defer { b2.DestroyWorld(world_a); b2.DestroyWorld(world_b) }
    bodies_a, bodies_b: [8]b2.BodyId
    skipped_a, ok_a := PhysicsCreate(world_a, original.desc, bodies_a[:])
    skipped_b, ok_b := PhysicsCreate(world_b, loaded.desc, bodies_b[:])
    testing.expect(t, ok_a && ok_b)
    testing.expect_value(t, skipped_a, 0)
    testing.expect_value(t, skipped_b, 0)

    for _ in 0 ..< 240 {
        b2.World_Step(world_a, 1.0 / 60, 4)
        b2.World_Step(world_b, 1.0 / 60, 4)
    }
    for i in 0 ..< original.desc.body_count {
        position_a: Vec2 = b2.Body_GetPosition(bodies_a[i])
        position_b: Vec2 = b2.Body_GetPosition(bodies_b[i])
        testing.expectf(t, position_a == position_b, "body %d: %v and %v", i, position_a, position_b)    // same inputs, same simulation
    }

    // the level is a working level: the character landed on the ground and did not tip over, the pendulum is inside its limit
    character: Vec2 = b2.Body_GetPosition(bodies_b[1])
    testing.expectf(t, character.y < 1.3 && character.y > 0.5, "the character stands on the ground, it is at %v", character)
    testing.expect(t, abs(b2.Rot_GetAngle(b2.Body_GetRotation(bodies_b[1]))) < 1e-4, "fixed rotation was kept")
    arm_angle: f32 = b2.Rot_GetAngle(b2.Body_GetRotation(bodies_b[5]))
    testing.expect(t, arm_angle > -1.05 && arm_angle < 1.05, "the hinge limit was kept")
}

@(test)
test_entities_link_to_their_bodies_and_shapes :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    storage := new(TestDesc)
    defer free(storage)
    build_level(storage)
    world: b2.WorldId = make_test_world()
    defer b2.DestroyWorld(world)
    bodies: [8]b2.BodyId
    PhysicsCreate(world, storage.desc, bodies[:])

    testing.expect_value(t, uintptr(b2.Body_GetUserData(bodies[1])), uintptr(100))   // the character
    testing.expect_value(t, uintptr(b2.Body_GetUserData(bodies[2])), uintptr(200))   // the crate
    testing.expect_value(t, b2.Body_GetType(bodies[0]), b2.BodyType.staticBody)
    testing.expect_value(t, b2.Body_GetShapeCount(bodies[0]), i32(4))                // the 3 segments of the chain and the wall segment
    testing.expect_value(t, b2.Body_GetShapeCount(bodies[2]), i32(2))                // box and polygon
    testing.expect(t, b2.Body_IsBullet(bodies[3]))

    shapes: [4]b2.ShapeId
    found: []b2.ShapeId = b2.Body_GetShapes(bodies[1], shapes[:])
    testing.expect_value(t, len(found), 1)
    testing.expect_value(t, uintptr(b2.Shape_GetUserData(shapes[0])), uintptr(101))
    testing.expect_value(t, b2.Shape_GetFriction(shapes[0]), f32(0.9))
    testing.expect(t, b2.Body_GetMotionLocks(bodies[1]).angularZ)

    sensor_shapes: [2]b2.ShapeId
    sensor_found: []b2.ShapeId = b2.Body_GetShapes(bodies[6], sensor_shapes[:])
    testing.expect_value(t, len(sensor_found), 1)
    testing.expect(t, b2.Shape_IsSensor(sensor_found[0]))
    filter: b2.Filter = b2.Shape_GetFilter(sensor_found[0])
    testing.expect_value(t, filter.categoryBits, u64(8))
    testing.expect_value(t, filter.groupIndex, i32(-3))
}

@(test)
test_a_description_can_take_the_settled_state_of_a_world :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    storage := new(TestDesc)
    defer free(storage)
    test_desc_init(storage)
    desc: ^PhysicsDesc = &storage.desc
    floor, _ := PhysicsAddBody(desc, .staticBody, {0, 0})
    PhysicsAddSegment(desc, floor, {-10, 0}, {10, 0})
    prop, _ := PhysicsAddBody(desc, .dynamicBody, {0, 4})
    PhysicsAddBox(desc, prop, 0.5, 0.5)

    world: b2.WorldId = make_test_world()
    defer b2.DestroyWorld(world)
    bodies: [4]b2.BodyId
    PhysicsCreate(world, desc^, bodies[:])
    for _ in 0 ..< 240 { b2.World_Step(world, 1.0 / 60, 4) }

    PhysicsDescUpdateFromWorld(desc, bodies[:])
    testing.expect(t, abs(desc.bodies[prop].position.y - 0.5) < 0.05, "the crate rests on the floor now")
    testing.expect(t, abs(desc.bodies[prop].linear_velocity.y) < 0.01)
    testing.expect_value(t, desc.bodies[floor].position, Vec2{0, 0})
}

@(test)
test_shapes_that_box2d_cannot_make_are_skipped_and_counted :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    storage := new(TestDesc)
    defer free(storage)
    test_desc_init(storage)
    desc: ^PhysicsDesc = &storage.desc
    body, _ := PhysicsAddBody(desc, .dynamicBody, {0, 0})
    PhysicsAddPolygon(desc, body, {{0, 0}, {1, 0}, {2, 0}})                          // in a line: no hull
    PhysicsAddCircle(desc, body, 0.5)

    world: b2.WorldId = make_test_world()
    defer b2.DestroyWorld(world)
    bodies: [4]b2.BodyId
    skipped, ok := PhysicsCreate(world, desc^, bodies[:])
    testing.expect(t, ok)
    testing.expect_value(t, skipped, 1)
    testing.expect_value(t, b2.Body_GetShapeCount(bodies[0]), i32(1))                // the circle was still made

    none: [0]b2.BodyId
    _, small_ok := PhysicsCreate(world, desc^, none[:])
    testing.expect(t, !small_ok, "bodies_out cannot hold the bodies")
}

@(private="file")
read_back :: proc(bytes: []byte, storage: ^TestDesc) -> bool {
    file, _, opened := serial.FileOpen(bytes)
    if !opened { return false }
    test_desc_init(storage)
    return PhysicsDescRead(file, &storage.desc)
}

// A file that is valid in every way except for one value in the physics chunk
@(private="file")
file_with_one_value :: proc(storage: ^TestDesc, buffer: []byte, change: proc(desc: ^PhysicsDesc)) -> []byte {
    build_level(storage)
    change(&storage.desc)
    return save_desc(storage.desc, buffer)
}

@(test)
test_values_that_would_hurt_a_simulation_are_refused :: proc(t: ^testing.T) {
    storage := new(TestDesc)
    reader_storage := new(TestDesc)
    defer { free(storage); free(reader_storage) }
    buffer := make([]byte, 16384)
    defer delete(buffer)

    testing.expect(t, read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) {}), reader_storage), "the unchanged level reads")
    testing.expect(t, !read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) { desc.bodies[1].position.x = math.nan_f32() }), reader_storage), "NaN position")
    testing.expect(t, !read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) { desc.bodies[1].linear_velocity.y = math.INF_F32 }), reader_storage), "infinite velocity")
    testing.expect(t, !read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) { desc.bodies[1].linear_damping = -1 }), reader_storage), "negative damping")
    testing.expect(t, !read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) { desc.shapes[1].body = 99 }), reader_storage), "a shape on a body that does not exist")
    testing.expect(t, !read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) { desc.shapes[2].radius = -0.3 }), reader_storage), "negative radius")
    testing.expect(t, !read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) { desc.shapes[2].density = math.nan_f32() }), reader_storage), "NaN density")
    testing.expect(t, !read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) { desc.shapes[4].point_count = 2 }), reader_storage), "a polygon with 2 points")
    testing.expect(t, !read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) { desc.shapes[0].point_count = 1 }), reader_storage), "a chain with 1 point")
    testing.expect(t, !read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) { desc.joints[0].body_b = desc.joints[0].body_a }), reader_storage), "a joint from a body to itself")
    testing.expect(t, !read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) { desc.joints[0].body_a = 50 }), reader_storage), "a joint to a body that does not exist")
    testing.expect(t, !read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) { desc.joints[0].lower_angle = 2 }), reader_storage), "limits the wrong way round")
    testing.expect(t, !read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) { desc.bodies[1].type = b2.BodyType(9) }), reader_storage), "a body type that does not exist")
    testing.expect(t, !read_back(file_with_one_value(storage, buffer, proc(desc: ^PhysicsDesc) { desc.shapes[0].kind = PhysicsShapeKind(77) }), reader_storage), "a shape kind that does not exist")
}

@(test)
test_a_description_that_does_not_fit_the_slices_is_refused :: proc(t: ^testing.T) {
    storage := new(TestDesc)
    defer free(storage)
    build_level(storage)
    buffer := make([]byte, 16384)
    defer delete(buffer)
    file, _, _ := serial.FileOpen(save_desc(storage.desc, buffer))

    small_bodies: [3]PhysicsBodyDesc
    small: PhysicsDesc = {bodies = small_bodies[:], shapes = storage.shapes[:], joints = storage.joints[:]}
    testing.expect(t, !PhysicsDescRead(file, &small), "7 bodies do not fit 3 slots")

    no_chunk_buffer: [64]byte
    writer: serial.Writer
    serial.WriterInit(&writer, no_chunk_buffer[:])
    serial.FileBegin(&writer)
    empty_file, _, _ := serial.FileOpen(serial.FileEnd(&writer))
    testing.expect(t, !PhysicsDescRead(empty_file, &small), "no physics chunk in the file")
}

@(test)
test_garbage_in_the_physics_chunk_never_crashes :: proc(t: ^testing.T) {
    state: u32 = 88172645
    next :: proc(state: ^u32) -> u32 {
        state^ ~= state^ << 13
        state^ ~= state^ >> 17
        state^ ~= state^ << 5
        return state^
    }
    storage := new(TestDesc)
    defer free(storage)
    for _ in 0 ..< 3000 {
        buffer: [600]byte
        writer: serial.Writer
        serial.WriterInit(&writer, buffer[:])
        serial.FileBegin(&writer)
        serial.ChunkBegin(&writer, PHYSICS_TAG(), 1)
        length: int = int(next(&state) % 500)
        for _ in 0 ..< length {
            // plausible small counts first, so the parser gets past the counts into the values
            serial.WriteU8(&writer, u8(next(&state)) if length > 8 else 1)
        }
        serial.ChunkEnd(&writer)
        read_back(serial.FileEnd(&writer), storage)
    }
    testing.expect(t, true, "no crash")
}
