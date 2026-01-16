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
//for editing
InputState :: tm.InputState

Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
Color :: rl.Color
Font :: rl.Font
Texture2D :: rl.Texture2D

screen_size:Vector2
is_hovering_buttons:bool

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
	COUNT,
}
current_example:Example = Example.TILEMAP_RESIZE

example_names:[]cstring = {
	"ATLAS",
	"TILE",
	"TILESET",
	"TILEMAP",
	"TILEMAP_GRID",
	"TILEMAP_REGION",
	"TILEMAP_PAINT",
	"TILEMAP_DRAG",
	"TILEMAP_RESIZE",
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
	screen_size = {cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.RAYWHITE)

	
	#partial switch(current_example){
	case Example.ATLAS:
		draw_from_atlas()
	case Example.TILE:
		draw_from_tiles()
	case Example.TILESET:
		draw_from_tileset()
	case Example.TILEMAP:
		draw_from_tilemap()
	case Example.TILEMAP_GRID:
		draw_tilemap_grid()
	case Example.TILEMAP_REGION:
		draw_tilemap_region()
	case Example.TILEMAP_PAINT:
		draw_tilemap_paint()
	case Example.TILEMAP_DRAG:
		draw_tilemap_drag()
	case Example.TILEMAP_RESIZE:
		draw_tilemap_resize()
	}

	BUTTON_SIZE: Vector2: {150, 20}
	BUTTON_PADDING :f32: 2
	button_rect:Rectangle = {screen_size.x - BUTTON_SIZE.x, 0, BUTTON_SIZE.x, BUTTON_SIZE.y}
	mouse_position:Vector2 = rl.GetMousePosition()
	is_hovering_buttons = false
	for i:int; i < cast(int)Example.COUNT; i += 1{
		if (rl.GuiButton(button_rect, example_names[i])){
			current_example = cast(Example)i
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

	rl.DrawText("draw_from_tilemap: Tilemap -> Tileset -> Tile -> TileAtlas", 10, 10, 20, rl.BLACK)
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

	rl.DrawText("draw_tilemap_grid: display as grid and IDs", 10, 10, 20, rl.BLACK)
}

draw_tilemap_region :: proc(){
	mouse_position:Vector2 = rl.GetMousePosition()
	mouse_position_i:vec2i = {cast(int)mouse_position.x, cast(int)mouse_position.y}
	// Translate position to tile coordinates
	tile_position:vec2i = tm.TilemapGetWorld2Tile(&tilemap, mouse_position_i)
	region:recti = {tile_position.x - 5, tile_position.y - 4, 5, 4}
	// Don't draw TILE_EMPTY ID
	skip_zero:bool = true

	tr.DrawTilemapGrid(&tilemap, rl.LIGHTGRAY)
	// Draw only tiles inside region
	tr.DrawTilemapRecti(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, region, &tileset_texture)
	// Draw rectangle around tiles
	tr.DrawTilemapSelection(&tilemap, region, rl.GRAY)

	rl.DrawText("draw_tilemap_region: reveal tiles with rectangle", 10, 10, 20, rl.BLACK)
}

// NOTE: tilemap/editing.odin has PaintTiles funcionality
draw_tilemap_paint :: proc(){
	@(static) tile_id:TileID = TILE_EMPTY
	@(static) position_state:vec2i
	mouse_position:Vector2 = rl.GetMousePosition()
	mouse_position_i:vec2i = {cast(int)mouse_position.x, cast(int)mouse_position.y}

	input_paint:InputState = tm.GetInputState(
		rl.IsMouseButtonPressed(rl.MouseButton.LEFT), 
		rl.IsMouseButtonDown(rl.MouseButton.LEFT),
		rl.IsMouseButtonReleased(rl.MouseButton.LEFT),
	)

	tm.PaintTiles(&tilemap, mouse_position_i, &position_state, tile_id, input_paint )

	// Read TileID under mouse position
	mouse_id:TileID = tm.TilemapGetTileWorld(&tilemap, mouse_position_i)
	
	if mouse_id != TILE_INVALID {
		// Active while inside tilemap
		wheel:int = cast(int)rl.GetMouseWheelMove()
		max_tiles:int = (ATLAS_SIZE.x * ATLAS_SIZE.y + 1)
		if wheel > 0 {
			tile_id = cast(TileID)((cast(int)tile_id + 1) % max_tiles)
		}
		if wheel < 0 {
			tile_id = cast(TileID)((cast(int)tile_id - 1 + max_tiles) % max_tiles)
		}
		
		if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT){
			// Copy TileID under mouse
			tile_id = mouse_id
		}
	}
		
	// Don't draw TILE_EMPTY ID
	skip_zero:bool = true
	tr.DrawTilemapGrid(&tilemap, rl.LIGHTGRAY)
	tr.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)

	if mouse_id != TILE_INVALID {
		// Draw a cell aligned to grid and ID under mouse
		tr.DrawTilemapCellRect(&tilemap, mouse_position_i, tile_id, rl.GetFontDefault(), 10, rl.GRAY)

	}

	rl.DrawText("draw_tilemap_paint: left mouse draw, right mouse copy, mouse scroll change ID", 10, 10, 20, rl.BLACK)
}

