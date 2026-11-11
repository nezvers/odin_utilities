// Port of box2d/samples/sample_shapes.cpp (Wind is not ported yet)
package box2d_samples

import "core:math"
import b2 "vendor:box2d"
import b2o ".."

@(init)
register_shapes :: proc "contextless" () {
    b2o.RegisterSample({category = "Shapes", name = "Chain Shape", create = chain_shape_create, draw = chain_shape_draw, controls = chain_shape_controls})
    b2o.RegisterSample({category = "Shapes", name = "Chain Segment", create = chain_segment_create, controls = chain_segment_controls})
    b2o.RegisterSample({category = "Shapes", name = "Compound Shapes", create = compound_create, draw = compound_draw, controls = compound_controls})
    b2o.RegisterSample({category = "Shapes", name = "Filter", create = filter_create, draw = filter_draw, controls = filter_controls})
    b2o.RegisterSample({category = "Shapes", name = "Custom Filter", create = custom_filter_create, draw = custom_filter_draw})
    b2o.RegisterSample({category = "Shapes", name = "Friction", create = friction_create})
    b2o.RegisterSample({category = "Shapes", name = "Rolling Resistance", create = rolling_create, draw = rolling_draw, keyboard = rolling_keyboard})
    b2o.RegisterSample({category = "Shapes", name = "Conveyor Belt", create = conveyor_create})
    b2o.RegisterSample({category = "Shapes", name = "Tangent Speed", create = tangent_create, step = tangent_step, controls = tangent_controls})
    b2o.RegisterSample({category = "Shapes", name = "Modify Geometry", create = modify_create, controls = modify_controls})
    b2o.RegisterSample({category = "Shapes", name = "Chain Link", create = chain_link_create, draw = chain_link_draw})
    b2o.RegisterSample({category = "Shapes", name = "Rounded", create = rounded_create})
    b2o.RegisterSample({category = "Shapes", name = "Ellipse", create = ellipse_create})
    b2o.RegisterSample({category = "Shapes", name = "Offset", create = offset_create, draw = offset_draw})
    b2o.RegisterSample({category = "Shapes", name = "Explosion", create = explosion_create, step = explosion_step, draw = explosion_draw, controls = explosion_controls})
    b2o.RegisterSample({category = "Shapes", name = "Recreate Static", create = recreate_static_create, step = recreate_static_step})
}

@(private="file")
add_shape_by_type :: proc(body: b2.BodyId, shape_type: i32, shape_def: b2.ShapeDef, circle_radius: f32 = 0.5) -> b2.ShapeId {
    switch shape_type {
    case 0: return b2o.AddCircle(body, circle_radius, def = shape_def)
    case 1: return b2o.AddCapsule(body, {-0.5, 0}, {0.5, 0}, 0.25, shape_def)
    }
    return b2o.AddPolygon(body, b2.MakeBox(0.5, 0.5), shape_def)
}

// ------------------------------------------------------------------------------------------------
// Chain Shape
// ------------------------------------------------------------------------------------------------

@(private="file") chain_ground, chain_body: b2.BodyId
@(private="file") chain_id: b2.ChainId
@(private="file") chain_shape: b2.ShapeId
@(private="file") chain_shape_type: i32
@(private="file") chain_material: b2.SurfaceMaterial

chain_shape_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 0}, 43.75)
    chain_ground = {}
    chain_body = {}
    chain_shape_type = 0

    chain_material = b2.DefaultSurfaceMaterial()
    chain_material.friction = 0.2
    chain_material.customColor = u32(b2.HexColor.SteelBlue)
    chain_material.userMaterialId = 42

    chain_shape_scene(ctx)
    chain_shape_launch(ctx)
}

@(private="file")
chain_shape_scene :: proc(ctx: ^b2o.SampleContext) {
    if b2.Body_IsValid(chain_ground) { b2.DestroyBody(chain_ground) }

    points: [19]Vec2 = {
        {-56.885498, 12.8985004}, {-56.885498, 16.2057495}, {56.885498, 16.2057495}, {56.885498, -16.2057514},
        {51.5935059, -16.2057514}, {43.6559982, -10.9139996}, {35.7184982, -10.9139996}, {27.7809982, -10.9139996},
        {21.1664963, -14.2212505}, {11.9059982, -16.2057514}, {0, -16.2057514}, {-10.5835037, -14.8827496},
        {-17.1980019, -13.5597477}, {-21.1665001, -12.2370014}, {-25.1355019, -9.5909977}, {-31.75, -3.63799858},
        {-38.3644981, 6.2840004}, {-42.3334999, 9.59125137}, {-47.625, 11.5755005},
    }

    chain_def: b2.ChainDef = b2.DefaultChainDef()
    chain_def.points = raw_data(points[:])
    chain_def.pointCount = len(points)
    chain_def.materials = &chain_material
    chain_def.materialCount = 1
    chain_def.isLoop = true

    chain_ground = b2.CreateBody(ctx.world, b2.DefaultBodyDef())
    chain_id = b2.CreateChain(chain_ground, chain_def)
}

