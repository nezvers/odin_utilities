package demo

import sp ".."
import rl "vendor:raylib"

state_maddhattpatt:State = {
    init_maddhattpatt,
    nil,
    update_maddhattpatt,
    draw_maddhattpatt,
}

params:sp.SpringParams = {
	37.24,	// k - Constant
	0.3,	// m - Mass
	1.7,	// zeta - Damping
	6.0,	// omega - frequency
	sp.SpringCategory.Overdamped,
}

init_maddhattpatt::proc(){
	circle_velocity = {}
	circle_position = {}
}

calculate_maddhattpatt_spring::proc(){
	delta_time:: 1.0 / 60
	current_length:f32 = 0
	target_length:f32 = 100
	velocity:f32 = 0
	offset:f32
	new_offset:f32

	for i:int = 0; i < len(cached_values); i += 1 {
		cached_values[i] = current_length
		offset = current_length - target_length
		new_offset = sp.SpringMaddHattPatt(&params, delta_time, offset, velocity)
		velocity = new_offset - offset
		current_length += velocity
	}
}

update_maddhattpatt :: proc() {
    delta_time:f32 = rl.GetFrameTime()
	target_position:rl.Vector2 = rl.GetMousePosition()
	offset:rl.Vector2 = circle_position - target_position
	new_offset:rl.Vector2 = {
		sp.SpringMaddHattPatt(&params, delta_time, offset.x, circle_velocity.x),
		sp.SpringMaddHattPatt(&params, delta_time, offset.y, circle_velocity.y),
	}
	circle_velocity = new_offset - offset

	circle_position.x = clamp(circle_position.x + circle_velocity.x, 1, cast(f32)rl.GetScreenWidth())
	circle_position.y = clamp(circle_position.y + circle_velocity.y, 1, cast(f32)rl.GetScreenHeight())
}

draw_maddhattpatt::proc(){
    rl.DrawCircleV(circle_position, 10, rl.PINK)

	draw_graph_maddhattpatt ()
	draw_gui_maddhattpatt ()
}

draw_gui_maddhattpatt ::proc(){
	@(static) dropdown_text:cstring = "#00#UndampedFrictionless;#00#UnderdampedUnstable;#00#CriticallyDamped;#00#Overdamped"
	@(static) dropdown_index:i32
	@(static) dropdown_edit:bool

	dropdown_index = cast(i32)params.category

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
			calculate_maddhattpatt_spring()
		}
	}

	rect.x = rect.x + rect.width + 10
	rect.y = 10
	rect.width = 75
	if rl.GuiButton(rect, "Update") {
		circle_velocity = {}
		calculate_maddhattpatt_spring()
	}
}

draw_graph_maddhattpatt ::proc(){
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