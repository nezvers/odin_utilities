// Port of box2d/samples/sample_restitution.cpp
package box2d_samples

import "core:math"
import b2 "vendor:box2d"
import b2o ".."

@(init)
register_restitution :: proc "contextless" () {
    b2o.RegisterSample({category = "Restitution", name = "Varying", create = varying_create, draw = varying_draw, controls = varying_controls})
    b2o.RegisterSample({category = "Restitution", name = "Single Box Restitution", create = single_box_r_create, draw = single_box_r_draw})
    b2o.RegisterSample({category = "Restitution", name = "Single Circle Restitution", create = single_circle_r_create, draw = single_circle_r_draw})
    b2o.RegisterSample({category = "Restitution", name = "Circle Stack Restitution", create = circle_stack_r_create, draw = circle_stack_r_draw, controls = circle_stack_r_controls})
    b2o.RegisterSample({category = "Restitution", name = "Restitution Propagation", create = propagation_create, draw = propagation_draw, controls = propagation_controls})
    b2o.RegisterSample({category = "Restitution", name = "Box Restitution", create = box_r_create, draw = box_r_draw, controls = box_r_controls})
    b2o.RegisterSample({category = "Restitution", name = "Rotated Box Restitution", create = rotated_box_create, draw = rotated_box_draw, controls = rotated_box_controls})
    b2o.RegisterSample({category = "Restitution", name = "Two Box Restitution", create = two_box_create, draw = two_box_draw})
    b2o.RegisterSample({category = "Restitution", name = "Circle Restitution", create = circle_r_create})
}

// ------------------------------------------------------------------------------------------------
// Varying: restitution is approximate since Box2D uses speculative collision
// ------------------------------------------------------------------------------------------------

VARYING_COUNT :: 40

@(private="file") varying_bodies: [VARYING_COUNT]b2.BodyId
@(private="file") varying_shape_type: i32

varying_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {4, 17}, 27.5)
    h: f32 = 1 * VARYING_COUNT
    b2o.CreateGroundSegment(ctx.world, {-h, 0}, {h, 0})
    varying_shape_type = 0
    varying_bodies = {}
    varying_create_bodies(ctx)
}

@(private="file")
varying_create_bodies :: proc(ctx: ^b2o.SampleContext) {
    for &body in varying_bodies {
        if b2.Body_IsValid(body) { b2.DestroyBody(body) }
        body = {}
    }

    shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, 0, 0)
    dr: f32 = 1.0 / f32(VARYING_COUNT - 1)
    x: f32 = -1.0 * f32(VARYING_COUNT - 1)
    for i in 0..<VARYING_COUNT {
        body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {x, 40})
        varying_bodies[i] = body
        if varying_shape_type == 0 {
            b2o.AddCircle(body, 0.5, def = shape_def)
        } else {
            b2o.AddBox(body, 0.5, 0.5, shape_def)
        }
        shape_def.material.restitution += dr
        x += 2
    }
}

varying_controls :: proc(ctx: ^b2o.SampleContext) {
    changed: bool = b2o.UiSelect(ctx.ui, {"Circle", "Box"}, &varying_shape_type)
    changed |= b2o.UiButton(ctx.ui, "Reset")
    if changed { varying_create_bodies(ctx) }
}

varying_draw :: proc(ctx: ^b2o.SampleContext) {
    h: f32 = 1 * VARYING_COUNT
    b2o.DrawLine(ctx, {-h, 40.5}, {h, 40.5}, .Red)
}

// ------------------------------------------------------------------------------------------------
// Single Box Restitution
// ------------------------------------------------------------------------------------------------

@(private="file") single_r_body: b2.BodyId
@(private="file") single_r_max_y: f32
@(private="file") single_r_height: f32
@(private="file") single_r_energy: b2o.EnergyTracker

single_box_r_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 5}, 8)
    b2o.CreateGroundSegment(ctx.world, {-4, 0}, {4, 0})
    single_r_height = 5
    single_r_max_y = 5

    shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, 0, 1)
    shape_def.enableHitEvents = true
    body_def: b2.BodyDef = b2.DefaultBodyDef()
    body_def.type = .dynamicBody
    body_def.position = {0, single_r_height}
    body_def.safetyFactor = 0.01
    single_r_body = b2.CreateBody(ctx.world, body_def)
    b2o.AddBox(single_r_body, 0.5, 0.5, shape_def)

    bodies: [1]b2.BodyId = {single_r_body}
    b2o.EnergyStart(&single_r_energy, ctx.world, bodies[:])
}

