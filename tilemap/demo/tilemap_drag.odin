#+private file
package demo

import tm ".."
import tr "../raylib"
import rl "vendor:raylib"

@(private="package")
state_drag:State = {
    nil,
    nil,
    nil,
    draw,
}


draw::proc(){
	// Persistent variables to hold state
	@(static) selection_state:vec2i
	@(static) drag_pos_state:vec2i
	@(static) map_pos_state:vec2i
	@(static) rect_state:recti
	@(static) temp_tilemap:Tilemap = {}
	@(static) temp_buffer:[MAP_SIZE.x * MAP_SIZE.y]TileID

	input_selection:InputState = tm.GetInputState(
		rl.IsMouseButtonPressed(rl.MouseButton.LEFT), 
		rl.IsMouseButtonDown(rl.MouseButton.LEFT),
		rl.IsMouseButtonReleased(rl.MouseButton.LEFT),
	)

	input_drag:InputState = tm.GetInputState(
		rl.IsMouseButtonPressed(rl.MouseButton.RIGHT), 
		rl.IsMouseButtonDown(rl.MouseButton.RIGHT),
		rl.IsMouseButtonReleased(rl.MouseButton.RIGHT),
	)

	if (rect_state.w == 0 || rect_state.h == 0){
		// no drag without selection
		input_drag = InputState.NONE
	}
	
	mouse_position:Vector2 = rl.GetMousePosition()
	mouse_position_i:vec2i = {cast(i32)mouse_position.x, cast(i32)mouse_position.y}
	

	if (input_drag != InputState.NONE){
		write_empty:bool = rl.IsKeyDown(rl.KeyboardKey.LEFT_ALT) || rl.IsKeyDown(rl.KeyboardKey.RIGHT_ALT)
		remove_source:bool = rl.IsKeyDown(rl.KeyboardKey.LEFT_CONTROL) || rl.IsKeyDown(rl.KeyboardKey.RIGHT_CONTROL)
		
		tm.DragTiles(
			&tilemap,
			&temp_tilemap,
			mouse_position_i,
			&drag_pos_state,
			&map_pos_state,
			&rect_state,
			input_drag,
			remove_source,
			write_empty,
			temp_buffer[:],
		)

		// Don't allow to change selection
		if (input_selection != InputState.NONE){
			input_selection = InputState.NONE
		}
	}

	if (input_selection != InputState.NONE){
		tm.CreateSelection(&tilemap, mouse_position_i, &selection_state, &rect_state, input_selection)
	}

	tr.DrawTilemapGrid(&tilemap, rl.LIGHTGRAY)
	skip_zero:bool = true
	tr.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)
	if(temp_tilemap.size.x != 0 && rect_state.w != 0){
		temp_rect:recti = tm.TilemapRecti(&temp_tilemap)
		tr.DrawTilemapSelection(&temp_tilemap, temp_rect, rl.GRAY)
		tr.DrawTilemap(&temp_tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)
	}

	tr.DrawTilemapSelection(&tilemap, rect_state, rl.BLACK)

	rl.DrawText("draw_tilemap_drag: left mouse select, right mouse drag, hold CTRL to remove source, ALT to write empty tiles", 10, 10, 20, rl.BLACK)
}