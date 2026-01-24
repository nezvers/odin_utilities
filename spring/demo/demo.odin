package demo

import rl "vendor:raylib"

import sp ".."

hertz:f32 = 2.0
damping:f32 = 0.8
cached_values:[60 * 4]f32 = {}

params:sp.SpringParams = {
	37.24,	// k - Constant
	0.3,	// m - Mass
	1.7,	// zeta - Damping
	6.0,	// omega - frequency
	sp.SpringCategory.Overdamped,
}

dropdown_text:cstring = "#00#UndampedFrictionless;#00#UnderdampedUnstable;#00#CriticallyDamped;#00#Overdamped"
dropdown_index:i32 = cast(i32)params.category
dropdown_edit:bool

circle_position:rl.Vector2 = 0.0
circle_velocity:rl.Vector2 = {}

calculate_spring::proc(){
	delta_time:: 1.0 / 60
	current_length:f32 = 0
	target_length:f32 = 100
	velocity:f32 = 0
	offset:f32
	new_offset:f32

	for i:int = 0; i < len(cached_values); i += 1 {
		cached_values[i] = current_length
		offset = current_length - target_length
		new_offset = sp.Spring(&params, delta_time, offset, velocity)
		velocity = new_offset - offset
		current_length += velocity
	}
}

game_init :: proc() {
	calculate_spring()
}

update :: proc() {
    delta_time:f32 = rl.GetFrameTime()
	target_position:rl.Vector2 = rl.GetMousePosition()
	offset:rl.Vector2 = circle_position - target_position
	new_offset:rl.Vector2 = {
		sp.Spring(&params, delta_time, offset.x, circle_velocity.x),
		sp.Spring(&params, delta_time, offset.y, circle_velocity.y),
	}
	circle_velocity = new_offset - offset

	circle_position.x = clamp(circle_position.x + circle_velocity.x, 1, cast(f32)rl.GetScreenWidth())
	circle_position.y = clamp(circle_position.y + circle_velocity.y, 1, cast(f32)rl.GetScreenHeight())
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	rl.DrawCircleV(circle_position, 10, rl.PINK)

	draw_graph()
	draw_gui()
    rl.EndDrawing()
}

draw_gui::proc(){
	height_step:f32 = 30
	rect:rl.Rectangle = {100, 10, 500, 25}
	rl.GuiSlider(rect, "Damping", "", &params.zeta, -5, 20)
	
	rect.y += height_step
	rl.GuiSlider(rect, "Hertz", "", &params.omega, 0, 30)
	
	rect.y += height_step
	rl.GuiSlider(rect, "Constant", "", &params.k, 1, 100)
	
	rect.y += height_step
	rl.GuiSlider(rect, "Mass", "", &params.m, 0.1, 10)

	rect.y += height_step
	if rl.GuiDropdownBox(rect, dropdown_text, &dropdown_index, dropdown_edit) {
		dropdown_edit = !dropdown_edit
		if !dropdown_edit {
			params.category = cast(sp.SpringCategory)dropdown_index
			circle_velocity = {}
			calculate_spring()
		}
	}

	rect.x = rect.x + rect.width + 10
	rect.y = 10
	rect.width = 75
	if rl.GuiButton(rect, "Update") {
		circle_velocity = {}
		calculate_spring()
	}
}

draw_graph::proc(){
	origin:rl.Vector2 = {100, 300}
	rl.DrawLineV(origin, {origin.x + len(cached_values), origin.y}, rl.DARKGRAY)

	for i:int = 0; i < len(cached_values) - 1; i += 1 {
		value:f32 = cached_values[i]
		next:f32 = cached_values[i+1]
		from:rl.Vector2 = {origin.x + cast(f32)i, origin.y + value}
		to:rl.Vector2 = {origin.x + cast(f32)i+1, origin.y + next}

		rl.DrawLineV(from, to, rl.WHITE)
	}
}


game_shutdown :: proc() {
    
}