single_box_r_draw :: proc(ctx: ^b2o.SampleContext) {
    b2o.DrawLine(ctx, {-4, single_r_height + 0.5}, {4, single_r_height + 0.5}, .Red)
    events: b2.ContactEvents = b2.World_GetContactEvents(ctx.world)
    p: Vec2 = b2.Body_GetPosition(single_r_body)
    single_r_max_y = p.y if events.hitCount == 1 else max(single_r_max_y, p.y)
    b2o.ScreenText(ctx, "maxY = %.2f", single_r_max_y)
    bodies: [1]b2.BodyId = {single_r_body}
    b2o.EnergyText(ctx, &single_r_energy, bodies[:])
}

// ------------------------------------------------------------------------------------------------
// Single Circle Restitution
// ------------------------------------------------------------------------------------------------

single_circle_r_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 5}, 8)
    b2o.CreateGroundSegment(ctx.world, {-4, 0}, {4, 0})

    shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, 0, 1)
    shape_def.enableHitEvents = true
    body_def: b2.BodyDef = b2.DefaultBodyDef()
    body_def.type = .dynamicBody
    body_def.position = {0, 10}
    body_def.safetyFactor = 0.01
    single_r_body = b2.CreateBody(ctx.world, body_def)
    b2o.AddCircle(single_r_body, 0.5, def = shape_def)
    single_r_max_y = body_def.position.y

    bodies: [1]b2.BodyId = {single_r_body}
    b2o.EnergyStart(&single_r_energy, ctx.world, bodies[:])
}

single_circle_r_draw :: proc(ctx: ^b2o.SampleContext) {
    events: b2.ContactEvents = b2.World_GetContactEvents(ctx.world)
    p: Vec2 = b2.Body_GetPosition(single_r_body)
    single_r_max_y = p.y if events.hitCount == 1 else max(single_r_max_y, p.y)
    b2o.DrawLine(ctx, {-4, 10.5}, {4, 10.5}, .Red)
    b2o.ScreenText(ctx, "maxY = %.2f", single_r_max_y)
    bodies: [1]b2.BodyId = {single_r_body}
    b2o.EnergyText(ctx, &single_r_energy, bodies[:])
}

// ------------------------------------------------------------------------------------------------
// Circle Stack Restitution, similar to MeasureSupportedBounce unit test
// ------------------------------------------------------------------------------------------------

CIRCLE_STACK_IMPACT_SPEED :: 5.0
CIRCLE_STACK_MAX :: 3

@(private="file") cs_bodies: [CIRCLE_STACK_MAX + 1]b2.BodyId
@(private="file") cs_body_count: int
@(private="file") cs_impactor: b2.BodyId
@(private="file") cs_stack_count: i32
@(private="file") cs_restitution: f32
@(private="file") cs_start_height: f32
@(private="file") cs_coefficient: f32
@(private="file") cs_gravity, cs_latched, cs_hit: bool
@(private="file") cs_energy: b2o.EnergyTracker

circle_stack_r_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 2.5}, 6)
    ground: b2.BodyId = b2o.CreateBodyAt(ctx.world, .staticBody, {0, -1})
    b2o.AddBox(ground, 40, 1, b2o.MakeShapeDef(1, 0, 0))

    cs_body_count = 0
    cs_stack_count = 2
    cs_restitution = 1
    cs_gravity = false
    circle_stack_r_scene(ctx)
}

@(private="file")
circle_stack_r_ball :: proc(ctx: ^b2o.SampleContext, y: f32, velocity_y: f32, restitution: f32, hit_events: bool) -> b2.BodyId {
    body_def: b2.BodyDef = b2.DefaultBodyDef()
    body_def.type = .dynamicBody
    body_def.position = {0, y}
    body_def.linearVelocity = {0, velocity_y}
    body_def.enableSleep = false
    body: b2.BodyId = b2.CreateBody(ctx.world, body_def)
    shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, 0, restitution)
    shape_def.enableHitEvents = hit_events
    b2o.AddCircle(body, 0.5, def = shape_def)
    return body
}

