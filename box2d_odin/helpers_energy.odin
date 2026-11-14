package box2d_odin

import b2 "vendor:box2d"
import "core:sync"
import "core:testing"

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

// --- Tests ---

@(test)
test_compute_energy :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    world_def: b2.WorldDef = b2.DefaultWorldDef()
    world_def.gravity = {0, -10}
    world: b2.WorldId = b2.CreateWorld(world_def)
    defer b2.DestroyWorld(world)

    // a unit box of density 2 weighs 2 kg, held 5 m high and moving at 3 m/s
    body: b2.BodyId = CreateDynamicPolygon(world, {0, 5}, b2.MakeBox(0.5, 0.5), 2)
    b2.Body_SetLinearVelocity(body, {3, 0})
    linear, angular, potential := ComputeEnergy(world, []b2.BodyId{body})
    testing.expect(t, abs(linear - 9) < 1e-3, "1/2 * 2 * 3^2")
    testing.expect(t, abs(angular) < 1e-6)
    testing.expect(t, abs(potential - 100) < 1e-3, "2 kg * 10 * 5 m")

    b2.Body_SetAngularVelocity(body, 2)
    _, spinning, _ := ComputeEnergy(world, []b2.BodyId{body})
    testing.expect(t, spinning > 0, "a spinning body has rotational energy")

    none_l, none_a, none_p := ComputeEnergy(world, nil)
    testing.expect(t, none_l == 0 && none_a == 0 && none_p == 0)

    tracker: EnergyTracker
    EnergyStart(&tracker, world, []b2.BodyId{body})
    testing.expect(t, tracker.start > 100)
    testing.expect_value(t, tracker.peak, tracker.start)
}
