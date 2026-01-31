#+private file
package demo

import tm ".."
import tr "../raylib"
import rl "vendor:raylib"
import "core:math"

@(private="package")
state_tile:State = {
    nil,
    nil,
    nil,
    draw,
}

// Example for drawing atlas directly by recreating whole texture
draw::proc(){
	padding:int = 4 + cast(int)(math.sin(get_animation_time(0.2) * math.TAU) * 4.5)
	root_position:Vector2 = {100, 100}
	// 0th id is TILE_EMPTY
	id_offset:int = 1
	for y:int = 0; y < ATLAS_SIZE.y; y += 1 {
		for x:int = 0; x < ATLAS_SIZE.x; x += 1 {
			i:int = x + y * ATLAS_SIZE.x + id_offset
			// Read tiles default 0th ID
			atlas_id:TileID = tm.TileGetId(&tile_list[i])
			draw_pos:Vector2 = {
				root_position.x + cast(f32)(x * (TILE_SIZE.x + padding)), 
				root_position.y + cast(f32)(y * (TILE_SIZE.y + padding)),
			}
			tr.DrawTileAtlas(&tile_atlas, atlas_id, draw_pos, &tileset_texture)
		}
	}

	rl.DrawText("draw_from_tiles: Tile -> TileAtlas", 10, 10, 20, rl.BLACK)
}