#+private file
package demo

import tm ".."
import tr "../raylib"
import rl "vendor:raylib"

@(private="package")
state_grid:State = {
    nil,
    nil,
    nil,
    draw,
}


draw::proc(){
	tr.DrawTilemapGrid(&tilemap, rl.LIGHTGRAY)
	tr.DrawTilemapTileId(&tilemap, rl.GetFontDefault(), 10, rl.LIGHTGRAY)

	mouse_position:Vector2 = rl.GetMousePosition()
	mouse_position_i:vec2i = {cast(int)mouse_position.x, cast(int)mouse_position.y}
	// Read TileID under mouse position
	tile_id:TileID = tm.TilemapGetTileWorld(&tilemap, mouse_position_i)
	// Draw a cell aligned to grid and ID under mouse
	tr.DrawTilemapCellRect(&tilemap, mouse_position_i, tile_id, rl.GetFontDefault(), 10, rl.GRAY)

	rl.DrawText("draw_tilemap_grid: display as grid and IDs", 10, 10, 20, rl.BLACK)
}