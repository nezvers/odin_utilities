// Port of box2d/samples/sample_stacking.cpp
package box2d_samples

import "core:math"
import b2 "vendor:box2d"
import b2o ".."

@(init)
register_stacking :: proc "contextless" () {
    b2o.RegisterSample({category = "Stacking", name = "Single Box", create = single_box_create, draw = single_box_draw})
    b2o.RegisterSample({category = "Stacking", name = "Tilted Stack", create = tilted_stack_create})
    b2o.RegisterSample({category = "Stacking", name = "Vertical Stack", create = vertical_stack_create, controls = vertical_stack_controls, keyboard = vertical_stack_keyboard})
    b2o.RegisterSample({category = "Stacking", name = "Circle Stack", create = circle_stack_create, draw = circle_stack_draw})
    b2o.RegisterSample({category = "Stacking", name = "Capsule Stack", create = capsule_stack_create})
    b2o.RegisterSample({category = "Stacking", name = "Cliff", create = cliff_create, controls = cliff_controls})
    b2o.RegisterSample({category = "Stacking", name = "Arch", create = arch_create})
    b2o.RegisterSample({category = "Stacking", name = "Double Domino", create = double_domino_create})
    b2o.RegisterSample({category = "Stacking", name = "Confined", create = confined_create})
    b2o.RegisterSample({category = "Stacking", name = "Card House", create = card_house_create})
}

// ------------------------------------------------------------------------------------------------
// Single Box
// ------------------------------------------------------------------------------------------------

@(private="file") single_box_body: b2.BodyId

single_box_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 2.5}, 3.5)
    extent: f32 = 1
    ground_width: f32 = 66 * extent
    b2o.CreateGroundSegment(ctx.world, {-0.5 * 2 * ground_width, 0}, {0.5 * 2 * ground_width, 0})

    body_def: b2.BodyDef = b2.DefaultBodyDef()
    body_def.type = .dynamicBody
    body_def.position = {0, 1}
    body_def.linearVelocity = {5, 0}
    single_box_body = b2.CreateBody(ctx.world, body_def)
    b2o.AddBox(single_box_body, extent, extent)
}

single_box_draw :: proc(ctx: ^b2o.SampleContext) {
    position: Vec2 = b2.Body_GetPosition(single_box_body)
    b2o.ScreenText(ctx, "(x, y) = (%.2g, %.2g)", position.x, position.y)
}

// ------------------------------------------------------------------------------------------------
// Tilted Stack
// ------------------------------------------------------------------------------------------------

tilted_stack_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {7.5, 7.5}, 20)
    b2o.CreateStaticBox(ctx.world, {0, -1}, {1000, 1})

    columns :: 10
    rows :: 10
    box: b2.Polygon = b2.MakeRoundedBox(0.45, 0.45, 0.05)
    shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, 0.3)

    offset: f32 = 0.2
    dx: f32 = 5
    x_root: f32 = -0.5 * dx * (columns - 1)
    for j in 0..<columns {
        x: f32 = x_root + f32(j) * dx
        for i in 0..<rows {
            body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {x + offset * f32(i), 0.5 + 1 * f32(i)})
            b2o.AddPolygon(body, box, shape_def)
        }
    }
}

// ------------------------------------------------------------------------------------------------
// Vertical Stack: bullet dynamic bodies and prevention of chain reaction tunneling.
// Try disabling continuous collision and firing a bullet.
// ------------------------------------------------------------------------------------------------

VERTICAL_MAX_COLUMNS :: 10
VERTICAL_MAX_ROWS :: 160
VERTICAL_MAX_BULLETS :: 8

@(private="file") vertical_bodies: [VERTICAL_MAX_ROWS * VERTICAL_MAX_COLUMNS]b2.BodyId
@(private="file") vertical_bullets: [VERTICAL_MAX_BULLETS]b2.BodyId
@(private="file") vertical_shape_type: i32       // 0 circle, 1 box
@(private="file") vertical_bullet_type: i32
@(private="file") vertical_rows, vertical_columns, vertical_bullet_count: i32