@(private="file")
chain_shape_launch :: proc(ctx: ^b2o.SampleContext) {
    if b2.Body_IsValid(chain_body) { b2.DestroyBody(chain_body) }
    chain_body = b2o.CreateBodyAt(ctx.world, .dynamicBody, {-55, 13.5})
    shape_def: b2.ShapeDef = b2.DefaultShapeDef()
    shape_def.material = chain_material
    chain_shape = add_shape_by_type(chain_body, chain_shape_type, shape_def)
    ctx.step_count = 0
}

chain_shape_controls :: proc(ctx: ^b2o.SampleContext) {
    ui: ^b2o.Ui = ctx.ui
    b2o.UiLabel(ui, "Shape")
    if b2o.UiSelect(ui, {"Circle", "Capsule", "Box"}, &chain_shape_type) {
        chain_shape_launch(ctx)
    }
    if b2o.UiSlider(ui, "Friction", &chain_material.friction, 0, 1) {
        b2.Shape_SetSurfaceMaterial(chain_shape, chain_material)
        b2.Chain_SetAllSurfaceMaterials(chain_id, chain_material)
    }
    if b2o.UiSlider(ui, "Restitution", &chain_material.restitution, 0, 2) {
        b2.Shape_SetSurfaceMaterial(chain_shape, chain_material)
    }
    if b2o.UiButton(ui, "Launch") {
        chain_shape_launch(ctx)
    }
}

chain_shape_draw :: proc(ctx: ^b2o.SampleContext) {
    b2o.DrawLine(ctx, {}, {0.5, 0}, .Red)
    b2o.DrawLine(ctx, {}, {0, 0.5}, .Green)
}

// ------------------------------------------------------------------------------------------------
// Chain Segment
// ------------------------------------------------------------------------------------------------

CHAIN_SEGMENT_COUNT :: 32
CHAIN_POINT_COUNT :: CHAIN_SEGMENT_COUNT + 3

@(private="file") cseg_body: b2.BodyId
@(private="file") cseg_shape_type: i32
@(private="file") cseg_shapes: [CHAIN_SEGMENT_COUNT]b2.ShapeId
@(private="file") cseg_points: [CHAIN_POINT_COUNT]Vec2
@(private="file") cseg_mutate_index: int

chain_segment_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 0}, 25)
    cseg_body = {}
    cseg_shape_type = 0
    cseg_mutate_index = 0

    ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())

    // Walk right-to-left so the right-perpendicular normal of (point2 - point1) points up.
    for i in 0..<CHAIN_POINT_COUNT {
        x: f32 = 25 - 50 * f32(i) / f32(CHAIN_POINT_COUNT - 1)
        y: f32 = 1.5 * math.sin(0.18 * x)
        cseg_points[i] = {x, y}
    }

    shape_def: b2.ShapeDef = b2.DefaultShapeDef()
    for i in 0..<CHAIN_SEGMENT_COUNT {
        segment: b2.ChainSegment = {
            ghost1 = cseg_points[i],
            segment = {cseg_points[i + 1], cseg_points[i + 2]},
            ghost2 = cseg_points[i + 3],
            chainId = -1,
        }
        cseg_shapes[i] = b2.CreateChainSegmentShape(ground, shape_def, segment)
    }
    chain_segment_launch(ctx)
}

@(private="file")
chain_segment_launch :: proc(ctx: ^b2o.SampleContext) {
    if b2.Body_IsValid(cseg_body) { b2.DestroyBody(cseg_body) }
    cseg_body = b2o.CreateBodyAt(ctx.world, .dynamicBody, {-18, 5})
    switch cseg_shape_type {
    case 0: b2o.AddCircle(cseg_body, 0.25)
    case 1: b2o.AddCapsule(cseg_body, {-0.5, 0}, {0.5, 0}, 0.25)
    case: b2o.AddPolygon(cseg_body, b2.MakeSquare(0.5))
    }
}

@(private="file")
chain_segment_make :: proc(index: int) -> b2.ChainSegment {
    return {
        ghost1 = cseg_points[index - 1],
        segment = {cseg_points[index], cseg_points[index + 1]},
        ghost2 = cseg_points[index + 2],
        chainId = -1,
    }
}

