#+private file
package game

// import "core:fmt"
import tm "../.."
import "../../../karl2d"
import tk "../../karl2d"

@(private="package")
tilemap_paint_state: GameState = {
    init,
    finit,
    process,
    draw,
}

init :: proc() {}

finit :: proc() {}

process :: proc() {}

draw :: proc() {
    karl2d.clear(karl2d.WHITE)
	
    @(static) tile_id:TileID = TILE_EMPTY
	@(static) position_state:vec2i
	mouse_position:Vec2 = karl2d.get_mouse_position()
	mouse_position_i:vec2i = {cast(i32)mouse_position.x, cast(i32)mouse_position.y}

	input_paint:InputState = tm.GetInputState(
		karl2d.mouse_button_went_down(.Left), 
		karl2d.mouse_button_is_held(.Left),
		karl2d.mouse_button_went_up(.Left),
	)

	tm.PaintTiles(&tilemap, mouse_position_i, &position_state, tile_id, input_paint )

	// Read TileID under mouse position
	mouse_id:TileID = tm.TilemapGetTileWorld(&tilemap, mouse_position_i)
	
	if mouse_id != TILE_INVALID {
		// Active while inside tilemap
		wheel:i32 = cast(i32)karl2d.get_mouse_wheel_delta()
		max_tiles:TileID = cast(TileID)(ATLAS_SIZE.x * ATLAS_SIZE.y + 1)
		if wheel > 0 {
			tile_id = ((tile_id + 1) % max_tiles)
		}
		if wheel < 0 {
			tile_id = ((tile_id - 1 + max_tiles) % max_tiles)
		}
		
		if karl2d.mouse_button_went_down(.Right){
			// Copy TileID under mouse
			tile_id = mouse_id
		}
	}
		
	// Don't draw TILE_EMPTY ID
	skip_zero:bool = true
	tk.DrawTilemapGrid(&tilemap, karl2d.LIGHT_GRAY)
	tk.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)

	if mouse_id != TILE_INVALID {
		// Draw a cell aligned to grid and ID under mouse
		tk.DrawTilemapCellRect(&tilemap, mouse_position_i, tile_id, karl2d.FONT_DEFAULT, 10, karl2d.GRAY)

	}

	karl2d.draw_text("left mouse draw, right mouse copy, mouse scroll change ID", {10, 10}, 20, karl2d.BLACK)
}