vertical_stack_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {-7, 9}, 14)
    ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())
    b2o.AddSegment(ground, {10, 0}, {10, 80})
    b2o.AddSegment(ground, {-100, 0}, {100, 0})

    vertical_bodies = {}
    vertical_bullets = {}
    vertical_shape_type = 1
    vertical_rows = 12
    vertical_columns = 1
    vertical_bullet_count = 1
    vertical_bullet_type = 0
    vertical_create_stacks(ctx)
}

@(private="file")
vertical_create_stacks :: proc(ctx: ^b2o.SampleContext) {
    for &body in vertical_bodies {
        if b2.Body_IsValid(body) {
            b2.DestroyBody(body)
        }
        body = {}
    }

    box: b2.Polygon = b2.MakeRoundedBox(0.45, 0.45, 0.05)
    shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, 0.3)
    offset: f32 = 0 if vertical_shape_type == 0 else 0.01
    dx: f32 = -3
    x_root: f32 = 8

    for j in 0..<int(vertical_columns) {
        x: f32 = x_root + f32(j) * dx
        for i in 0..<int(vertical_rows) {
            shift: f32 = -offset if i % 2 == 0 else offset
            body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {x + shift, 0.5 + 1 * f32(i)})
            vertical_bodies[j * int(vertical_rows) + i] = body
            if vertical_shape_type == 0 {
                b2o.AddCircle(body, 0.5, def = shape_def)
            } else {
                b2o.AddPolygon(body, box, shape_def)
            }
        }
    }
}

@(private="file")
vertical_destroy_bullets :: proc() {
    for &bullet in vertical_bullets {
        if b2.Body_IsValid(bullet) {
            b2.DestroyBody(bullet)
        }
        bullet = {}
    }
}

@(private="file")
vertical_fire_bullets :: proc(ctx: ^b2o.SampleContext) {
    shape_def: b2.ShapeDef = b2o.MakeShapeDef(4)
    for i in 0..<int(vertical_bullet_count) {
        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.type = .dynamicBody
        body_def.position = {-26.7 - f32(i), 6}
        speed: f32 = b2o.RandomFloatRange(200, 300)
        body_def.linearVelocity = {speed, 0}
        body_def.isBullet = true
        bullet: b2.BodyId = b2.CreateBody(ctx.world, body_def)
        if vertical_bullet_type == 1 {
            b2o.AddBox(bullet, 0.25, 0.25, shape_def)
        } else {
            b2o.AddCircle(bullet, 0.25, def = shape_def)
        }
        vertical_bullets[i] = bullet
    }
}

vertical_stack_keyboard :: proc(ctx: ^b2o.SampleContext, key: b2o.Key) {
    if key == .B {
        vertical_fire_bullets(ctx)
    }
}

vertical_stack_controls :: proc(ctx: ^b2o.SampleContext) {
    ui: ^b2o.Ui = ctx.ui
    changed: bool

    b2o.UiLabel(ui, "Shape")
    changed |= b2o.UiSelect(ui, {"Circle", "Box"}, &vertical_shape_type)
    changed |= b2o.UiSliderInt(ui, "Rows", &vertical_rows, 1, VERTICAL_MAX_ROWS)
    changed |= b2o.UiSliderInt(ui, "Columns", &vertical_columns, 1, VERTICAL_MAX_COLUMNS)
    b2o.UiSliderInt(ui, "Bullets", &vertical_bullet_count, 1, VERTICAL_MAX_BULLETS)
    b2o.UiLabel(ui, "Bullet Shape")
    b2o.UiSelect(ui, {"Circle", "Box"}, &vertical_bullet_type)

    if b2o.UiButton(ui, "Fire Bullets (B)") {
        vertical_destroy_bullets()
        vertical_fire_bullets(ctx)
    }
    if b2o.UiButton(ui, "Destroy Body") {
        for j in 0..<int(vertical_columns) {
            for i in 0..<int(vertical_rows) {
                n: int = j * int(vertical_rows) + i
                if b2.Body_IsValid(vertical_bodies[n]) {
                    b2.DestroyBody(vertical_bodies[n])
                    vertical_bodies[n] = {}
                    break
                }
            }
        }
    }
    changed |= b2o.UiButton(ui, "Reset Stack")
    if changed {
        vertical_destroy_bullets()
        vertical_create_stacks(ctx)
    }
}

