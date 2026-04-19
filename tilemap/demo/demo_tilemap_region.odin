#+private file
package demo

import tm ".."
import tr "../raylib"
import rl "vendor:raylib"

@(private="package")
state_region:State = {
    nil,
    nil,
    nil,
    draw,
}


draw::proc(){
	mouse_position:Vector2 = rl.GetMousePosition()
	mouse_position_i:vec2i = {cast(i32)mouse_position.x, cast(i32)mouse_position.y}
	// Translate position to tile coordinates
	tile_position:vec2i = tm.TilemapGetWorld2Tile(&tilemap, mouse_position_i)
	region:recti = {tile_position.x - 5, tile_position.y - 4, 5, 4}
	// Don't draw TILE_EMPTY ID
	skip_zero:bool = true

	tr.DrawTilemapGrid(&tilemap, rl.LIGHTGRAY)
	// Draw only tiles inside region
	tr.DrawTilemapRecti(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, region, &tileset_texture)
	// Draw rectangle around tiles
	tr.DrawTilemapSelection(&tilemap, region, rl.GRAY)

	rl.DrawText("draw_tilemap_region: reveal tiles with rectangle", 10, 10, 20, rl.BLACK)
}