@(private="file")
circle_stack_r_scene :: proc(ctx: ^b2o.SampleContext) {
    for i in 0..<cs_body_count {
        b2.DestroyBody(cs_bodies[i])
    }
    cs_body_count = 0

    b2.World_SetGravity(ctx.world, {0, -10} if cs_gravity else {})

    for i in 0..<int(cs_stack_count) {
        cs_bodies[cs_body_count] = circle_stack_r_ball(ctx, 0.5 + 1 * f32(i), 0, 0, false)
        cs_body_count += 1
    }

    // Start half a step of travel above contact so the impact lands mid step, matching the test
    cs_start_height = 0.5 + 1 * f32(cs_stack_count) + 0.5 * CIRCLE_STACK_IMPACT_SPEED * (1.0 / 60.0)
    cs_impactor = circle_stack_r_ball(ctx, cs_start_height, -CIRCLE_STACK_IMPACT_SPEED, cs_restitution, true)
    cs_bodies[cs_body_count] = cs_impactor
    cs_body_count += 1

    b2o.EnergyStart(&cs_energy, ctx.world, cs_bodies[:cs_body_count])
    cs_coefficient = 0
    cs_latched = false
    cs_hit = false
}

circle_stack_r_controls :: proc(ctx: ^b2o.SampleContext) {
    ui: ^b2o.Ui = ctx.ui
    rebuild: bool = b2o.UiSlider(ui, "Restitution", &cs_restitution, 0, 1)
    rebuild |= b2o.UiSliderInt(ui, "Stack", &cs_stack_count, 0, CIRCLE_STACK_MAX)
    rebuild |= b2o.UiCheckbox(ui, "Gravity", &cs_gravity)
    rebuild |= b2o.UiButton(ui, "Reset")
    if rebuild { circle_stack_r_scene(ctx) }
}

circle_stack_r_draw :: proc(ctx: ^b2o.SampleContext) {
    events: b2.ContactEvents = b2.World_GetContactEvents(ctx.world)
    if events.hitCount > 0 { cs_hit = true }

    vy: f32 = b2.Body_GetLinearVelocity(cs_impactor).y
    // The rebound only means something once the impact has happened and the impactor is leaving
    if !cs_latched && cs_hit && vy > 0 {
        cs_coefficient = vy / CIRCLE_STACK_IMPACT_SPEED
        cs_latched = true
    }

    support_speed: f32
    for i in 0..<int(cs_stack_count) {
        support_speed = max(support_speed, b2.Length(b2.Body_GetLinearVelocity(cs_bodies[i])))
    }

    b2o.DrawLine(ctx, {-2, cs_start_height}, {2, cs_start_height}, .Red)
    b2o.ScreenText(ctx, "impactor vy = %.3f m/s", vy)
    b2o.ScreenText(ctx, "coefficient = %.4f live (target %.2f)", vy / CIRCLE_STACK_IMPACT_SPEED, cs_restitution)
    if cs_latched {
        b2o.ScreenText(ctx, "coefficient = %.4f at first rebound", cs_coefficient)
    }
    b2o.ScreenText(ctx, "support speed = %.4f m/s", support_speed)
    b2o.EnergyText(ctx, &cs_energy, cs_bodies[:cs_body_count])
}

// ------------------------------------------------------------------------------------------------
// Restitution Propagation: a bouncy ball landing on a resting body
// ------------------------------------------------------------------------------------------------

PROPAGATION_COLUMNS :: 3
PROPAGATION_DROP_HEIGHT :: 5.0

@(private="file") prop_bodies: [2 * PROPAGATION_COLUMNS]b2.BodyId
@(private="file") prop_balls: [PROPAGATION_COLUMNS]b2.BodyId
@(private="file") prop_crates: [PROPAGATION_COLUMNS]b2.BodyId
@(private="file") prop_rest_height: [PROPAGATION_COLUMNS]f32
@(private="file") prop_apex: [PROPAGATION_COLUMNS]f32
@(private="file") prop_rebounding, prop_done: [PROPAGATION_COLUMNS]bool
@(private="file") prop_body_count, prop_crate_count: int
@(private="file") prop_restitution: f32
@(private="file") prop_kick: f32

propagation_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 4}, 10)
    ground: b2.BodyId = b2o.CreateBodyAt(ctx.world, .staticBody, {0, -1})
    b2o.AddBox(ground, 40, 1, b2o.MakeShapeDef(1, 0.6))
    prop_body_count = 0
    prop_restitution = 0.9
    propagation_scene(ctx)
}