draw_tilemap_drag :: proc(){
	// Persistent variables to hold state
	@(static) selection_state:vec2i
	@(static) drag_pos_state:vec2i
	@(static) map_pos_state:vec2i
	@(static) rect_state:recti
	@(static) temp_tilemap:Tilemap = {}
	@(static) temp_buffer:[MAP_SIZE.x * MAP_SIZE.y]TileID

	input_selection:InputState = tm.GetInputState(
		rl.IsMouseButtonPressed(rl.MouseButton.LEFT), 
		rl.IsMouseButtonDown(rl.MouseButton.LEFT),
		rl.IsMouseButtonReleased(rl.MouseButton.LEFT),
	)

	input_drag:InputState = tm.GetInputState(
		rl.IsMouseButtonPressed(rl.MouseButton.RIGHT), 
		rl.IsMouseButtonDown(rl.MouseButton.RIGHT),
		rl.IsMouseButtonReleased(rl.MouseButton.RIGHT),
	)

	if (rect_state.w == 0 || rect_state.h == 0){
		// no drag without selection
		input_drag = InputState.NONE
	}
	
	mouse_position:Vector2 = rl.GetMousePosition()
	mouse_position_i:vec2i = {cast(int)mouse_position.x, cast(int)mouse_position.y}
	

	if (input_drag != InputState.NONE){
		write_empty:bool = rl.IsKeyDown(rl.KeyboardKey.LEFT_ALT) || rl.IsKeyDown(rl.KeyboardKey.RIGHT_ALT)
		remove_source:bool = rl.IsKeyDown(rl.KeyboardKey.LEFT_CONTROL) || rl.IsKeyDown(rl.KeyboardKey.RIGHT_CONTROL)
		
		tm.DragTiles(
			&tilemap,
			&temp_tilemap,
			mouse_position_i,
			&drag_pos_state,
			&map_pos_state,
			&rect_state,
			input_drag,
			remove_source,
			write_empty,
			temp_buffer[:],
		)

		// Don't allow to change selection
		if (input_selection != InputState.NONE){
			input_selection = InputState.NONE
		}
	}

	if (input_selection != InputState.NONE){
		tm.CreateSelection(&tilemap, mouse_position_i, &selection_state, &rect_state, input_selection)
	}

	tr.DrawTilemapGrid(&tilemap, rl.LIGHTGRAY)
	skip_zero:bool = true
	tr.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)
	if(temp_tilemap.size.x != 0 && rect_state.w != 0){
		temp_rect:recti = tm.TilemapRecti(&temp_tilemap)
		tr.DrawTilemapSelection(&temp_tilemap, temp_rect, rl.GRAY)
		tr.DrawTilemap(&temp_tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)
	}

	tr.DrawTilemapSelection(&tilemap, rect_state, rl.BLACK)

	rl.DrawText("draw_tilemap_drag: left mouse select, right mouse drag, hold CTRL to remove source, ALT to write empty tiles", 10, 10, 20, rl.BLACK)
}

draw_tilemap_resize :: proc(){
	// Persistent variables to hold state
	@(static) rect_state:recti
	@(static) selection_state:vec2i
	@(static) temp_buffer:[MAP_SIZE.x * MAP_SIZE.y]TileID

	size_error:bool

	input_selection:InputState = tm.GetInputState(
		rl.IsMouseButtonPressed(rl.MouseButton.LEFT), 
		rl.IsMouseButtonDown(rl.MouseButton.LEFT),
		rl.IsMouseButtonReleased(rl.MouseButton.LEFT),
	)

	if (is_hovering_buttons){
		input_selection = InputState.NONE
		rect_state.w = 0
		rect_state.h = 0
	}

	mouse_position:Vector2 = rl.GetMousePosition()
	mouse_position_i:vec2i = {cast(int)mouse_position.x, cast(int)mouse_position.y}

	if (input_selection != InputState.NONE){
		tm.CreateSelection(&tilemap, mouse_position_i, &selection_state, &rect_state, input_selection)
	}

	rect_area:int = rect_state.w * rect_state.h
	size_error = rect_area > len(tilemap.grid)

	if (input_selection == InputState.RELEASE){
		if (!size_error && rect_area > 0){
			tm.TilemapResize(&tilemap, rect_state, temp_buffer[:])
		}
		rect_state.w = 0
		rect_state.h = 0
	}

	tr.DrawTilemapGrid(&tilemap, rl.LIGHTGRAY)
	skip_zero:bool = true
	tr.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)

	tr.DrawTilemapSelection(&tilemap, rect_state, rl.BLACK)

	rl.DrawText("draw_tilemap_resize: left mouse select, ENTER to resize", 10, 10, 20, rl.BLACK)

	if size_error {
		text:cstring = rl.TextFormat("ERROR: tilemap grid buffer overflow (%d > %d)", rect_area, len(tilemap.grid))
		rl.DrawText(text, 10, 30, 20, rl.RED)
	}
}