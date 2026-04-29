#+private file
package game

// import "core:fmt"
import tm "../.."
import "../../../karl2d"
import tm_glue "../../karl2d"

@(private="package")
tilemap_region_state: GameState = {
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
	
    mouse_position:Vec2 = karl2d.get_mouse_position()
	mouse_position_i:vec2i = {cast(i32)mouse_position.x, cast(i32)mouse_position.y}
	// Translate position to tile coordinates
	tile_position:vec2i = tm.TilemapGetWorld2Tile(&tilemap, mouse_position_i)
	region:recti = {tile_position.x - 5, tile_position.y - 4, 5, 4}
	// Don't draw TILE_EMPTY ID
	skip_zero:bool = true

	tm_glue.DrawTilemapGrid(&tilemap, karl2d.LIGHT_GRAY)
	// Draw only tiles inside region
	tm_glue.DrawTilemapRecti(&tilemap, &tileset, &tile_atlas, skip_zero, tm_glue.TileRandType.NONE, region, &tileset_texture)
	// Draw rectangle around tiles
	tm_glue.DrawTilemapSelection(&tilemap, region, karl2d.GRAY)

	karl2d.draw_text("Reveal tiles with rectangle", {10, 10}, 20, karl2d.BLACK)
}