@(private="file")
propagation_scene :: proc(ctx: ^b2o.SampleContext) {
    for i in 0..<prop_body_count {
        b2.DestroyBody(prop_bodies[i])
    }
    prop_body_count = 0
    prop_crate_count = 0
    prop_kick = 0

    for column in 0..<PROPAGATION_COLUMNS {
        x: f32 = 4 * f32(column - 1)
        for k in 0..<column {
            body_def: b2.BodyDef = b2.DefaultBodyDef()
            body_def.type = .dynamicBody
            body_def.position = {x, 0.5 + 1 * f32(k)}
            body_def.enableSleep = false
            crate: b2.BodyId = b2.CreateBody(ctx.world, body_def)
            b2o.AddBox(crate, 0.5, 0.5)
            prop_bodies[prop_body_count] = crate
            prop_body_count += 1
            prop_crates[prop_crate_count] = crate
            prop_crate_count += 1
        }

        prop_rest_height[column] = 0.5 + 1 * f32(column)
        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.type = .dynamicBody
        body_def.position = {x, prop_rest_height[column] + PROPAGATION_DROP_HEIGHT}
        body_def.enableSleep = false
        ball: b2.BodyId = b2.CreateBody(ctx.world, body_def)
        shape_def: b2.ShapeDef = b2.DefaultShapeDef()
        shape_def.material.restitution = prop_restitution
        b2o.AddCircle(ball, 0.5, def = shape_def)
        prop_bodies[prop_body_count] = ball
        prop_body_count += 1
        prop_balls[column] = ball
        prop_apex[column] = 0
        prop_rebounding[column] = false
        prop_done[column] = false
    }
}

propagation_controls :: proc(ctx: ^b2o.SampleContext) {
    rebuild: bool = b2o.UiSlider(ctx.ui, "Restitution", &prop_restitution, 0, 1)
    rebuild |= b2o.UiButton(ctx.ui, "Reset")
    if rebuild { propagation_scene(ctx) }
}

propagation_draw :: proc(ctx: ^b2o.SampleContext) {
    labels: [PROPAGATION_COLUMNS]string = {"ground", "one crate", "two crates"}
    for column in 0..<PROPAGATION_COLUMNS {
        v: Vec2 = b2.Body_GetLinearVelocity(prop_balls[column])
        height: f32 = b2.Body_GetPosition(prop_balls[column]).y - prop_rest_height[column]

        // The first rebound apex: the ball starts at rest and falls, so upward velocity means it bounced
        if !prop_rebounding[column] && v.y > 0 {
            prop_rebounding[column] = true
        }
        if prop_rebounding[column] && !prop_done[column] {
            prop_apex[column] = max(prop_apex[column], height)
            if v.y < 0 { prop_done[column] = true }
        }

        x: f32 = 4 * f32(column - 1)
        b2o.DrawLine(ctx, {x - 1, prop_rest_height[column] + PROPAGATION_DROP_HEIGHT}, {x + 1, prop_rest_height[column] + PROPAGATION_DROP_HEIGHT}, .Red)
        if prop_apex[column] > 0 {
            b2o.DrawLine(ctx, {x - 1, prop_rest_height[column] + prop_apex[column]}, {x + 1, prop_rest_height[column] + prop_apex[column]}, .Green)
        }
        b2o.ScreenText(ctx, "%s: apex %.2f m (%.0f%% of drop)", labels[column], prop_apex[column], 100 * prop_apex[column] / PROPAGATION_DROP_HEIGHT)
    }
    for i in 0..<prop_crate_count {
        prop_kick = max(prop_kick, b2.Length(b2.Body_GetLinearVelocity(prop_crates[i])))
    }
    b2o.ScreenText(ctx, "peak crate speed %.2f m/s", prop_kick)
}

// ------------------------------------------------------------------------------------------------
// Box Restitution, similar to MeasureFlatBounce and SpinTest unit tests
// ------------------------------------------------------------------------------------------------

BOX_R_IMPACT_SPEED :: 5.0

@(private="file") box_r_body: b2.BodyId
@(private="file") box_r_restitution: f32
@(private="file") box_r_spin: f32
@(private="file") box_r_coefficient: f32
@(private="file") box_r_latched, box_r_hit: bool
@(private="file") box_r_energy: b2o.EnergyTracker

box_r_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 8}, 10)
    // Gravity would bias the measured coefficient
    b2.World_SetGravity(ctx.world, {})
    ground: b2.BodyId = b2o.CreateBodyAt(ctx.world, .staticBody, {0, -1})
    b2o.AddBox(ground, 40, 1, b2o.MakeShapeDef(1, 0, 0))

    box_r_body = {}
    box_r_restitution = 0.9
    box_r_spin = 0
    box_r_scene(ctx)
}