@(private="file")
chain_segment_mutate :: proc() {
    // Index 0 and pointCount - 1 are ghost vertices and are not mutated
    index: int = cseg_mutate_index + 1
    cseg_mutate_index += 1
    if cseg_mutate_index == CHAIN_SEGMENT_COUNT {
        cseg_mutate_index = 0
    }
    cseg_points[index].y += 0.25

    b2.Shape_SetChainSegment(cseg_shapes[index - 1], chain_segment_make(index))
    if index - 1 > 0 {
        b2.Shape_SetChainSegment(cseg_shapes[index - 2], chain_segment_make(index - 1))
    }
    if index + 1 < CHAIN_POINT_COUNT - 2 {
        b2.Shape_SetChainSegment(cseg_shapes[index], chain_segment_make(index + 1))
    }
}

chain_segment_controls :: proc(ctx: ^b2o.SampleContext) {
    ui: ^b2o.Ui = ctx.ui
    b2o.UiLabel(ui, "Shape")
    if b2o.UiSelect(ui, {"Circle", "Capsule", "Box"}, &cseg_shape_type) {
        chain_segment_launch(ctx)
    }
    if b2o.UiButton(ui, "Launch") { chain_segment_launch(ctx) }
    if b2o.UiButton(ui, "Mutate") { chain_segment_mutate() }
}

// ------------------------------------------------------------------------------------------------
// Compound Shapes: careful creation of compound shapes avoids stuck objects, also shows body AABB
// ------------------------------------------------------------------------------------------------

@(private="file") compound_table1, compound_table2, compound_ship1, compound_ship2: b2.BodyId
@(private="file") compound_draw_aabbs: bool

compound_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 6}, 12.5)
    b2o.CreateGroundSegment(ctx.world, {50, 0}, {-50, 0})
    identity: b2.Rot = {1, 0}

    // Table 1
    compound_table1 = b2o.CreateBodyAt(ctx.world, .dynamicBody, {-15, 1})
    b2o.AddPolygon(compound_table1, b2.MakeOffsetBox(3, 0.5, {0, 3.5}, identity))
    b2o.AddPolygon(compound_table1, b2.MakeOffsetBox(0.5, 1.5, {-2.5, 1.5}, identity))
    b2o.AddPolygon(compound_table1, b2.MakeOffsetBox(0.5, 1.5, {2.5, 1.5}, identity))

    // Table 2
    compound_table2 = b2o.CreateBodyAt(ctx.world, .dynamicBody, {-5, 1})
    b2o.AddPolygon(compound_table2, b2.MakeOffsetBox(3, 0.5, {0, 3.5}, identity))
    b2o.AddPolygon(compound_table2, b2.MakeOffsetBox(0.5, 2, {-2.5, 2}, identity))
    b2o.AddPolygon(compound_table2, b2.MakeOffsetBox(0.5, 2, {2.5, 2}, identity))

    triangle :: proc(a: Vec2, b: Vec2, c: Vec2) -> b2.Polygon {
        vertices: [3]Vec2 = {a, b, c}
        return b2.MakePolygon(b2.ComputeHull(vertices[:]), 0)
    }

    // Spaceship 1
    compound_ship1 = b2o.CreateBodyAt(ctx.world, .dynamicBody, {5, 1})
    b2o.AddPolygon(compound_ship1, triangle({-2, 0}, {0, 4.0 / 3.0}, {0, 4}))
    b2o.AddPolygon(compound_ship1, triangle({2, 0}, {0, 4.0 / 3.0}, {0, 4}))

    // Spaceship 2
    compound_ship2 = b2o.CreateBodyAt(ctx.world, .dynamicBody, {15, 1})
    b2o.AddPolygon(compound_ship2, triangle({-2, 0}, {1, 2}, {0, 4}))
    b2o.AddPolygon(compound_ship2, triangle({2, 0}, {-1, 2}, {0, 4}))

    compound_draw_aabbs = false
}

compound_controls :: proc(ctx: ^b2o.SampleContext) {
    if b2o.UiButton(ctx.ui, "Intrude") {
        identity_box :: proc(world: b2.WorldId, source: b2.BodyId, shape: proc(body: b2.BodyId)) {
            body_def: b2.BodyDef = b2.DefaultBodyDef()
            body_def.type = .dynamicBody
            body_def.position = b2.Body_GetPosition(source)
            body_def.rotation = b2.Body_GetRotation(source)
            shape(b2.CreateBody(world, body_def))
        }
        plank :: proc(body: b2.BodyId) {
            b2o.AddPolygon(body, b2.MakeOffsetBox(4, 0.1, {0, 3}, b2.Rot{1, 0}))
        }
        ball :: proc(body: b2.BodyId) {
            b2o.AddCircle(body, 0.5, {0, 2})
        }
        identity_box(ctx.world, compound_table1, plank)
        identity_box(ctx.world, compound_table2, plank)
        identity_box(ctx.world, compound_ship1, ball)
        identity_box(ctx.world, compound_ship2, ball)
    }
    b2o.UiCheckbox(ctx.ui, "Body AABBs", &compound_draw_aabbs)
}

