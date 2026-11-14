package box2d_odin

// based on - https://github.com/moomerman/odin-karl2d-box2d-platformer/blob/main/src/world.odin

import b2 "vendor:box2d"
import "core:sync"
import "core:testing"
// import "core:log"

WorldContext :: struct {
    world: b2.WorldId,
    time: f32,
    units_per_meter:f32,
    sensor_begin_callback : proc(event: b2.SensorBeginTouchEvent),
    sensor_end_callback : proc(event: b2.SensorEndTouchEvent),
	debug_draw: b2.DebugDraw,
}

WorldInit :: proc(
	ctx: ^WorldContext,
	units_per_meter:f32,
	gravity: b2.Vec2 = b2.Vec2{0, -1200},
	sensor_begin_callback: proc(event: b2.SensorBeginTouchEvent) = nil,
	sensor_end_callback: proc(event: b2.SensorEndTouchEvent) = nil,
) {
	b2.SetLengthUnitsPerMeter(units_per_meter)
	world_def := b2.DefaultWorldDef()
	world_def.gravity = gravity
	ctx.world = b2.CreateWorld(world_def)
	ctx.time = 0
	ctx.sensor_begin_callback = sensor_begin_callback
	ctx.sensor_end_callback = sensor_end_callback
}

WorldDebug :: proc(ctx: ^WorldContext) {
	b2.World_Draw(ctx.world, &ctx.debug_draw)
}

WorldFinit :: proc(ctx: ^WorldContext) {
	ctx.time = 0.0
	b2.DestroyWorld(ctx.world)
}

WorldUpdate :: proc(ctx: ^WorldContext, delta_time:f32) {
	PHYSICS_TIME_STEP :: 1.0 / 60
	SUB_STEPS :: 12
	stepped := false

    ctx.time += delta_time
	for ctx.time >= PHYSICS_TIME_STEP {
		b2.World_Step(ctx.world, PHYSICS_TIME_STEP, SUB_STEPS)
		ctx.time -= PHYSICS_TIME_STEP
		stepped = true
	}
	if !stepped {return}

	sensor_events := b2.World_GetSensorEvents(ctx.world)

	if sensor_events.beginCount > 0 && ctx.sensor_begin_callback != nil {
		begin_events := sensor_events.beginEvents[:sensor_events.beginCount]
		for event in begin_events {
            ctx.sensor_begin_callback(event)
        }
	}
	if sensor_events.endCount > 0 && ctx.sensor_end_callback != nil {
		end_events := sensor_events.endEvents[:sensor_events.endCount]
		for event in end_events {
            ctx.sensor_end_callback(event)
        }
	}
}

// --- Tests ---

@(private="file", thread_local)
sensor_begin_count: int
@(private="file", thread_local)
sensor_end_count: int

@(test)
test_world_steps_in_fixed_slices :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    ctx: WorldContext
    WorldInit(&ctx, 1, {0, -10})
    defer WorldFinit(&ctx)
    body: b2.BodyId = CreateBody(&ctx, {0, 0}, {10, 10}, .dynamicBody)
    CreateShapeBox(body, {10, 10}, 1)
    start: b2.Vec2 = b2.Body_GetPosition(body)

    WorldUpdate(&ctx, 0.005)                                                               // less than one slice: nothing is simulated
    testing.expect_value(t, b2.Body_GetPosition(body), start)
    WorldUpdate(&ctx, 0.005)
    testing.expect_value(t, b2.Body_GetPosition(body), start)
    WorldUpdate(&ctx, 0.01)                                                                // the leftover adds up to a full 1/60 s slice
    testing.expect(t, b2.Body_GetPosition(body).y < start.y, "gravity pulls it down")

    for _ in 0 ..< 60 { WorldUpdate(&ctx, 1.0 / 60) }
    testing.expect(t, b2.Body_GetPosition(body).y < start.y - 4, "after a second it fell about five metres")
}

@(test)
test_world_reports_sensor_events :: proc(t: ^testing.T) {
    sync.guard(&test_box2d_lock)
    sensor_begin_count = 0
    sensor_end_count = 0
    ctx: WorldContext
    WorldInit(&ctx, 1, {0, 0},
        proc(event: b2.SensorBeginTouchEvent) { sensor_begin_count += 1 },
        proc(event: b2.SensorEndTouchEvent) { sensor_end_count += 1 })
    defer WorldFinit(&ctx)

    zone: b2.BodyId = CreateBody(&ctx, {0, 0}, {40, 40}, .staticBody)
    CreateShapeBox(zone, {40, 40}, 1, isSensor = true, enableSensorEvents = true)
    visitor: b2.BodyId = CreateBody(&ctx, {10, 10}, {10, 10}, .dynamicBody)
    CreateShapeBox(visitor, {10, 10}, 2, enableSensorEvents = true)

    for _ in 0 ..< 5 { WorldUpdate(&ctx, 1.0 / 60) }
    testing.expect_value(t, sensor_begin_count, 1)
    testing.expect_value(t, sensor_end_count, 0)

    BodyLinearVelocity(visitor, {0, 0})
    b2.Body_SetTransform(visitor, {500, 500}, b2.MakeRot(0))                              // leaves the zone
    for _ in 0 ..< 5 { WorldUpdate(&ctx, 1.0 / 60) }
    testing.expect_value(t, sensor_end_count, 1)
}
