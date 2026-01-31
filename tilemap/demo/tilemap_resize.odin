#+private file
package demo

import tm ".."
import tr "../raylib"
import rl "vendor:raylib"

@(private="package")
state_resize:State = {
    nil,
    nil,
    nil,
    draw,
}


draw::proc(){
	// Persistent variables to hold state
	@(static) rect_state:recti
	@(static) selection_state:vec2i
	@(static) temp_buffer:[MAP_SIZE.x * MAP_SIZE.y]TileID

	size_error:bool

	input_selection:InputState = tm.GetInputState(
		rl.IsMouseButtonPressed(rl.MouseButton.LEFT), 
		rl.IsMouseButtonDown(rl.MouseButton.LEFT),
		rl.IsMouseButtonReleased(rl.MouseButton.LEFT),
	)

	if (is_hovering_buttons){
		input_selection = InputState.NONE
		rect_state.w = 0
		rect_state.h = 0
	}

	mouse_position:Vector2 = rl.GetMousePosition()
	mouse_position_i:vec2i = {cast(int)mouse_position.x, cast(int)mouse_position.y}

	if (input_selection != InputState.NONE){
		tm.CreateSelection(&tilemap, mouse_position_i, &selection_state, &rect_state, input_selection)
	}

	rect_area:int = rect_state.w * rect_state.h
	size_error = rect_area > len(tilemap.grid)

	if (input_selection == InputState.RELEASE){
		if (!size_error && rect_area > 0){
			tm.TilemapResize(&tilemap, rect_state, temp_buffer[:])
		}
		rect_state.w = 0
		rect_state.h = 0
	}

	tr.DrawTilemapGrid(&tilemap, rl.LIGHTGRAY)
	skip_zero:bool = true
	tr.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)

	tr.DrawTilemapSelection(&tilemap, rect_state, rl.BLACK)

	rl.DrawText("draw_tilemap_resize: left mouse select, ENTER to resize", 10, 10, 20, rl.BLACK)

	if size_error {
		text:cstring = rl.TextFormat("ERROR: tilemap grid buffer overflow (%d > %d)", rect_area, len(tilemap.grid))
		rl.DrawText(text, 10, 30, 20, rl.RED)
	}
}