compound_draw :: proc(ctx: ^b2o.SampleContext) {
    if compound_draw_aabbs {
        for body in ([4]b2.BodyId{compound_table1, compound_table2, compound_ship1, compound_ship2}) {
            b2o.DrawBounds(ctx, b2.Body_ComputeBounds(body), .Yellow)
        }
    }
}

// ------------------------------------------------------------------------------------------------
// Filter
// ------------------------------------------------------------------------------------------------

FILTER_GROUND :: u64(0x1)
FILTER_TEAM1 :: u64(0x2)
FILTER_TEAM2 :: u64(0x4)
FILTER_TEAM3 :: u64(0x8)

@(private="file") filter_players: [3]b2.BodyId
@(private="file") filter_shapes: [3]b2.ShapeId

filter_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 5}, 12.5)

    ground_def: b2.ShapeDef = b2.DefaultShapeDef()
    ground_def.filter.categoryBits = FILTER_GROUND
    ground_def.filter.maskBits = ~u64(0)
    ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())
    b2o.AddSegment(ground, {-20, 0}, {20, 0}, ground_def)

    teams: [3]u64 = {FILTER_TEAM1, FILTER_TEAM2, FILTER_TEAM3}
    for i in 0..<3 {
        filter_players[i] = b2o.CreateBodyAt(ctx.world, .dynamicBody, {0, 2 + 3 * f32(i)})
        shape_def: b2.ShapeDef = b2.DefaultShapeDef()
        shape_def.filter.categoryBits = teams[i]
        shape_def.filter.maskBits = FILTER_GROUND | (FILTER_TEAM1 | FILTER_TEAM2 | FILTER_TEAM3) & ~teams[i]
        filter_shapes[i] = b2o.AddPolygon(filter_players[i], b2.MakeBox(2, 1), shape_def)
    }
}

filter_controls :: proc(ctx: ^b2o.SampleContext) {
    ui: ^b2o.Ui = ctx.ui
    teams: [3]u64 = {FILTER_TEAM1, FILTER_TEAM2, FILTER_TEAM3}
    team_labels: [3]string = {"Team 1", "Team 2", "Team 3"}
    for player in 0..<3 {
        b2o.UiLabelf(ui, "Player %d Collides With", player + 1)
        filter: b2.Filter = b2.Shape_GetFilter(filter_shapes[player])
        for team in 0..<3 {
            if team == player { continue }
            enabled: bool = filter.maskBits & teams[team] == teams[team]
            if b2o.UiCheckbox(ui, team_labels[team], &enabled) {
                if enabled {
                    filter.maskBits |= teams[team]
                } else {
                    filter.maskBits &= ~teams[team]
                }
                b2.Shape_SetFilter(filter_shapes[player], filter)
            }
        }
    }
}

filter_draw :: proc(ctx: ^b2o.SampleContext) {
    for i in 0..<3 {
        p: Vec2 = b2.Body_GetPosition(filter_players[i])
        b2o.DrawString(ctx, {p.x - 0.5, p.y}, .White, "player %d", i + 1)
    }
}

// ------------------------------------------------------------------------------------------------
// Custom Filter
// ------------------------------------------------------------------------------------------------

CUSTOM_FILTER_COUNT :: 10
@(private="file") custom_filter_bodies: [CUSTOM_FILTER_COUNT]b2.BodyId

custom_filter_should_collide :: proc "c" (shape_a: b2.ShapeId, shape_b: b2.ShapeId, user_context: rawptr) -> bool {
    user_a: rawptr = b2.Shape_GetUserData(shape_a)
    user_b: rawptr = b2.Shape_GetUserData(shape_b)
    if user_a == nil || user_b == nil {
        return true
    }
    index_a: int = int(uintptr(user_a))
    index_b: int = int(uintptr(user_b))
    return ((index_a & 1) + (index_b & 1)) != 1
}

custom_filter_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 5}, 10)
    b2.World_SetCustomFilterCallback(ctx.world, custom_filter_should_collide, nil)
    b2o.CreateGroundSegment(ctx.world, {-40, 0}, {40, 0})

    shape_def: b2.ShapeDef = b2.DefaultShapeDef()
    shape_def.enableCustomFiltering = true
    x: f32 = -CUSTOM_FILTER_COUNT
    for i in 0..<CUSTOM_FILTER_COUNT {
        custom_filter_bodies[i] = b2o.CreateBodyAt(ctx.world, .dynamicBody, {x, 5})
        shape_def.userData = rawptr(uintptr(i + 1))
        b2o.AddPolygon(custom_filter_bodies[i], b2.MakeSquare(1), shape_def)
        x += 2
    }
}

