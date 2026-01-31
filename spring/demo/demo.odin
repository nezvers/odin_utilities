package demo

import "core:reflect"
import "core:strings"

import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
Color :: rl.Color


// DEMO STATES
State :: struct {
	enter : proc(),
	exit : proc(),
	update : proc(),
	draw : proc(),
}

state_list: []State = {
	state_inertia_spring,
	state_box2d,
}

StateIndex :: enum {
	INERTIA_SPRING,
	BOX2D_SPRING_DAMPER,
	COUNT,
}

state_index:StateIndex = StateIndex.INERTIA_SPRING
screen_size:Vector2
is_hovering_buttons:bool

button_names:[StateIndex.COUNT]cstring

state_change :: proc(index:StateIndex){
	if state_list[state_index].exit != nil{
		state_list[state_index].exit()
	}
	state_index = index
	if state_list[state_index].enter != nil{
		state_list[state_index].enter()
	}
}

game_init :: proc() {
	for i:int; i < cast(int)StateIndex.COUNT; i += 1{
		name, _: = reflect.enum_name_from_value(cast(StateIndex)i)
		button_names[i] = strings.clone_to_cstring(name)
	}
	state_change(state_index)
	screen_size = {cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}
}

update :: proc() {
	if rl.IsWindowResized() {
		screen_size = {cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}
	}
	if state_list[state_index].update != nil{
		state_list[state_index].update()
	}
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	if state_list[state_index].draw != nil{
		state_list[state_index].draw()
	}

	// GUI BUTTONS
	BUTTON_SIZE: Vector2: {150, 20}
	BUTTON_PADDING :f32: 2
	button_rect:Rectangle = {screen_size.x - BUTTON_SIZE.x - 10, 10, BUTTON_SIZE.x, BUTTON_SIZE.y}
	mouse_position:Vector2 = rl.GetMousePosition()
	
	is_hovering_buttons = false
	for i:int; i < cast(int)StateIndex.COUNT; i += 1{
		if (rl.GuiButton(button_rect, button_names[i])){
			state_change(cast(StateIndex)i)
		}
		if (rl.CheckCollisionPointRec(mouse_position, button_rect)){
			is_hovering_buttons = true
		}
		button_rect.y += BUTTON_SIZE.y + BUTTON_PADDING
	}
	
    rl.EndDrawing()
}

game_shutdown :: proc() {
    if state_list[state_index].exit != nil{
		state_list[state_index].exit()
	}
}
