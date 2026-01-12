package demo

// import "core:fmt"
import rl "vendor:raylib"
import tm ".."
import tr "../raylib"
import math "core:math"

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

Example :: enum {
	DRAW_ATLAS,
	DRAW_TILE,
	DRAW_TILESET,
	DRAW_TILEMAP,
	DRAW_TILEMAP_GRID,
	DRAW_TILEMAP_REGION,
	COUNT,
}
current_example:Example = Example.DRAW_ATLAS

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
	if rl.IsKeyPressed(rl.KeyboardKey.TAB) {
		current_example = cast(Example)((cast(int)current_example + 1) % cast(int)Example.COUNT)
	}
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.RAYWHITE)

	
	#partial switch(current_example){
	case Example.DRAW_ATLAS:
		draw_from_atlas()
	case Example.DRAW_TILE:
		draw_from_tiles()
	case Example.DRAW_TILESET:
		draw_from_tileset()
	case Example.DRAW_TILEMAP:
		draw_from_tilemap()
	case Example.DRAW_TILEMAP_GRID:
		draw_tilemap_grid()
	case Example.DRAW_TILEMAP_REGION:
		draw_tilemap_region()
	}

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
		x:int = i % ATLAS_SIZE.x
		y:int = i / ATLAS_SIZE.x
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
	tm.TilemapSetTile(&tilemap, {6, 2}, 4)

	tm.TilemapSetTile(&tilemap, {2, 3}, 1 + cast(TileID)ATLAS_SIZE.x * 1)
	tm.TilemapSetTile(&tilemap, {3, 3}, 2 + cast(TileID)ATLAS_SIZE.x * 1)
	tm.TilemapSetTile(&tilemap, {4, 3}, 3 + cast(TileID)ATLAS_SIZE.x * 1)
	tm.TilemapSetTile(&tilemap, {6, 3}, 4 + cast(TileID)ATLAS_SIZE.x * 1)

	tm.TilemapSetTile(&tilemap, {2, 4}, 1 + cast(TileID)ATLAS_SIZE.x * 2)
	tm.TilemapSetTile(&tilemap, {3, 4}, 2 + cast(TileID)ATLAS_SIZE.x * 2)
	tm.TilemapSetTile(&tilemap, {4, 4}, 3 + cast(TileID)ATLAS_SIZE.x * 2)
	tm.TilemapSetTile(&tilemap, {6, 4}, 4 + cast(TileID)ATLAS_SIZE.x * 2)

	tm.TilemapSetTile(&tilemap, {2, 6}, 1 + cast(TileID)ATLAS_SIZE.x * 3)
	tm.TilemapSetTile(&tilemap, {3, 6}, 2 + cast(TileID)ATLAS_SIZE.x * 3)
	tm.TilemapSetTile(&tilemap, {4, 6}, 3 + cast(TileID)ATLAS_SIZE.x * 3)

	tm.TilemapSetTile(&tilemap, {6, 6}, 4 + cast(TileID)ATLAS_SIZE.x * 3)
}

get_animation_time :: proc(speed:f32)->f32 {
	@(static) t:f32
	t += rl.GetFrameTime() * speed
	if t > 1.0 {
		t -= cast(f32)cast(i32)t
	}
	return t
}

// Example for drawing atlas directly by recreating whole texture
draw_from_atlas::proc(){
	padding:int = 4 + cast(int)(math.sin(get_animation_time(0.2) * math.TAU) * 4.5)
	root_position:Vector2 = {100, 100}
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

	rl.DrawText("draw_from_atlas\nTAB to change", 10, 10, 20, rl.BLACK)
}

// Example for drawing atlas directly by recreating whole texture
draw_from_tiles::proc(){
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

// Example for drawing atlas directly by recreating whole texture
draw_from_tileset::proc(){
	padding:int = 4 + cast(int)(math.sin(get_animation_time(0.2) * math.TAU) * 4.5)
	root_position:Vector2 = {100, 100}
	// 0th id is TILE_EMPTY
	id_offset:int = 1
	for y:int = 0; y < ATLAS_SIZE.y; y += 1 {
		for x:int = 0; x < ATLAS_SIZE.x; x += 1 {
			i:int = x + y * ATLAS_SIZE.x + id_offset
			
			// get a tile ID from tileset
			tile:TileID = tm.TilesetGetId(&tileset, cast(TileID)i)

			// Read tiles default 0th ID
			atlas_id:TileID = tm.TileGetId(&tile_list[tile])
			draw_pos:Vector2 = {
				root_position.x + cast(f32)(x * (TILE_SIZE.x + padding)), 
				root_position.y + cast(f32)(y * (TILE_SIZE.y + padding)),
			}
			tr.DrawTileAtlas(&tile_atlas, atlas_id, draw_pos, &tileset_texture)
		}
	}

	rl.DrawText("draw_from_tileset: Tileset -> Tile -> TileAtlas", 10, 10, 20, rl.BLACK)
}

draw_from_tilemap :: proc(){
	skip_zero:bool = true

	tr.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)

	rl.DrawText("draw_from_tilemap: TILEMAP -> Tileset -> Tile -> TileAtlas", 10, 10, 20, rl.BLACK)
}

draw_tilemap_grid :: proc(){
	tr.DrawTilemapGrid(&tilemap, rl.LIGHTGRAY)
	tr.DrawTilemapTileId(&tilemap, rl.GetFontDefault(), 10, rl.LIGHTGRAY)

	mouse_position:Vector2 = rl.GetMousePosition()
	mouse_position_i:vec2i = {cast(int)mouse_position.x, cast(int)mouse_position.y}
	// Read TileID under mouse position
	tile_id:TileID = tm.TilemapGetTileWorld(&tilemap, mouse_position_i)
	// Draw a cell aligned to grid and ID under mouse
	tr.DrawTilemapCellRect(&tilemap, mouse_position_i, tile_id, rl.GetFontDefault(), 10, rl.GRAY)

	rl.DrawText("draw_tilemap_grid: ", 10, 10, 20, rl.BLACK)
}

draw_tilemap_region :: proc(){
	mouse_position:Vector2 = rl.GetMousePosition()
	mouse_position_i:vec2i = {cast(int)mouse_position.x, cast(int)mouse_position.y}
	// Translate position to tile coordinates
	tile_position:vec2i = tm.TilemapGetPositionWorld2Tile(&tilemap, mouse_position_i)
	region:recti = {tile_position.x, tile_position.y, 4, 3}
	// Don't draw TILE_EMPTY ID
	skip_zero:bool = true

	tr.DrawTilemapGrid(&tilemap, rl.LIGHTGRAY)
	// Draw only tiles inside region
	tr.DrawTilemapRecti(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, region, &tileset_texture)
	// Draw rectangle around tiles
	tr.DrawTilemapSelection(&tilemap, region, rl.GRAY)

	rl.DrawText("draw_tilemap_region: ", 10, 10, 20, rl.BLACK)
}