custom_filter_draw :: proc(ctx: ^b2o.SampleContext) {
    b2o.ScreenText(ctx, "Custom filter disables collision between odd and even shapes")
    for i in 0..<CUSTOM_FILTER_COUNT {
        p: Vec2 = b2.Body_GetPosition(custom_filter_bodies[i])
        b2o.DrawString(ctx, p, .White, "%d", i)
    }
}

// ------------------------------------------------------------------------------------------------
// Friction
// ------------------------------------------------------------------------------------------------

friction_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 14}, 15)
    ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())
    ground_def: b2.ShapeDef = b2o.MakeShapeDef(1, 0.2)
    b2o.AddSegment(ground, {-40, 0}, {40, 0}, ground_def)
    identity: b2.Rot = {1, 0}
    b2o.AddPolygon(ground, b2.MakeOffsetBox(13, 0.25, {-4, 22}, b2.MakeRot(-0.25)), ground_def)
    b2o.AddPolygon(ground, b2.MakeOffsetBox(0.25, 1, {10.5, 19}, identity), ground_def)
    b2o.AddPolygon(ground, b2.MakeOffsetBox(13, 0.25, {4, 14}, b2.MakeRot(0.25)), ground_def)
    b2o.AddPolygon(ground, b2.MakeOffsetBox(0.25, 1, {-10.5, 11}, identity), ground_def)
    b2o.AddPolygon(ground, b2.MakeOffsetBox(13, 0.25, {-4, 6}, b2.MakeRot(-0.25)), ground_def)

    friction: [5]f32 = {0.75, 0.5, 0.35, 0.1, 0}
    for i in 0..<5 {
        body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {-15 + 4 * f32(i), 28})
        b2o.AddBox(body, 0.5, 0.5, b2o.MakeShapeDef(25, friction[i]))
    }
}

// ------------------------------------------------------------------------------------------------
// Rolling Resistance
// ------------------------------------------------------------------------------------------------

@(private="file") rolling_lift: f32
@(private="file") rolling_scale: f32

rolling_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {5, 20}, 27.5)
    rolling_lift = 0
    rolling_scale = 0.02
    rolling_scene(ctx)
}

@(private="file")
rolling_scene :: proc(ctx: ^b2o.SampleContext) {
    shape_def: b2.ShapeDef = b2.DefaultShapeDef()
    for i in 0..<20 {
        ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())
        b2o.AddSegment(ground, {-40, 2 * f32(i)}, {40, 2 * f32(i) + rolling_lift}, shape_def)

        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.type = .dynamicBody
        body_def.position = {-39.5, 2 * f32(i) + 0.75}
        body_def.angularVelocity = -10
        body_def.linearVelocity = {5, 0}
        body: b2.BodyId = b2.CreateBody(ctx.world, body_def)
        shape_def.material.rollingResistance = rolling_scale * f32(i)
        b2o.AddCircle(body, 0.5, def = shape_def)
    }
}

rolling_keyboard :: proc(ctx: ^b2o.SampleContext, key: b2o.Key) {
    lift: f32 = -1
    #partial switch key {
    case .N1: lift = 0
    case .N2: lift = 5
    case .N3: lift = -5
    }
    if lift != -1 || key == .N3 {
        rolling_lift = lift
        b2o.SampleRecreateWorld(ctx)
        rolling_scene(ctx)
    }
}

rolling_draw :: proc(ctx: ^b2o.SampleContext) {
    b2o.ScreenText(ctx, "1, 2, 3: flat, lift up, lift down")
    for i in 0..<20 {
        b2o.DrawString(ctx, {-41.5, 2 * f32(i) + 1}, .White, "%.2f", rolling_scale * f32(i))
    }
}

// ------------------------------------------------------------------------------------------------
// Conveyor Belt
// ------------------------------------------------------------------------------------------------

conveyor_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {2, 7.5}, 12)
    b2o.CreateGroundSegment(ctx.world)

    // Platform
    platform: b2.BodyId = b2o.CreateBodyAt(ctx.world, .staticBody, {-5, 5})
    shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, 0.8)
    shape_def.material.tangentSpeed = 2
    b2o.AddPolygon(platform, b2.MakeRoundedBox(10, 0.25, 0.25), shape_def)

    // Boxes
    for i in 0..<5 {
        body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {-10 + 2 * f32(i), 7})
        b2o.AddPolygon(body, b2.MakeSquare(0.5))
    }
}

// ------------------------------------------------------------------------------------------------
// Tangent Speed
// ------------------------------------------------------------------------------------------------

TANGENT_TOTAL_COUNT :: 200
@(private="file") tangent_bodies: [TANGENT_TOTAL_COUNT]b2.BodyId
@(private="file") tangent_count: int
@(private="file") tangent_friction, tangent_rolling: f32

