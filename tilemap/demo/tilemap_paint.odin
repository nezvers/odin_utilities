#+private file
package demo

import tm ".."
import tr "../raylib"
import rl "vendor:raylib"

@(private="package")
state_paint:State = {
    nil,
    nil,
    nil,
    draw,
}

// NOTE: tilemap/editing.odin has PaintTiles funcionality example
draw::proc(){
	@(static) tile_id:TileID = TILE_EMPTY
	@(static) position_state:vec2i
	mouse_position:Vector2 = rl.GetMousePosition()
	mouse_position_i:vec2i = {cast(i32)mouse_position.x, cast(i32)mouse_position.y}

	input_paint:InputState = tm.GetInputState(
		rl.IsMouseButtonPressed(rl.MouseButton.LEFT), 
		rl.IsMouseButtonDown(rl.MouseButton.LEFT),
		rl.IsMouseButtonReleased(rl.MouseButton.LEFT),
	)

	tm.PaintTiles(&tilemap, mouse_position_i, &position_state, tile_id, input_paint )

	// Read TileID under mouse position
	mouse_id:TileID = tm.TilemapGetTileWorld(&tilemap, mouse_position_i)
	
	if mouse_id != TILE_INVALID {
		// Active while inside tilemap
		wheel:i32 = cast(i32)rl.GetMouseWheelMove()
		max_tiles:TileID = cast(TileID)(ATLAS_SIZE.x * ATLAS_SIZE.y + 1)
		if wheel > 0 {
			tile_id = ((tile_id + 1) % max_tiles)
		}
		if wheel < 0 {
			tile_id = ((tile_id - 1 + max_tiles) % max_tiles)
		}
		
		if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT){
			// Copy TileID under mouse
			tile_id = mouse_id
		}
	}
		
	// Don't draw TILE_EMPTY ID
	skip_zero:bool = true
	tr.DrawTilemapGrid(&tilemap, rl.LIGHTGRAY)
	tr.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)

	if mouse_id != TILE_INVALID {
		// Draw a cell aligned to grid and ID under mouse
		tr.DrawTilemapCellRect(&tilemap, mouse_position_i, tile_id, rl.GetFontDefault(), 10, rl.GRAY)

	}

	rl.DrawText("draw_tilemap_paint: left mouse draw, right mouse copy, mouse scroll change ID", 10, 10, 20, rl.BLACK)
}