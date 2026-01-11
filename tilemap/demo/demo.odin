package demo

// import "core:fmt"
import rl "vendor:raylib"
import tm ".."
import tr "../raylib"

vec2i :: tm.vec2i
recti :: tm.recti
TileAtlas :: tm.TileAtlas
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
MAP_SIZE:vec2i: {10, 10}

// Holds texture positions for tiles
atlas_buffer:[ATLAS_SIZE.x * ATLAS_SIZE.y + 1]Vector2
// Holds indexes for tile_atlas positions
// For this example same buffer sliced for each Tile (no alternative tiles)
tile_buffer:[ATLAS_SIZE.x * ATLAS_SIZE.y + 1]TileID
// Holds indexes for Tiles
tileset_buffer:[ATLAS_SIZE.x * ATLAS_SIZE.y + 1]TileID

tileset_texture: Texture2D
tile_atlas: tm.TileAtlas

// Allocated Tile array
tileset:Tileset
tile_list:[ATLAS_SIZE.x * ATLAS_SIZE.y + 1]Tile

tilemap: Tilemap
tilemap_buffer: [MAP_SIZE.x * MAP_SIZE.y]TileID


game_init :: proc() {
	create_tiles()
	create_tilemap()
}

game_shutdown :: proc() {
	rl.UnloadTexture(tileset_texture)
}

update :: proc() {
 //
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.RAYWHITE)

	// draw_from_atlas()
	// draw_from_tiles()
	// draw_from_tileset()
	draw_from_tilemap()

    rl.EndDrawing()
}

create_tiles :: proc(){
	tileset_texture = rl.LoadTexture("demo/tileset_template.png")
	tile_size:Vector2 = {cast(f32)TILE_SIZE.x, cast(f32)TILE_SIZE.y}
	tm.TileAtlasInit(&tile_atlas, tile_size, atlas_buffer[0:len(atlas_buffer)])
	
	// Assign Tile array to a tileset
	initial_length_tileset:u32 = len(tile_list)
	tm.TilesetInit(&tileset, tile_list[0:len(tile_list)], initial_length_tileset)
	
	// Represents TILE_EMPTY, use skip_zero flag
	tex_pos:Vector2 = {0.0, 0.0}
	// Each tile gets 1 TileAtlas position
	initial_length:u32 = 1
	tm.TileAtlasInsert(&tile_atlas, tex_pos, 0)
	tile_buffer[0] = TILE_EMPTY
	tm.TileInit(&tile_list[0], tile_buffer[0:1], initial_length)

	// Calculate actual tiles
	// for each tile in texture generate atlas position and assign ID to Tile
	for i:int = 0; i < (ATLAS_SIZE.x * ATLAS_SIZE.y); i += 1{
		x:int = i % TILE_SIZE.x
		y:int = i / TILE_SIZE.x
		tex_pos = {
			cast(f32)(x * TILE_SIZE.x),
			cast(f32)(y * TILE_SIZE.y),
		}

		tile_i:u32 = cast(u32)(i + 1)
		tm.TileAtlasInsert(&tile_atlas, tex_pos, tile_i)
		// Assign TileID
		tile_buffer[tile_i] = cast(u8)tile_i
		tm.TileInit(&tile_list[tile_i], tile_buffer[tile_i:tile_i+1], initial_length)
	}
}

create_tilemap :: proc(){
	tilemap = tm.TilemapInit({100, 100}, MAP_SIZE, {16,16}, tilemap_buffer[0:len(tilemap_buffer)], len(tilemap_buffer))
	// reset map to predictable state
	tm.TilemapClear(&tilemap)
	
	tm.TilemapSetTile(&tilemap, {2, 2}, 1)
	tm.TilemapSetTile(&tilemap, {3, 2}, 2)
	tm.TilemapSetTile(&tilemap, {4, 2}, 3)
}

// Example for drawing atlas directly by recreating whole texture
draw_from_atlas::proc(){
	root_position:Vector2 = {100, 100}
	padding:int = 4
	// 0th id is TILE_EMPTY
	id_offset:int = 1
	for y:int = 0; y < ATLAS_SIZE.y; y += 1 {
		for x:int = 0; x < ATLAS_SIZE.x; x += 1 {
			i:int = x + y * ATLAS_SIZE.x + id_offset

			atlas_id:TileID = cast(TileID)i
			draw_pos:Vector2 = {
				root_position.x + cast(f32)(x * (TILE_SIZE.x + padding)), 
				root_position.y + cast(f32)(y * (TILE_SIZE.y + padding)),
			}
			tr.DrawTileAtlas(&tile_atlas, atlas_id, draw_pos, &tileset_texture)
		}
	}
}

// Example for drawing atlas directly by recreating whole texture
draw_from_tiles::proc(){
	root_position:Vector2 = {100, 100}
	padding:int = 4
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
}

// Example for drawing atlas directly by recreating whole texture
draw_from_tileset::proc(){
	root_position:Vector2 = {100, 100}
	padding:int = 4
	// 0th id is TILE_EMPTY
	id_offset:int = 1
	for y:int = 0; y < ATLAS_SIZE.y; y += 1 {
		for x:int = 0; x < ATLAS_SIZE.x; x += 1 {
			i:int = x + y * ATLAS_SIZE.x + id_offset
			
			// get a tile ID from tileset
			tile:TileID = tm.TilesetGetTile(&tileset, cast(TileID)i)

			// Read tiles default 0th ID
			atlas_id:TileID = tm.TileGetId(&tile_list[tile])
			draw_pos:Vector2 = {
				root_position.x + cast(f32)(x * (TILE_SIZE.x + padding)), 
				root_position.y + cast(f32)(y * (TILE_SIZE.y + padding)),
			}
			tr.DrawTileAtlas(&tile_atlas, atlas_id, draw_pos, &tileset_texture)
		}
	}
}

draw_from_tilemap :: proc(){
	tr.DrawTilemapGrid(&tilemap, rl.LIGHTGRAY)
	tr.DrawTilemapTileId(&tilemap, rl.GetFontDefault(), 10, rl.LIGHTGRAY)

	mp:Vector2 = rl.GetMousePosition()
	tr.DrawTilemapCellRect(&tilemap, {cast(int)mp.x, cast(int)mp.y}, 0, rl.GetFontDefault(), 10, rl.GRAY)

	tr.DrawTilemapSelection(&tilemap, {2, 2, 3, 1}, rl.GRAY)
}