tangent_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {60, -15}, 38)
    ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())

    path :: "m 613.8334,185.20833 -42.33338,0 h -37.04166 l -34.39581,0 -29.10417,-2.64583 -26.45834,-7.9375 -26.45833,-13.22917 -23.81251,-21.16666 h -13.22916 v 44.97916 H 68.791712 V 0 h -21.16671 v 206.375 l 566.208398,-1e-5 z"
    offset: Vec2 = {-47.375002, 0.25}
    points: [20]Vec2
    count: int = b2o.ParsePath(path, offset, points[:], 0.2, true)

    materials: [20]b2.SurfaceMaterial
    for &material in materials {
        material = b2.DefaultSurfaceMaterial()
        material.friction = 0.6
    }
    speeds: [7]f32 = {-10, -20, -30, -40, -50, -60, -70}
    colors: [7]b2.HexColor = {.DarkBlue, .DarkCyan, .DarkGoldenRod, .DarkGray, .DarkGreen, .DarkKhaki, .DarkMagenta}
    for i in 0..<7 {
        materials[i].tangentSpeed = speeds[i]
        materials[i].customColor = u32(colors[i])
    }

    chain_def: b2.ChainDef = b2.DefaultChainDef()
    chain_def.points = raw_data(points[:])
    chain_def.pointCount = i32(count)
    chain_def.isLoop = true
    chain_def.materials = raw_data(materials[:])
    chain_def.materialCount = i32(count)
    _ = b2.CreateChain(ground, chain_def)

    tangent_count = 0
    tangent_bodies = {}
    tangent_friction = 0.6
    tangent_rolling = 0.3
}

@(private="file")
tangent_reset :: proc() {
    for i in 0..<tangent_count {
        b2.DestroyBody(tangent_bodies[i])
    }
    tangent_count = 0
}

tangent_controls :: proc(ctx: ^b2o.SampleContext) {
    if b2o.UiSlider(ctx.ui, "Friction", &tangent_friction, 0, 2) { tangent_reset() }
    if b2o.UiSlider(ctx.ui, "Rolling Resistance", &tangent_rolling, 0, 1) { tangent_reset() }
}

tangent_step :: proc(ctx: ^b2o.SampleContext, dt: f32) {
    if ctx.step_count % 25 == 0 && tangent_count < TANGENT_TOTAL_COUNT && !ctx.pause {
        body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {110, -30})
        shape_def: b2.ShapeDef = b2.DefaultShapeDef()
        shape_def.material.friction = tangent_friction
        shape_def.material.rollingResistance = tangent_rolling
        b2o.AddCircle(body, 0.5, def = shape_def)
        tangent_bodies[tangent_count] = body
        tangent_count += 1
    }
}

// ------------------------------------------------------------------------------------------------
// Modify Geometry: only supported on dynamic and kinematic shapes
// ------------------------------------------------------------------------------------------------

@(private="file") modify_shape: b2.ShapeId
@(private="file") modify_type: b2.ShapeType
@(private="file") modify_scale: f32

modify_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 5}, 6.25)
    ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())
    b2o.AddPolygon(ground, b2.MakeOffsetBox(10, 1, {0, -1}, b2.Rot{1, 0}))

    b2o.CreateDynamicPolygon(ctx.world, {0, 4}, b2.MakeBox(1, 1), 1)

    modify_type = .circleShape
    modify_scale = 1
    body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .kinematicBody, {0, 1})
    modify_shape = b2o.AddCircle(body, 0.5)
}

@(private="file")
modify_update :: proc() {
    s: f32 = modify_scale
    #partial switch modify_type {
    case .circleShape:
        b2.Shape_SetCircle(modify_shape, b2.Circle{{0, 0}, 0.5 * s})
    case .capsuleShape:
        b2.Shape_SetCapsule(modify_shape, b2.Capsule{{-0.5 * s, 0}, {0, 0.5 * s}, 0.5 * s})
    case .segmentShape:
        b2.Shape_SetSegment(modify_shape, b2.Segment{{-0.5 * s, 0}, {0.75 * s, 0}})
    case .polygonShape:
        b2.Shape_SetPolygon(modify_shape, b2.MakeBox(0.5 * s, 0.75 * s))
    }
    b2.Body_UpdateMassFromShapes(b2.Shape_GetBody(modify_shape))
}

