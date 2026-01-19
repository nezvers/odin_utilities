package demo
// Based on Karl Zylinski's template - https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template

import geometry2d ".."
import rl "vendor:raylib"

// import geometry2d ".."
Line :: geometry2d.Line
Circle :: geometry2d.Circle
Rect :: geometry2d.Rect
Triangle :: geometry2d.Triangle
Ray :: geometry2d.Ray
vec2 :: geometry2d.vec2

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
	state_tests,
	state_draw_shapes,
	state_project,
}

StateIndex :: enum {
	TESTS,
	DRAW_SHAPES,
	PROJECT,
	COUNT,
}
state_index:StateIndex = StateIndex.PROJECT

button_names:[]cstring = {
	"TESTS",
	"DRAW_SHAPES",
	"PROJECT",
}

screen_size:Vector2
is_hovering_buttons:bool

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
	if state_list[state_index].enter != nil{
		state_list[state_index].enter()
	}
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

	BUTTON_SIZE: Vector2: {150, 20}
	BUTTON_PADDING :f32: 2
	button_rect:Rectangle = {screen_size.x - BUTTON_SIZE.x, 0, BUTTON_SIZE.x, BUTTON_SIZE.y}
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

draw_lines::proc(slice:[]rl.Vector2){
	LINE_COUNT:= len(slice)-1
	for i in 0..< LINE_COUNT {
		rl.DrawLineV(slice[i], slice[i+1], rl.WHITE)
	}
}


game_shutdown :: proc() {
	if state_list[state_index].exit != nil{
		state_list[state_index].exit()
	}
}
