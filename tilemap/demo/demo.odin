package demo

// import "core:fmt"
import rl "vendor:raylib"


state_list: []State = {
	state_atlas,
	state_tile,
	state_tileset,
	state_tilemap,
	state_grid,
	state_region,
	state_paint,
	state_drag,
	state_resize,
	state_ruletile,
}

Example :: enum {
	ATLAS,
	TILE,
	TILESET,
	TILEMAP,
	TILEMAP_GRID,
	TILEMAP_REGION,
	TILEMAP_PAINT,
	TILEMAP_DRAG,
	TILEMAP_RESIZE,
	RULETILE_PAINT,
	COUNT,
}
current_example:Example = Example.ATLAS

example_names:[]cstring = {
	"Atlas",
	"Tile",
	"Tileset",
	"Tilemap",
	"Tilemap Grid",
	"Tilemap Show Region",
	"Tilemap Painting",
	"Tilemap Dragging",
	"Tilemap Resizing",
	"Ruletile Painting",
}

screen_size:Vector2
is_hovering_buttons:bool

game_init :: proc() {
	tileset_texture = rl.LoadTexture("../assets/textures/tileset_template.png")
	// demo_common.odin
	create_tiles()
	create_tilemap()

	screen_size = {cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}
	// Init default state
	state_change(current_example)
}

game_shutdown :: proc() {
	rl.UnloadTexture(tileset_texture)
}

update :: proc() {
	if state_list[current_example].update != nil{
		state_list[current_example].update()
	}
	if rl.IsWindowResized() {
		screen_size = {cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}
	}
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.RAYWHITE)

	if state_list[current_example].draw != nil{
		state_list[current_example].draw()
	}

	BUTTON_SIZE: Vector2: {150, 20}
	BUTTON_PADDING :f32: 2
	button_rect:Rectangle = {screen_size.x - BUTTON_SIZE.x, 0, BUTTON_SIZE.x, BUTTON_SIZE.y}
	mouse_position:Vector2 = rl.GetMousePosition()
	is_hovering_buttons = false
	for i:int; i < cast(int)Example.COUNT; i += 1{
		if (rl.GuiButton(button_rect, example_names[i])){
			state_change(cast(Example)i)
		}
		if (rl.CheckCollisionPointRec(mouse_position, button_rect)){
			is_hovering_buttons = true
		}
		button_rect.y += BUTTON_SIZE.y + BUTTON_PADDING
	}

	if (rl.GuiButton(button_rect, "RESET")){
		create_tilemap()
	}

    rl.EndDrawing()
}

