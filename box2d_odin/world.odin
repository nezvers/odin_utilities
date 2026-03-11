package box2d_odin

// based on - https://github.com/moomerman/odin-karl2d-box2d-platformer/blob/main/src/world.odin

import b2 "vendor:box2d"
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
