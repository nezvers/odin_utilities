package demo

// import "core:fmt"
import rl "vendor:raylib"
import tm ".."
import tr "../raylib"

vec2i :: tm.vec2i
recti :: tm.recti
TileID :: tm.TileID
Tile :: tm.Tile
Tileset :: tm.Tileset
Tilemap :: tm.Tilemap
TILE_EMPTY :: tm.TILE_EMPTY
TILE_INVALID :: tm.TILE_INVALID

Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
Color :: rl.Color
Font :: rl.Font
Texture2D :: rl.Texture2D

tilemap_buffer: [20 * 20]TileID
tilemap: Tilemap
tileset_texture: Texture2D
tile_atlas: tr.TileAtlas

game_init :: proc() {
	tileset_texture = rl.LoadTexture("demo/tileset_template.png")


	new_tilemap: = tm.TilemapInit({}, {20,20}, {16,16}, tilemap_buffer[:], len(tilemap_buffer))
	tm.TilemapClear(&new_tilemap)
}

game_shutdown :: proc() {

}

update :: proc() {

}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.WHITE)

	rl.DrawTextureRec(tileset_texture, {32,32,16,16}, {32, 32}, rl.WHITE)

    rl.EndDrawing()
}
