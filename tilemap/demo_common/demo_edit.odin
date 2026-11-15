#+private file
package demo_common

// The editing procs of the library (editing.odin) driven by the mouse: paint, select and drag, select and resize.

import "core:fmt"
import tm ".."
import tm_kit "../kit"
import kit "../../demo_kit"

@(private="package")
demo_paint: kit.Demo = {name = "tilemap paint", init = common_init, draw = draw_paint, script = script_paint}
@(private="package")
demo_drag: kit.Demo = {name = "tilemap drag", init = init_drag, draw = draw_drag, script = script_drag}
@(private="package")
demo_resize: kit.Demo = {name = "tilemap resize", init = init_resize, draw = draw_resize, script = script_resize}

// ---- paint

paint_tile_id: TileID = TILE_EMPTY
paint_position_state: vec2i

// NOTE: tilemap/editing.odin has PaintTiles functionality example
draw_paint :: proc(ctx: ^kit.Context) {
	mouse: vec2i = mouse_cell(ctx)
	if !ctx.ui_hover {
		tm.PaintTiles(&tilemap, mouse, &paint_position_state, paint_tile_id, mouse_state(ctx, .LEFT))
	}

	// Read TileID under mouse position
	mouse_id: TileID = tm.TilemapGetTileWorld(&tilemap, mouse)
	if mouse_id != TILE_INVALID {
		// Active while inside tilemap
		wheel: i32 = i32(ctx.input.mouse_wheel)
		max_tiles: TileID = TileID(ATLAS_SIZE.x * ATLAS_SIZE.y + 1)
		if wheel > 0 { paint_tile_id = (paint_tile_id + 1) % max_tiles }
		if wheel < 0 { paint_tile_id = (paint_tile_id - 1 + max_tiles) % max_tiles }
		if kit.MousePressed(&ctx.input, .RIGHT) {
			// Copy TileID under mouse
			paint_tile_id = mouse_id
		}
	}

	skip_zero: bool = true
	tm_kit.DrawTilemapGrid(ctx, &tilemap, kit.LIGHT_GRAY)
	tm_kit.DrawTilemap(ctx, &tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, tileset_texture)
	if mouse_id != TILE_INVALID {
		// Draw a cell aligned to grid and the ID that is painted
		tm_kit.DrawTilemapCellRect(ctx, &tilemap, mouse, paint_tile_id, 10, kit.GRAY)
	}
	kit.DrawText(ctx, "draw_tilemap_paint: left mouse draw, right mouse copy, mouse scroll change ID", {10, 10}, 20, kit.BLACK)
}

script_paint: []kit.Step = {
	kit.Wait(3),
	kit.MoveTo({100 + 16 * 5 + 4, 100 + 16 * 5 + 4}),       // the cell 5,5 is empty and in the map
	kit.Wait(1),
	kit.Scroll(1), kit.Wait(1), kit.Scroll(1), kit.Wait(1), kit.Scroll(1), kit.Wait(1),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return paint_tile_id == 3 }, "the wheel changes the tile that is painted"),
	kit.Click({100 + 16 * 5 + 4, 100 + 16 * 5 + 4}),
	kit.Wait(2),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return tm.TilemapGetTile(&tilemap, {5, 5}) == 3 }, "the left button paints the tile under the mouse"),
	kit.Click({100 + 16 * 2 + 4, 100 + 16 * 2 + 4}, .RIGHT),        // copy the tile at 2,2
	kit.Wait(2),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return paint_tile_id == 1 }, "the right button copies the tile under the mouse"),
}

// ---- drag: select a rectangle with the left button, drag it with the right one (control: remove the source, alt: write empty tiles)

drag_selection_state: vec2i
drag_pos_state: vec2i
drag_rect_state: recti
drag_temp_tilemap: Tilemap
drag_temp_buffer: [MAP_SIZE.x * MAP_SIZE.y]TileID

init_drag :: proc(ctx: ^kit.Context) {
	common_init(ctx)
	drag_selection_state, drag_pos_state, drag_rect_state, drag_temp_tilemap = {}, {}, {}, {}
}

draw_drag :: proc(ctx: ^kit.Context) {
	input_selection: InputState = mouse_state(ctx, .LEFT)
	input_drag: InputState = mouse_state(ctx, .RIGHT)
	if drag_rect_state.w == 0 || drag_rect_state.h == 0 {
		input_drag = InputState.NONE        // no drag without selection
	}
	mouse: vec2i = mouse_cell(ctx)
	if input_drag != InputState.NONE {
		write_empty: bool = kit.KeyDown(&ctx.input, .LEFT_ALT) || kit.KeyDown(&ctx.input, .RIGHT_ALT)
		remove_source: bool = kit.CtrlDown(&ctx.input)
		tm.DragTiles(&tilemap, &drag_temp_tilemap, mouse, &drag_pos_state, &drag_rect_state, input_drag, remove_source, write_empty, drag_temp_buffer[:])
		// Do not allow to change the selection
		input_selection = InputState.NONE
	}
	if input_selection != InputState.NONE && !ctx.ui_hover {
		tm.CreateSelection(&tilemap, mouse, &drag_selection_state, &drag_rect_state, input_selection)
	}

	tm_kit.DrawTilemapGrid(ctx, &tilemap, kit.LIGHT_GRAY)
	skip_zero: bool = true
	tm_kit.DrawTilemap(ctx, &tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, tileset_texture)
	if drag_temp_tilemap.size.x != 0 && drag_rect_state.w != 0 {
		temp_rect: recti = tm.TilemapRecti(&drag_temp_tilemap)
		tm_kit.DrawTilemapSelection(ctx, &drag_temp_tilemap, temp_rect, kit.GRAY)
		tm_kit.DrawTilemap(ctx, &drag_temp_tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, tileset_texture)
	}
	tm_kit.DrawTilemapSelection(ctx, &tilemap, drag_rect_state, kit.BLACK)
	kit.DrawText(ctx, "draw_tilemap_drag: left mouse select, right mouse drag, hold CTRL to remove source, ALT to write empty tiles", {10, 10}, 20, kit.BLACK)
}

