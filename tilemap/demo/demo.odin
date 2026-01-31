package demo

// import "core:fmt"
import rl "vendor:raylib"
import tm ".."

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

Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
Color :: rl.Color
Font :: rl.Font
Texture2D :: rl.Texture2D

state_list: []State = {
	state_atlas,
	state_tile,
	state_tileset,
	state_tilemap,
	state_grid,
	state_region,
	state_paint,
	state_drag,
	state_resize,
	state_ruletile,
}

Example :: enum {
	ATLAS,
	TILE,
	TILESET,
	TILEMAP,
	TILEMAP_GRID,
	TILEMAP_REGION,
	TILEMAP_PAINT,
	TILEMAP_DRAG,
	TILEMAP_RESIZE,
	RULETILE_PAINT,
	COUNT,
}
current_example:Example = Example.ATLAS

example_names:[]cstring = {
	"Atlas",
	"Tile",
	"Tileset",
	"Tilemap",
	"Tilemap Grid",
	"Tilemap Show Region",
	"Tilemap Painting",
	"Tilemap Dragging",
	"Tilemap Resizing",
	"Ruletile Painting",
}

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

screen_size:Vector2
is_hovering_buttons:bool

game_init :: proc() {
	create_tiles()
	create_tilemap()

	screen_size = {cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}
	// Init default state
	state_change(current_example)
}

game_shutdown :: proc() {
	rl.UnloadTexture(tileset_texture)
}

update :: proc() {
	if state_list[current_example].update != nil{
		state_list[current_example].update()
	}
	if rl.IsWindowResized() {
		screen_size = {cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}
	}
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.RAYWHITE)

	if state_list[current_example].draw != nil{
		state_list[current_example].draw()
	}

	BUTTON_SIZE: Vector2: {150, 20}
	BUTTON_PADDING :f32: 2
	button_rect:Rectangle = {screen_size.x - BUTTON_SIZE.x, 0, BUTTON_SIZE.x, BUTTON_SIZE.y}
	mouse_position:Vector2 = rl.GetMousePosition()
	is_hovering_buttons = false
	for i:int; i < cast(int)Example.COUNT; i += 1{
		if (rl.GuiButton(button_rect, example_names[i])){
			state_change(cast(Example)i)
		}
		if (rl.CheckCollisionPointRec(mouse_position, button_rect)){
			is_hovering_buttons = true
		}
		button_rect.y += BUTTON_SIZE.y + BUTTON_PADDING
	}

	if (rl.GuiButton(button_rect, "RESET")){
		create_tilemap()
	}

    rl.EndDrawing()
}

create_tiles :: proc(){
	tileset_texture = rl.LoadTexture("demo/tileset_template.png")
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
	tilemap = tm.TilemapInit({100, 100}, MAP_SIZE, {16,16}, tilemap_buffer[:])
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