@(private="file")
box_r_scene :: proc(ctx: ^b2o.SampleContext) {
    if b2.Body_IsValid(box_r_body) { b2.DestroyBody(box_r_body) }

    body_def: b2.BodyDef = b2.DefaultBodyDef()
    body_def.type = .dynamicBody
    body_def.position = {0, 0.25 + 0.5 * BOX_R_IMPACT_SPEED * (1.0 / 60.0)}
    body_def.linearVelocity = {0, -BOX_R_IMPACT_SPEED}
    body_def.angularVelocity = box_r_spin
    body_def.enableSleep = false
    box_r_body = b2.CreateBody(ctx.world, body_def)

    shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, 0, box_r_restitution)
    shape_def.enableHitEvents = true
    b2o.AddBox(box_r_body, 1, 0.25, shape_def)

    bodies: [1]b2.BodyId = {box_r_body}
    b2o.EnergyStart(&box_r_energy, ctx.world, bodies[:])
    box_r_coefficient = 0
    box_r_latched = false
    box_r_hit = false
}

box_r_controls :: proc(ctx: ^b2o.SampleContext) {
    rebuild: bool = b2o.UiSlider(ctx.ui, "Restitution", &box_r_restitution, 0, 1)
    rebuild |= b2o.UiSlider(ctx.ui, "Spin", &box_r_spin, 0, 2)
    rebuild |= b2o.UiButton(ctx.ui, "Reset")
    if rebuild { box_r_scene(ctx) }
}

box_r_draw :: proc(ctx: ^b2o.SampleContext) {
    events: b2.ContactEvents = b2.World_GetContactEvents(ctx.world)
    if events.hitCount > 0 { box_r_hit = true }

    vy: f32 = b2.Body_GetLinearVelocity(box_r_body).y
    w: f32 = b2.Body_GetAngularVelocity(box_r_body)
    if !box_r_latched && box_r_hit && vy > 0 {
        box_r_coefficient = vy / BOX_R_IMPACT_SPEED
        box_r_latched = true
    }

    b2o.DrawPoint(ctx, b2.Body_GetWorldPoint(box_r_body, {-1, -0.25}), 8, .Yellow)
    b2o.DrawPoint(ctx, b2.Body_GetWorldPoint(box_r_body, {1, -0.25}), 8, .Yellow)

    b2o.ScreenText(ctx, "vy = %.3f m/s", vy)
    b2o.ScreenText(ctx, "coefficient = %.4f live (target %.2f)", vy / BOX_R_IMPACT_SPEED, box_r_restitution)
    if box_r_latched {
        b2o.ScreenText(ctx, "coefficient = %.4f at first rebound", box_r_coefficient)
    }
    b2o.ScreenText(ctx, "spin in = %.2f, spin out = %.4f (ideal %.2f at e = 1)", box_r_spin, w, -box_r_spin)
    bodies: [1]b2.BodyId = {box_r_body}
    b2o.EnergyText(ctx, &box_r_energy, bodies[:])
}

// ------------------------------------------------------------------------------------------------
// Rotated Box Restitution
// ------------------------------------------------------------------------------------------------

ROTATED_COUNT :: 12
ROTATED_DROP_HEIGHT :: 10.0

@(private="file") rotated_bodies: [ROTATED_COUNT]b2.BodyId
@(private="file") rotated_start_energy: [ROTATED_COUNT]f32
@(private="file") rotated_restitution, rotated_friction, rotated_safety: f32

rotated_box_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 4}, 14)
    h: f32 = 2 * ROTATED_COUNT + 1
    b2o.CreateGroundSegment(ctx.world, {-h, 0}, {h, 0})
    rotated_bodies = {}
    rotated_restitution = 0.9
    rotated_friction = 0
    rotated_safety = 0.5
    rotated_box_scene(ctx)
}

@(private="file")
rotated_box_scene :: proc(ctx: ^b2o.SampleContext) {
    for &body in rotated_bodies {
        if b2.Body_IsValid(body) { b2.DestroyBody(body) }
        body = {}
    }

    shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, rotated_friction, rotated_restitution)
    // Boxes in a negative group never collide with each other.
    shape_def.filter.groupIndex = -1

    // A square repeats every quarter turn
    dq: f32 = 0.5 * math.PI / ROTATED_COUNT
    x: f32 = -1.0 * f32(ROTATED_COUNT - 1)
    for i in 0..<ROTATED_COUNT {
        body_def: b2.BodyDef = b2.DefaultBodyDef()
        body_def.type = .dynamicBody
        body_def.safetyFactor = rotated_safety
        body_def.position = {x, ROTATED_DROP_HEIGHT}
        body_def.rotation = b2.MakeRot(f32(i) * dq)
        rotated_bodies[i] = b2.CreateBody(ctx.world, body_def)
        b2o.AddBox(rotated_bodies[i], 0.5, 0.5, shape_def)

        bodies: [1]b2.BodyId = {rotated_bodies[i]}
        linear, angular, potential: = b2o.ComputeEnergy(ctx.world, bodies[:])
        rotated_start_energy[i] = linear + angular + potential
        x += 2
    }
}