// ------------------------------------------------------------------------------------------------
// Circle Stack: also shows how to collect hit events
// ------------------------------------------------------------------------------------------------

@(private="file") circle_events: [256][2]i32
@(private="file") circle_event_count: int

circle_stack_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 5}, 6)
    circle_event_count = 0
    shape_index: uintptr = 0

    ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())
    ground_def: b2.ShapeDef = b2.DefaultShapeDef()
    ground_def.userData = rawptr(shape_index)
    shape_index += 1
    b2o.AddSegment(ground, {-10, 0}, {10, 0}, ground_def)

    b2.World_SetGravity(ctx.world, {0, -20})
    b2.World_SetContactTuning(ctx.world, 0.25 * 360, 10, 3)

    shape_def: b2.ShapeDef = b2.DefaultShapeDef()
    shape_def.enableHitEvents = true
    shape_def.material.friction = 0
    shape_def.material.restitution = 0.8

    y: f32 = 0.75
    for i in 0..<4 {
        body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {0, y})
        shape_def.userData = rawptr(shape_index)
        shape_def.density = 1 + 4 * f32(i)
        shape_index += 1
        b2o.AddCircle(body, 0.5, def = shape_def)
        y += 1.25
    }
}

circle_stack_draw :: proc(ctx: ^b2o.SampleContext) {
    events: b2.ContactEvents = b2.World_GetContactEvents(ctx.world)
    for event in events.hitEvents[:events.hitCount] {
        index_a: i32 = i32(uintptr(b2.Shape_GetUserData(event.shapeIdA)))
        index_b: i32 = i32(uintptr(b2.Shape_GetUserData(event.shapeIdB)))
        b2o.DrawPoint(ctx, event.point, 10, .White)
        if circle_event_count < len(circle_events) {
            circle_events[circle_event_count] = {index_a, index_b}
            circle_event_count += 1
        }
    }
    for i in 0..<min(circle_event_count, 30) {
        b2o.ScreenText(ctx, "%d, %d", circle_events[i].x, circle_events[i].y)
    }
}

// ------------------------------------------------------------------------------------------------
// Capsule Stack
// ------------------------------------------------------------------------------------------------

capsule_stack_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 5}, 6)
    b2o.CreateStaticBox(ctx.world, {0, -1}, {10, 1})

    a: f32 = 0.25
    y: f32 = 2 * a
    for _ in 0..<20 {
        body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {0, y})
        b2o.AddCapsule(body, {-4 * a, 0}, {4 * a, 0}, a)
        y += 3 * a
    }
}

// ------------------------------------------------------------------------------------------------
// Cliff
// ------------------------------------------------------------------------------------------------

@(private="file") cliff_bodies: [9]b2.BodyId
@(private="file") cliff_flip: bool

cliff_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 5}, 12.5)

    ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())
    b2o.AddPolygon(ground, b2.MakeOffsetBox(100, 1, {0, -1}, b2.Rot{1, 0}))
    b2o.AddSegment(ground, {-14, 4}, {-8, 4})
    b2o.AddPolygon(ground, b2.MakeOffsetBox(3, 0.5, {0, 4}, b2.Rot{1, 0}))
    b2o.AddCapsule(ground, {8.5, 4}, {13.5, 4}, 0.5)

    cliff_flip = false
    cliff_bodies = {}
    cliff_create_bodies(ctx)
}