modify_controls :: proc(ctx: ^b2o.SampleContext) {
    ui: ^b2o.Ui = ctx.ui
    if b2o.UiButton(ui, "Circle", modify_type == .circleShape) { modify_type = .circleShape; modify_update() }
    if b2o.UiButton(ui, "Capsule", modify_type == .capsuleShape) { modify_type = .capsuleShape; modify_update() }
    if b2o.UiButton(ui, "Segment", modify_type == .segmentShape) { modify_type = .segmentShape; modify_update() }
    if b2o.UiButton(ui, "Polygon", modify_type == .polygonShape) { modify_type = .polygonShape; modify_update() }
    if b2o.UiSlider(ui, "Scale", &modify_scale, 0.1, 10) { modify_update() }

    body: b2.BodyId = b2.Shape_GetBody(modify_shape)
    body_type: b2.BodyType = b2.Body_GetType(body)
    if b2o.UiButton(ui, "Static", body_type == .staticBody) { b2.Body_SetType(body, .staticBody) }
    if b2o.UiButton(ui, "Kinematic", body_type == .kinematicBody) { b2.Body_SetType(body, .kinematicBody) }
    if b2o.UiButton(ui, "Dynamic", body_type == .dynamicBody) { b2.Body_SetType(body, .dynamicBody) }
}

// ------------------------------------------------------------------------------------------------
// Chain Link: two chain shapes linked with ghost points
// ------------------------------------------------------------------------------------------------

chain_link_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 5}, 12.5)
    points1: [4]Vec2 = {{0, 0}, {-40, 0}, {-40, -1}, {0, -1}}
    points2: [4]Vec2 = {{0, -1}, {40, -1}, {40, 0}, {0, 0}}

    ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())

    chain_def: b2.ChainDef = b2.DefaultChainDef()
    chain_def.points = raw_data(points1[:])
    chain_def.pointCount = 4
    // The other chain carries on past both ends of this one
    chain_def.ghost1 = {40, 1}
    chain_def.ghost2 = {40, -1}
    chain_def.isLoop = false
    _ = b2.CreateChain(ground, chain_def)

    chain_def = b2.DefaultChainDef()
    chain_def.points = raw_data(points2[:])
    chain_def.pointCount = 4
    chain_def.ghost1 = {-40, -1}
    chain_def.ghost2 = {-40, 0}
    chain_def.isLoop = false
    _ = b2.CreateChain(ground, chain_def)

    circle: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {-5, 2})
    b2o.AddCircle(circle, 0.5)
    capsule: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {0, 2})
    b2o.AddCapsule(capsule, {-0.5, 0}, {0.5, 0}, 0.25)
    box: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {5, 2})
    b2o.AddBox(box, 0.5, 0.5)
}

chain_link_draw :: proc(ctx: ^b2o.SampleContext) {
    b2o.ScreenText(ctx, "This shows how to link together two chain shapes")
}

// ------------------------------------------------------------------------------------------------
// Rounded, Ellipse: boxes in a container
// ------------------------------------------------------------------------------------------------

@(private="file")
shapes_container :: proc(ctx: ^b2o.SampleContext) {
    ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())
    identity: b2.Rot = {1, 0}
    b2o.AddPolygon(ground, b2.MakeOffsetBox(20, 1, {0, -1}, identity))
    b2o.AddPolygon(ground, b2.MakeOffsetBox(1, 5, {19, 5}, identity))
    b2o.AddPolygon(ground, b2.MakeOffsetBox(1, 5, {-19, 5}, identity))
}

rounded_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {2, 8}, 13.75)
    shapes_container(ctx)

    shape_def: b2.ShapeDef = b2.DefaultShapeDef()
    shape_def.material.rollingResistance = 0.3
    y: f32 = 2
    for _ in 0..<10 {
        x: f32 = -5
        for _ in 0..<10 {
            body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {x, y})
            poly: b2.Polygon = b2o.RandomPolygon(0.5)
            poly.radius = b2o.RandomFloatRange(0.05, 0.25)
            b2o.AddPolygon(body, poly, shape_def)
            x += 1
        }
        y += 1
    }
}

ellipse_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {2, 8}, 13.75)
    shapes_container(ctx)

    points: [6]Vec2 = {{0, -0.25}, {0, 0.25}, {0.05, 0.075}, {-0.05, 0.075}, {0.05, -0.075}, {-0.05, -0.075}}
    poly: b2.Polygon = b2.MakePolygon(b2.ComputeHull(points[:]), 0.2)

    shape_def: b2.ShapeDef = b2.DefaultShapeDef()
    shape_def.material.rollingResistance = 0.2
    y: f32 = 2
    for _ in 0..<10 {
        x: f32 = -5
        for _ in 0..<10 {
            body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {x, y})
            b2o.AddPolygon(body, poly, shape_def)
            x += 1
        }
        y += 1
    }
}

// ------------------------------------------------------------------------------------------------
// Offset
// ------------------------------------------------------------------------------------------------