rotated_box_controls :: proc(ctx: ^b2o.SampleContext) {
    ui: ^b2o.Ui = ctx.ui
    rebuild: bool = b2o.UiSlider(ui, "Restitution", &rotated_restitution, 0, 1)
    rebuild |= b2o.UiSlider(ui, "Friction", &rotated_friction, 0, 1)
    rebuild |= b2o.UiSlider(ui, "Safety Factor", &rotated_safety, 0.01, 0.5)
    rebuild |= b2o.UiButton(ui, "Reset")
    if rebuild { rotated_box_scene(ctx) }
}

rotated_box_draw :: proc(ctx: ^b2o.SampleContext) {
    h: f32 = 1 * ROTATED_COUNT
    b2o.DrawLine(ctx, {-h, ROTATED_DROP_HEIGHT + 0.5}, {h, ROTATED_DROP_HEIGHT + 0.5}, .Red)

    min_percent, max_percent: f32
    x: f32 = -1.0 * f32(ROTATED_COUNT - 1)
    for i in 0..<ROTATED_COUNT {
        bodies: [1]b2.BodyId = {rotated_bodies[i]}
        linear, angular, potential: = b2o.ComputeEnergy(ctx.world, bodies[:])
        total: f32 = linear + angular + potential
        percent: f32 = 100 * total / rotated_start_energy[i] if rotated_start_energy[i] != 0 else 0
        min_percent = percent if i == 0 else min(min_percent, percent)
        max_percent = percent if i == 0 else max(max_percent, percent)
        b2o.DrawString(ctx, {x - 0.5, ROTATED_DROP_HEIGHT + 1.5}, .White, "%.1f%%", percent)
        x += 2
    }
    b2o.ScreenText(ctx, "energy: min %.2f%%, max %.2f%% of start", min_percent, max_percent)
}

// ------------------------------------------------------------------------------------------------
// Two Box Restitution, based on https://github.com/erincatto/box2d/discussions/957
// ------------------------------------------------------------------------------------------------

@(private="file") two_box_bodies: [2]b2.BodyId
@(private="file") two_box_energy: b2o.EnergyTracker

two_box_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 3}, 5)
    b2o.CreateGroundSegment(ctx.world, {-10, 0}, {10, 0})

    shape_def: b2.ShapeDef = b2.DefaultShapeDef()
    shape_def.material.restitution = 0.9
    box: b2.Polygon = b2.MakeSquare(0.5)

    two_box_bodies[0] = b2o.CreateBodyAt(ctx.world, .dynamicBody, {0, 0.5})
    b2o.AddPolygon(two_box_bodies[0], box, shape_def)
    two_box_bodies[1] = b2o.CreateBodyAt(ctx.world, .dynamicBody, {0.1, 6})
    b2o.AddPolygon(two_box_bodies[1], box, shape_def)

    b2o.EnergyStart(&two_box_energy, ctx.world, two_box_bodies[:])
}

two_box_draw :: proc(ctx: ^b2o.SampleContext) {
    b2o.EnergyText(ctx, &two_box_energy, two_box_bodies[:])
}

// ------------------------------------------------------------------------------------------------
// Circle Restitution
// ------------------------------------------------------------------------------------------------

circle_r_create :: proc(ctx: ^b2o.SampleContext) {
    b2o.SetCamera(ctx, {0, 5}, 10)
    count :: 10
    h: f32 = 2 * count
    b2o.CreateGroundSegment(ctx.world, {-h, 0}, {h, 0})

    shape_def: b2.ShapeDef = b2o.MakeShapeDef(1, 0.6, 0)
    dr: f32 = 1.0 / f32(count - 1)
    x: f32 = -1.0 * f32(count - 1)
    for _ in 0..<count {
        for y in ([2]f32{1, 4}) {
            body: b2.BodyId = b2o.CreateBodyAt(ctx.world, .dynamicBody, {x, y})
            b2o.AddCircle(body, 0.5, def = shape_def)
        }
        shape_def.material.restitution += dr
        x += 2
    }
}