@(private="file")
cliff_create_bodies :: proc(ctx: ^b2o.SampleContext) {
    for &body in cliff_bodies {
        if b2.Body_IsValid(body) { b2.DestroyBody(body) }
        body = {}
    }

    sign: f32 = -1 if cliff_flip else 1
    square: b2.Polygon = b2.MakeSquare(0.5)

    spawn :: proc(ctx: ^b2o.SampleContext, index: int, position: Vec2, velocity: Vec2, friction: f32, kind: int, square: b2.Polygon) {
        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.type = .dynamicBody
        body_def.position = position
        body_def.linearVelocity = velocity
        cliff_bodies[index] = b2.CreateBody(ctx.world, body_def)
        shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, friction)
        switch kind {
        case 0: b2o.AddCapsule(cliff_bodies[index], {-0.25, 0}, {0.25, 0}, 0.25, shape_def)
        case 1: b2o.AddPolygon(cliff_bodies[index], square, shape_def)
        case 2: b2o.AddCircle(cliff_bodies[index], 0.5, def = shape_def)
        }
    }

    offset: f32 = -4 if cliff_flip else 0
    spawn(ctx, 0, {-9 + offset, 4.25}, {2 * sign, 0}, 0.01, 0, square)
    spawn(ctx, 1, {2 + offset, 4.75}, {2 * sign, 0}, 0.01, 0, square)
    spawn(ctx, 2, {13 + offset, 4.75}, {2 * sign, 0}, 0.01, 0, square)

    spawn(ctx, 3, {-11, 4.5}, {2.5 * sign, 0}, 0.01, 1, square)
    spawn(ctx, 4, {0, 5}, {2.5 * sign, 0}, 0.01, 1, square)
    spawn(ctx, 5, {11, 5}, {2.5 * sign, 0}, 0.01, 1, square)

    offset = 4 if cliff_flip else 0
    spawn(ctx, 6, {-13 + offset, 4.5}, {1.5 * sign, 0}, 0.2, 2, square)
    spawn(ctx, 7, {-2 + offset, 5}, {1.5 * sign, 0}, 0.2, 2, square)
    spawn(ctx, 8, {9 + offset, 5}, {1.5 * sign, 0}, 0.2, 2, square)
}

cliff_controls :: proc(ctx: ^b2o.SampleContext) {
    if b2o.UiButton(ctx.ui, "Flip") {
        cliff_flip = !cliff_flip
        cliff_create_bodies(ctx)
    }
}

// ------------------------------------------------------------------------------------------------
// Arch
// ------------------------------------------------------------------------------------------------

arch_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 8}, 8.75)

    ps1: [9]Vec2 = {
        {16, 0},
        {14.93803712795643, 5.133601056842984},
        {13.79871746027416, 10.24928069555078},
        {12.56252963284711, 15.34107019122473},
        {11.20040987372525, 20.39856541571217},
        {9.66521217819836, 25.40369899225096},
        {7.87179930638133, 30.3179337000085},
        {5.635199558196225, 35.03820717801641},
        {2.405937953536585, 39.09554102558315},
    }
    ps2: [9]Vec2 = {
        {24, 0},
        {22.33619528222415, 6.02299846205841},
        {20.54936888969905, 12.00964361211476},
        {18.60854610798073, 17.9470321677465},
        {16.46769273811807, 23.81367936585418},
        {14.05325025774858, 29.57079353071012},
        {11.23551045834022, 35.13775818285372},
        {7.752568160730571, 40.30450679009583},
        {3.016931552701656, 44.28891593799322},
    }

    scale: f32 = 0.25
    for i in 0..<9 {
        ps1[i] *= scale
        ps2[i] *= scale
    }

    shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, 0.6)
    ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())
    b2o.AddSegment(ground, {-100, 0}, {100, 0}, shape_def)

    add_hull :: proc(world: b2.WorldId, points: []Vec2, shape_def: b2.ShapeDef) {
        body: b2.BodyId = b2o.CreateBodyAt(world, .dynamicBody, {0, 0})
        hull: b2.Hull = b2.ComputeHull(points)
        b2o.AddPolygon(body, b2.MakePolygon(hull, 0), shape_def)
    }

    for i in 0..<8 {
        ps: [4]Vec2 = {ps1[i], ps2[i], ps2[i + 1], ps1[i + 1]}
        add_hull(ctx.world, ps[:], shape_def)
    }
    for i in 0..<8 {
        ps: [4]Vec2 = {{-ps2[i].x, ps2[i].y}, {-ps1[i].x, ps1[i].y}, {-ps1[i + 1].x, ps1[i + 1].y}, {-ps2[i + 1].x, ps2[i + 1].y}}
        add_hull(ctx.world, ps[:], shape_def)
    }
    {
        ps: [4]Vec2 = {ps1[8], ps2[8], {-ps2[8].x, ps2[8].y}, {-ps1[8].x, ps1[8].y}}
        add_hull(ctx.world, ps[:], shape_def)
    }

    for i in 0..<4 {
        body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {0, 0.5 + ps2[8].y + 1 * f32(i)})
        b2o.AddBox(body, 2, 0.5, shape_def)
    }
}

