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

TILE_SIZE:vec2i: {16, 16}
ATLAS_SIZE:vec2i: {10, 5}

// Holds texture positions for tiles
atlas_buffer:[ATLAS_SIZE.x * ATLAS_SIZE.y + 1]Vector2
// Holds indexes for tile_atlas positions
// For this example same buffer sliced for each Tile (no alternative tiles)
tile_buffer:[ATLAS_SIZE.x * ATLAS_SIZE.y + 1]TileID
// Holds indexes for Tiles
tileset_buffer:[ATLAS_SIZE.x * ATLAS_SIZE.y + 1]TileID

// Allocated Tile array
tile_list:[ATLAS_SIZE.x * ATLAS_SIZE.y + 1]Tile
tileset:Tileset


tilemap_buffer: [20 * 20]TileID
tilemap: Tilemap
tileset_texture: Texture2D
tile_atlas: tr.TileAtlas


game_init :: proc() {
	create_tile_atlas()

	new_tilemap: = tm.TilemapInit({}, {20,20}, {16,16}, tilemap_buffer[0:len(tilemap_buffer)], len(tilemap_buffer))
	tm.TilemapClear(&new_tilemap)
}

game_shutdown :: proc() {

}

update :: proc() {

}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.WHITE)

	tile_id:TileID = tile_list[5].data[0]
	tex_pos:Vector2 = tile_atlas.data[tile_id]
	rl.DrawTextureRec(tileset_texture, {tex_pos.x,tex_pos.y,16,16}, {32, 32}, rl.WHITE)

    rl.EndDrawing()
}

create_tile_atlas :: proc(){
	tileset_texture = rl.LoadTexture("demo/tileset_template.png")
	tr.TileAtlasInit(&tile_atlas, {cast(f32)TILE_SIZE.x, cast(f32)TILE_SIZE.y}, &tileset_texture, atlas_buffer[0:len(atlas_buffer)])
	
	// Represents TILE_EMPTY, use skip_zero flag
	tr.TileAtlasInsert(&tile_atlas, {0.0, 0.0}, 0)
	tile_buffer[0] = TILE_EMPTY
	tm.TileInit(&tile_list[0], tile_buffer[0:1])
	tm.TilesetInit(&tileset, tile_list[0:len(tile_list)])


	// Calculate actual tiles
	for i:int = 0; i < (ATLAS_SIZE.x * ATLAS_SIZE.y); i += 1{
		x:int = i % TILE_SIZE.x
		y:int = i / TILE_SIZE.x
		tex_pos:Vector2 = {
			cast(f32)(x * TILE_SIZE.x),
			cast(f32)(y * TILE_SIZE.y),
		}

		tile_i:u32 = cast(u32)(i + 1)
		tr.TileAtlasInsert(&tile_atlas, tex_pos, tile_i)
		// Assign TileID
		tile_buffer[tile_i] = cast(u8)tile_i
		tm.TileInit(&tile_list[tile_i], tile_buffer[tile_i:tile_i+1])
	}
}