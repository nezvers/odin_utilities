package box2d_odin

import b2 "vendor:box2d"

// Kinetic (linear + angular) and potential energy of bodies, used by the restitution samples
ComputeEnergy :: proc(world: b2.WorldId, bodies: []b2.BodyId) -> (linear: f32, angular: f32, potential: f32) {
    gravity: Vec2 = b2.World_GetGravity(world)
    for body in bodies {
        mass_data: b2.MassData = b2.Body_GetMassData(body)
        v: Vec2 = b2.Body_GetLinearVelocity(body)
        w: f32 = b2.Body_GetAngularVelocity(body)
        linear += 0.5 * mass_data.mass * b2.Dot(v, v)
        angular += 0.5 * mass_data.rotationalInertia * w * w
        potential -= mass_data.mass * b2.Dot(gravity, b2.Body_GetWorldCenter(body))
    }
    return
}

// Energy tracking that prints the same three lines as the C++ samples
EnergyTracker :: struct {
    start: f32,
    peak: f32,
}

EnergyStart :: proc(tracker: ^EnergyTracker, world: b2.WorldId, bodies: []b2.BodyId) {
    linear, angular, potential: = ComputeEnergy(world, bodies)
    tracker.start = linear + angular + potential
    tracker.peak = tracker.start
}

EnergyText :: proc(ctx: ^SampleContext, tracker: ^EnergyTracker, bodies: []b2.BodyId) {
    linear, angular, potential: = ComputeEnergy(ctx.world, bodies)
    total: f32 = linear + angular + potential
    tracker.peak = max(tracker.peak, total)
    scale: f32 = 100 / tracker.start if tracker.start != 0 else 0
    ScreenText(ctx, "kinetic   = %.3f J linear + %.3f J angular", linear, angular)
    ScreenText(ctx, "potential = %.3f J", potential)
    ScreenText(ctx, "total     = %.3f J (%.2f%% of start, peak %.2f%%)", total, scale * total, scale * tracker.peak)
}
