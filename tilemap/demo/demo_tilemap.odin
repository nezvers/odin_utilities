#+private file
package demo

import tm ".."
import tm_glue "../raylib"
import rl "vendor:raylib"

@(private="package")
state_tilemap:State = {
    nil,
    nil,
    nil,
    draw,
}


draw::proc(){
	skip_zero:bool = true

	tm_glue.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)

	rl.DrawText("draw_from_tilemap: Tilemap -> Tileset -> Tile -> TileAtlas", 10, 10, 20, rl.BLACK)
}