script_drag: []kit.Step = {
	kit.Wait(3),
	// select the cells 2,2 .. 4,4 (3 x 3) with the left button
	kit.MoveTo({100 + 16 * 2 + 4, 100 + 16 * 2 + 4}), kit.MouseDownStep(), kit.Wait(1), kit.MoveTo({100 + 16 * 4 + 4, 100 + 16 * 4 + 4}), kit.Wait(1), kit.MouseUpStep(), kit.Wait(2),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return drag_rect_state.w == 3 && drag_rect_state.h == 3 && drag_rect_state.x == 2 }, "dragging the left button selects a rectangle of cells"),
	// drag the selection with the right button, one cell down and four right, holding control: the source is removed
	kit.KeyDownStep(.LEFT_CTRL),
	kit.MoveTo({100 + 16 * 3 + 4, 100 + 16 * 3 + 4}), kit.MouseDownStep(.RIGHT), kit.Wait(1), kit.MoveTo({100 + 16 * 7 + 4, 100 + 16 * 4 + 4}), kit.Wait(1), kit.MouseUpStep(.RIGHT), kit.Wait(2),
	kit.KeyUpStep(.LEFT_CTRL),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return tm.TilemapGetTile(&tilemap, {3, 2}) == TILE_EMPTY }, "dragging with control removed the source tiles"),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return tm.TilemapGetTile(&tilemap, {7, 3}) != TILE_EMPTY }, "and the tiles are where they were dropped"),
}

// ---- resize: select with the left button, the tilemap becomes the selection when it is let go

resize_rect_state: recti
resize_selection_state: vec2i
resize_temp_buffer: [MAP_SIZE.x * MAP_SIZE.y]TileID
resized: int

init_resize :: proc(ctx: ^kit.Context) {
	common_init(ctx)
	resize_rect_state, resize_selection_state = {}, {}
	resized = 0
}

draw_resize :: proc(ctx: ^kit.Context) {
	input_selection: InputState = mouse_state(ctx, .LEFT)
	if ctx.ui_hover {
		input_selection = InputState.NONE
		resize_rect_state.w = 0
		resize_rect_state.h = 0
	}
	mouse: vec2i = mouse_cell(ctx)
	if input_selection != InputState.NONE {
		tm.CreateSelection(&tilemap, mouse, &resize_selection_state, &resize_rect_state, input_selection)
	}
	rect_area: i32 = resize_rect_state.w * resize_rect_state.h
	size_error: bool = rect_area > i32(len(tilemap.grid))
	if input_selection == InputState.RELEASE {
		if !size_error && rect_area > 0 {
			tm.TilemapResize(&tilemap, resize_rect_state, resize_temp_buffer[:])
			resized += 1
		}
		resize_rect_state.w = 0
		resize_rect_state.h = 0
	}

	tm_kit.DrawTilemapGrid(ctx, &tilemap, kit.LIGHT_GRAY)
	skip_zero: bool = true
	tm_kit.DrawTilemap(ctx, &tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, tileset_texture)
	tm_kit.DrawTilemapSelection(ctx, &tilemap, resize_rect_state, kit.BLACK)
	kit.DrawText(ctx, "draw_tilemap_resize: left mouse select, release to resize", {10, 10}, 20, kit.BLACK)
	if size_error {
		kit.DrawText(ctx, fmt.tprintf("ERROR: tilemap grid buffer overflow (%d > %d)", rect_area, len(tilemap.grid)), {10, 30}, 20, kit.RED)
	}
}

script_resize: []kit.Step = {
	kit.Wait(3),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return tilemap.size == vec2i{10, 10} }, "starts as 10 x 10"),
	// select cells 1,1 .. 5,4 (5 x 4)
	kit.MoveTo({100 + 16 * 1 + 4, 100 + 16 * 1 + 4}), kit.MouseDownStep(), kit.Wait(1), kit.MoveTo({100 + 16 * 5 + 4, 100 + 16 * 4 + 4}), kit.Wait(1), kit.MouseUpStep(), kit.Wait(3),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return resized == 1 && tilemap.size == vec2i{5, 4} }, "letting go of the selection resizes the tilemap to it"),
}
