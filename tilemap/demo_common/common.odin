package demo_common

import tm ".."
import kit "../../demo_kit"

vec2i :: tm.vec2i
recti :: tm.recti
TileAtlas :: tm.TileAtlas
TileID :: tm.TileID
Tile :: tm.Tile
Tileset :: tm.Tileset
Tilemap :: tm.Tilemap
TILE_EMPTY :: tm.TILE_EMPTY
TILE_INVALID :: tm.TILE_INVALID
//for editing
InputState :: tm.InputState

Vector2 :: kit.Vec2

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

tileset_texture: kit.Texture
tile_atlas: tm.TileAtlas

// Allocated Tile array
tileset:Tileset
tile_list:[ATLAS_SIZE.x * ATLAS_SIZE.y + 1]Tile

tilemap: Tilemap
tilemap_buffer: [MAP_SIZE.x * MAP_SIZE.y]TileID

// Dual grid tile sheet is 4x4 tiles
DUALGRID_ATLAS_SIZE:vec2i: {4, 4}
tileset_dualgrid_texture: kit.Texture
tile_atlas_dualgrid: tm.TileAtlas
tileset_dualgrid:Tileset
atlas_buffer_dualgrid:[DUALGRID_ATLAS_SIZE.x * DUALGRID_ATLAS_SIZE.y + 1]Vector2
tile_buffer_dualgrid:[DUALGRID_ATLAS_SIZE.x * DUALGRID_ATLAS_SIZE.y + 1]TileID
tile_list_dualgrid:[DUALGRID_ATLAS_SIZE.x * DUALGRID_ATLAS_SIZE.y + 1]Tile

create_dualgrid_tiles :: proc() {
	tile_size:Vector2 = {cast(f32)TILE_SIZE.x, cast(f32)TILE_SIZE.y}
	tm.TileAtlasInit(&tile_atlas_dualgrid, tile_size, atlas_buffer_dualgrid[:])
	initial_length_tileset:u32 = len(tile_list_dualgrid)
	tm.TilesetInit(&tileset_dualgrid, tile_list_dualgrid[:], initial_length_tileset)

	// Represents TILE_EMPTY
	tex_pos:Vector2 = {0.0, 0.0}
	initial_length:u32 = 1
	tm.TileAtlasInsert(&tile_atlas_dualgrid, tex_pos, 0)
	tile_buffer_dualgrid[0] = TILE_EMPTY
	tm.TileInit(&tile_list_dualgrid[0], tile_buffer_dualgrid[0:1], initial_length)

	for i:i32 = 0; i < (DUALGRID_ATLAS_SIZE.x * DUALGRID_ATLAS_SIZE.y); i += 1{
		x:i32 = i % DUALGRID_ATLAS_SIZE.x
		y:i32 = i / DUALGRID_ATLAS_SIZE.x
		tex_pos = {
			cast(f32)(x * TILE_SIZE.x),
			cast(f32)(y * TILE_SIZE.y),
		}

		tile_i:u32 = cast(u32)(i + 1)
		tm.TileAtlasInsert(&tile_atlas_dualgrid, tex_pos, tile_i)
		tile_buffer_dualgrid[tile_i] = cast(u8)tile_i
		tm.TileInit(&tile_list_dualgrid[tile_i], tile_buffer_dualgrid[tile_i:tile_i+1], initial_length)
	}
}

create_tiles :: proc() {
	tile_size:Vector2 = {cast(f32)TILE_SIZE.x, cast(f32)TILE_SIZE.y}
	tm.TileAtlasInit(&tile_atlas, tile_size, atlas_buffer[:])
	
	// Assign Tile array to a tileset
	initial_length_tileset:u32 = len(tile_list)
	tm.TilesetInit(&tileset, tile_list[:], initial_length_tileset)
	
	// Represents TILE_EMPTY, use skip_zero flag
	tex_pos:Vector2 = {0.0, 0.0}
	// Each tile gets 1 TileAtlas position
	initial_length:u32 = 1
	tm.TileAtlasInsert(&tile_atlas, tex_pos, 0)
	tile_buffer[0] = TILE_EMPTY
	tm.TileInit(&tile_list[0], tile_buffer[0:1], initial_length)

	// Calculate actual tiles
	// for each tile in texture generate atlas position and assign ID to Tile
	for i:i32 = 0; i < (ATLAS_SIZE.x * ATLAS_SIZE.y); i += 1{
		x:i32 = i % ATLAS_SIZE.x
		y:i32 = i / ATLAS_SIZE.x
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

create_tilemap :: proc() {
	tilemap = tm.TilemapInit({100, 100}, MAP_SIZE, {16,16}, tilemap_buffer[:])
	// reset map to predictable state
	tm.TilemapClear(&tilemap)
	
    // Hardcoded tilemap
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

animation_t: f32
get_animation_time :: proc(ctx: ^kit.Context, speed: f32) -> f32 {
	animation_t += ctx.delta_time * speed
	if animation_t > 1.0 {
		animation_t -= f32(i32(animation_t))
	}
	return animation_t
}

// Every demo shares the textures and the tiles: made when the first demo starts, the textures belong to the backend
common_ready: bool

common_init :: proc(ctx: ^kit.Context) {
	if !common_ready {
		tileset_texture = kit.TextureLoad(ctx, #load("../../assets/textures/tileset_template.png"))
		tileset_dualgrid_texture = kit.TextureLoad(ctx, #load("../../assets/textures/tileset_template_dualgrid.png"))
		create_tiles()
		create_dualgrid_tiles()
		common_ready = true
	}
	// every demo starts from the same tilemap
	create_tilemap()
}

// The state of the left mouse button for the editing procs of the library
mouse_state :: proc(ctx: ^kit.Context, button: kit.MouseButton) -> InputState {
	return tm.GetInputState(kit.MousePressed(&ctx.input, button), kit.MouseDown(&ctx.input, button), kit.MouseReleased(&ctx.input, button))
}

mouse_cell :: proc(ctx: ^kit.Context) -> vec2i {
	return {i32(ctx.input.mouse_position.x), i32(ctx.input.mouse_position.y)}
}