// ------------------------------------------------------------------------------------------------
// Double Domino
// ------------------------------------------------------------------------------------------------

double_domino_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 4}, 6.25)
    b2o.CreateStaticBox(ctx.world, {0, -1}, {100, 1})

    shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, 0.6)
    count :: 15
    x: f32 = -0.5 * count
    for i in 0..<count {
        body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {x, 0.5})
        b2o.AddBox(body, 0.125, 0.5, shape_def)
        if i == 0 {
            b2.Body_ApplyLinearImpulse(body, {0.2, 0}, {x, 1}, true)
        }
        x += 1
    }
}

// ------------------------------------------------------------------------------------------------
// Confined
// ------------------------------------------------------------------------------------------------

confined_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 10}, 12.5)
    ground: b2.BodyId = b2.CreateBody(ctx.world, b2.DefaultBodyDef())
    b2o.AddCapsule(ground, {-10.5, 0}, {10.5, 0}, 0.5)
    b2o.AddCapsule(ground, {-10.5, 0}, {-10.5, 20.5}, 0.5)
    b2o.AddCapsule(ground, {10.5, 0}, {10.5, 20.5}, 0.5)
    b2o.AddCapsule(ground, {-10.5, 20.5}, {10.5, 20.5}, 0.5)

    grid_count :: 25
    max_count :: grid_count * grid_count
    column, count: int
    for count < max_count {
        row: int = 0
        for _ in 0..<grid_count {
            x: f32 = -8.75 + f32(column) * 18 / grid_count
            y: f32 = 1.5 + f32(row) * 18 / grid_count
            body_def: b2.BodyDef = b2.DefaultBodyDef()
            body_def.type = .dynamicBody
            body_def.gravityScale = 0
            body_def.position = {x, y}
            body: b2.BodyId = b2.CreateBody(ctx.world, body_def)
            b2o.AddCircle(body, 0.5)
            count += 1
            row += 1
        }
        column += 1
    }
}

// ------------------------------------------------------------------------------------------------
// Card House (from PEEL)
// ------------------------------------------------------------------------------------------------

card_house_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0.75, 0.9}, 1.25)
    shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, 0.7)
    ground: b2.BodyId = b2o.CreateBodyAt(ctx.world, .staticBody, {0, -2})
    b2o.AddPolygon(ground, b2.MakeBox(40, 2), shape_def)

    card_height: f32 = 0.2
    card_thickness: f32 = 0.001
    angle0: f32 = 25 * math.PI / 180
    angle1: f32 = -25 * math.PI / 180
    angle2: f32 = 0.5 * math.PI
    card_box: b2.Polygon = b2.MakeBox(card_thickness, card_height)

    add_card :: proc(world: b2.WorldId, position: Vec2, angle: f32, box: b2.Polygon, shape_def: b2.ShapeDef) {
        body: b2.BodyId = b2o.CreateBodyAt(world, .dynamicBody, position, angle)
        b2o.AddPolygon(body, box, shape_def)
    }

    nb: int = 5
    z0: f32 = 0
    y: f32 = card_height - 0.02
    for nb > 0 {
        z: f32 = z0
        for i in 0..<nb {
            if i != nb - 1 {
                add_card(ctx.world, {z + 0.25, y + card_height - 0.015}, angle2, card_box, shape_def)
            }
            add_card(ctx.world, {z, y}, angle1, card_box, shape_def)
            z += 0.175
            add_card(ctx.world, {z, y}, angle0, card_box, shape_def)
            z += 0.175
        }
        y += card_height * 2 - 0.03
        z0 += 0.175
        nb -= 1
    }
}