offset_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {2, 8}, 13.75)
    ground: b2.BodyId = b2o.CreateBodyAt(ctx.world, .staticBody, {-1, 1})
    b2o.AddPolygon(ground, b2.MakeOffsetBox(1, 1, {10, -2}, b2.MakeRot(0.5 * math.PI)))

    capsule: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {13.5, -0.75})
    b2o.AddCapsule(capsule, {-5, 1}, {-4, 1}, 0.25)

    box: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {0, 0})
    b2o.AddPolygon(box, b2.MakeOffsetBox(0.75, 0.5, {9, 2}, b2.MakeRot(0.5 * math.PI)))
}

offset_draw :: proc(ctx: ^b2o.SampleContext) {
    b2o.DrawTransform(ctx, {q = {1, 0}})
}

// ------------------------------------------------------------------------------------------------
// Explosion: shows how to use explosions and demonstrates the projected perimeter
// ------------------------------------------------------------------------------------------------

@(private="file") explosion_joints: [12]b2.JointId
@(private="file") explosion_radius, explosion_falloff, explosion_impulse, explosion_angle: f32

explosion_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 0}, 14)
    ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())

    explosion_angle = 0
    weld_def: b2.WeldJointDef = b2.DefaultWeldJointDef()
    weld_def.base.bodyIdA = ground
    weld_def.base.localFrameA.q = b2.MakeRot(explosion_angle)
    weld_def.base.localFrameB.p = {}
    weld_def.angularHertz = 0.5
    weld_def.angularDampingRatio = 0.7
    weld_def.linearHertz = 0.5
    weld_def.linearDampingRatio = 0.7

    r: f32 = 8
    index: int
    for angle: f32 = 0; angle < 360; angle += 30 {
        cos_sin: b2.CosSin = b2.ComputeCosSin(angle * math.PI / 180)
        position: Vec2 = {r * cos_sin.cosine, r * cos_sin.sine}
        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.type = .dynamicBody
        body_def.gravityScale = 0
        body_def.position = position
        body: b2.BodyId = b2.CreateBody(ctx.world, body_def)
        b2o.AddBox(body, 1, 0.1)

        weld_def.base.localFrameA.p = position
        weld_def.base.bodyIdB = body
        explosion_joints[index] = b2.CreateWeldJoint(ctx.world, weld_def)
        index += 1
    }

    explosion_radius = 7
    explosion_falloff = 3
    explosion_impulse = 10
}

explosion_controls :: proc(ctx: ^b2o.SampleContext) {
    ui: ^b2o.Ui = ctx.ui
    if b2o.UiButton(ui, "Explode") {
        def: b2.ExplosionDef = b2.DefaultExplosionDef()
        def.position = {}
        def.radius = explosion_radius
        def.falloff = explosion_falloff
        def.impulsePerLength = explosion_impulse
        b2.World_Explode(ctx.world, def)
    }
    b2o.UiSlider(ui, "radius", &explosion_radius, 0, 20)
    b2o.UiSlider(ui, "falloff", &explosion_falloff, 0, 20)
    b2o.UiSlider(ui, "impulse", &explosion_impulse, -20, 20)
}

explosion_step :: proc(ctx: ^b2o.SampleContext, dt: f32) {
    if dt > 0 {
        explosion_angle += 60 * math.PI / 180 * dt
        explosion_angle = b2.UnwindAngle(explosion_angle)
        for joint in explosion_joints {
            frame: b2.Transform = b2.Joint_GetLocalFrameA(joint)
            frame.q = b2.MakeRot(explosion_angle)
            b2.Joint_SetLocalFrameA(joint, frame)
        }
    }
}

explosion_draw :: proc(ctx: ^b2o.SampleContext) {
    b2o.ScreenText(ctx, "reference angle = %g", explosion_angle)
    b2o.DrawCircle(ctx, {}, explosion_radius + explosion_falloff, .Box2DBlue)
    b2o.DrawCircle(ctx, {}, explosion_radius, .Box2DYellow)
}

// ------------------------------------------------------------------------------------------------
// Recreate Static: a static shape is recreated every step
// ------------------------------------------------------------------------------------------------

@(private="file") recreate_ground: b2.BodyId

recreate_static_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 2.5}, 3.5)
    b2o.CreateDynamicPolygon(ctx.world, {0, 1}, b2.MakeBox(1, 1), 1)
    recreate_ground = {}
}

recreate_static_step :: proc(ctx: ^b2o.SampleContext, dt: f32) {
    if b2.Body_IsValid(recreate_ground) {
        b2.DestroyBody(recreate_ground)
    }
    recreate_ground = b2.CreateBody(ctx.world, b2.DefaultBodyDef())
    shape_def: b2.ShapeDef = b2.DefaultShapeDef()
    // Invoke contact creation so that contact points are created immediately on a static body
    shape_def.invokeContactCreation = true
    b2o.AddSegment(recreate_ground, {-10, 0}, {10, 0}, shape_def)
}
