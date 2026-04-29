#+private file
package game

// import "core:fmt"
import tm "../.."
import "../../../karl2d"
import tm_glue "../../karl2d"

@(private="package")
tilemap_state: GameState = {
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
	
    skip_zero:bool = true
	tm_glue.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)

	karl2d.draw_text("Draw a tilemap", {10, 10}, 20, karl2d.BLACK)
}