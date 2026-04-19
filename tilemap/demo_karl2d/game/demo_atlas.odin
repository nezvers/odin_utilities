#+private file
package game

// import "core:fmt"
import "../../../karl2d"
import "core:math"
import tk "../../karl2d"

@(private="package")
atlas_state: GameState = {
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
	
    padding:i32 = 4 + cast(i32)(math.sin(get_animation_time(0.2) * math.TAU) * 4.5)
	root_position:Vec2 = {100, 100}
	// 0th id is TILE_EMPTY
	id_offset:i32 = 1
	for y:i32 = 0; y < ATLAS_SIZE.y; y += 1 {
		for x:i32 = 0; x < ATLAS_SIZE.x; x += 1 {
			i:i32 = x + y * ATLAS_SIZE.x + id_offset

			atlas_id:TileID = cast(TileID)i
			draw_pos:Vec2 = {
				root_position.x + cast(f32)(x * (TILE_SIZE.x + padding)), 
				root_position.y + cast(f32)(y * (TILE_SIZE.y + padding)),
			}
			tk.DrawTileAtlas(&tile_atlas, atlas_id, draw_pos, &tileset_texture)
		}
	}

	karl2d.draw_text("draw_from_atlas", {10, 10}, 20, karl2d.BLACK)
}