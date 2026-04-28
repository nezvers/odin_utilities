#+private file
package game

// import "core:fmt"
import tm "../.."
import "../../../karl2d"
import tk "../../karl2d"

@(private="package")
tilemap_grid_state: GameState = {
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
	
    tk.DrawTilemapGrid(&tilemap, karl2d.LIGHT_GRAY)
	tk.DrawTilemapTileId(&tilemap, karl2d.FONT_DEFAULT, 10, karl2d.LIGHT_GRAY)

	mouse_position:Vec2 = karl2d.get_mouse_position()
	mouse_position_i:vec2i = {cast(i32)mouse_position.x, cast(i32)mouse_position.y}
	// Read TileID under mouse position
	tile_id:TileID = tm.TilemapGetTileWorld(&tilemap, mouse_position_i)
	// Draw a cell aligned to grid and ID under mouse
	tk.DrawTilemapCellRect(&tilemap, mouse_position_i, tile_id, karl2d.FONT_DEFAULT, 10, karl2d.GRAY)

	karl2d.draw_text("Draw a tilemap grid", {10, 10}, 20, karl2d.BLACK)
}