#+private file
package game

// import "core:fmt"
import tm "../.."
import "../../../karl2d"
import tm_glue "../../karl2d"

@(private="package")
tilemap_dualgrid_state: GameState = {
    init,
    finit,
    process,
    draw,
}

// Translated from Karl2D example

// Maps a bitmask to a coordinate within the tileset. The bits mean:
// Bit 4: Top-left neighbor exists
// Bit 3: Top-right neighbor exists
// Bit 2: Bottom-right neighbor exists
// Bit 1: Bottom-left neighbor exists
//
// Look at how the `tileset_path.png` looks in order to better understand why we map to these
// specific coordinates.
DUAL_GRID_MASK_TO_TXTY := [16][2]int {
	{0, 3}, // 0000
	{3, 3}, // 0001
	{0, 2}, // 0010
	{1, 2}, // 0011
	{1, 3}, // 0100
	{0, 1}, // 0101
	{1, 0}, // 0110
	{2, 2}, // 0111
	{0, 0}, // 1000
	{3, 2}, // 1001
	{2, 3}, // 1010
	{3, 1}, // 1011
	{3, 0}, // 1100
	{2, 0}, // 1101
	{1, 1}, // 1110
	{2, 1}, // 1111
}

TILE_GRASS:TileID: 0
TILE_ROAD:TileID: 1
tilemap_dualgrid_buffer: [MAP_SIZE.x * MAP_SIZE.y]TileID

init :: proc() {}

finit :: proc() {}

process :: proc() {}

draw :: proc() {
    karl2d.clear(karl2d.WHITE)
	
    skip_zero:bool = true
	tm_glue.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)

	karl2d.draw_text("Draw a dualgrid", {10, 10}, 20, karl2d.BLACK)
}