#+private file
package demo_common

// The chain of the library, one level per demo: TileAtlas (texture positions) -> Tile (alternatives) -> Tileset (tiles by TileID) -> Tilemap (a grid of TileID).

import "core:math"
import tm ".."
import tm_kit "../kit"
import kit "../../demo_kit"

@(private="package")
demo_atlas: kit.Demo = {name = "atlas", init = common_init, draw = draw_atlas, script = script_draw}
@(private="package")
demo_tile: kit.Demo = {name = "tile", init = common_init, draw = draw_tile, script = script_draw}
@(private="package")
demo_tileset: kit.Demo = {name = "tileset", init = common_init, draw = draw_tileset, script = script_draw}
@(private="package")
demo_tilemap: kit.Demo = {name = "tilemap", init = common_init, draw = draw_tilemap, script = script_tilemap}
@(private="package")
demo_grid: kit.Demo = {name = "tilemap grid", init = common_init, draw = draw_grid, script = script_grid}
@(private="package")
demo_region: kit.Demo = {name = "tilemap region", init = common_init, draw = draw_region, script = script_region}

// the atlas as a grid of tiles that spreads apart and together: three levels of the same picture
draw_spread :: proc(ctx: ^kit.Context, title: string, id_of: proc(i: i32) -> TileID) {
	padding: i32 = 4 + i32(math.sin(get_animation_time(ctx, 0.2) * math.TAU) * 4.5)
	root_position: Vector2 = {100, 100}
	// 0th id is TILE_EMPTY
	id_offset: i32 = 1
	for y in 0 ..< ATLAS_SIZE.y {
		for x in 0 ..< ATLAS_SIZE.x {
			i: i32 = x + y * ATLAS_SIZE.x + id_offset
			draw_pos: Vector2 = {
				root_position.x + f32(x * (TILE_SIZE.x + padding)),
				root_position.y + f32(y * (TILE_SIZE.y + padding)),
			}
			tm_kit.DrawTileAtlas(ctx, &tile_atlas, id_of(i), draw_pos, tileset_texture)
		}
	}
	kit.DrawText(ctx, title, {10, 10}, 20, kit.BLACK)
}

// Example for drawing atlas directly by recreating whole texture
draw_atlas :: proc(ctx: ^kit.Context) {
	draw_spread(ctx, "draw_from_atlas", proc(i: i32) -> TileID { return TileID(i) })
}

draw_tile :: proc(ctx: ^kit.Context) {
	// Read tiles default 0th ID
	draw_spread(ctx, "draw_from_tiles: Tile -> TileAtlas", proc(i: i32) -> TileID { return tm.TileGetId(&tile_list[i]) })
}

draw_tileset :: proc(ctx: ^kit.Context) {
	// get a tile ID from tileset, then read the tile default 0th ID
	draw_spread(ctx, "draw_from_tileset: Tileset -> Tile -> TileAtlas", proc(i: i32) -> TileID {
		tile: TileID = tm.TilesetGetId(&tileset, TileID(i))
		return tm.TileGetId(&tile_list[tile])
	})
}

draw_tilemap :: proc(ctx: ^kit.Context) {
	skip_zero: bool = true
	tm_kit.DrawTilemap(ctx, &tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, tileset_texture)
	kit.DrawText(ctx, "draw_from_tilemap: Tilemap -> Tileset -> Tile -> TileAtlas", {10, 10}, 20, kit.BLACK)
}

hovered_id: TileID

draw_grid :: proc(ctx: ^kit.Context) {
	tm_kit.DrawTilemapGrid(ctx, &tilemap, kit.LIGHT_GRAY)
	tm_kit.DrawTilemapTileId(ctx, &tilemap, 10, kit.LIGHT_GRAY)
	mouse: vec2i = mouse_cell(ctx)
	// Read TileID under mouse position
	hovered_id = tm.TilemapGetTileWorld(&tilemap, mouse)
	// Draw a cell aligned to grid and ID under mouse
	tm_kit.DrawTilemapCellRect(ctx, &tilemap, mouse, hovered_id, 10, kit.GRAY)
	kit.DrawText(ctx, "draw_tilemap_grid: display as grid and IDs", {10, 10}, 20, kit.BLACK)
}

draw_region :: proc(ctx: ^kit.Context) {
	// Translate position to tile coordinates
	tile_position: vec2i = tm.TilemapGetWorld2Tile(&tilemap, mouse_cell(ctx))
	region: recti = {tile_position.x - 5, tile_position.y - 4, 5, 4}
	// Do not draw TILE_EMPTY ID
	skip_zero: bool = true
	tm_kit.DrawTilemapGrid(ctx, &tilemap, kit.LIGHT_GRAY)
	// Draw only tiles inside region
	tm_kit.DrawTilemapRecti(ctx, &tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, region, tileset_texture)
	// Draw rectangle around tiles
	tm_kit.DrawTilemapSelection(ctx, &tilemap, region, kit.GRAY)
	kit.DrawText(ctx, "draw_tilemap_region: reveal tiles with rectangle", {10, 10}, 20, kit.BLACK)
}

script_draw: []kit.Step = {
	kit.Wait(3),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return tileset_texture != kit.TEXTURE_NONE && tile_atlas.data[1] == Vector2{0, 0} && tile_atlas.data[2] == Vector2{16, 0} }, "the atlas knows the texture position of the tiles"),
	kit.Wait(30),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return ctx.backend.stats.draw_calls >= int(ATLAS_SIZE.x * ATLAS_SIZE.y) }, "every tile of the atlas is drawn"),
}

script_tilemap: []kit.Step = {
	kit.Wait(3),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return tm.TilemapGetTile(&tilemap, {2, 2}) == 1 && tm.TilemapGetTile(&tilemap, {0, 0}) == TILE_EMPTY }, "the hard coded map: tile 1 at 2,2, empty at 0,0"),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return tm.TilesetGetId(&tileset, 3) == 3 }, "the tileset maps a TileID to its tile"),
}

script_grid: []kit.Step = {
	kit.MoveTo({100 + 16 * 2 + 4, 100 + 16 * 2 + 4}),     // the cell 2,2
	kit.Wait(3),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return hovered_id == 1 }, "the tile id under the mouse is read from the tilemap"),
	kit.MoveTo({20, 20}),
	kit.Wait(3),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return hovered_id == TILE_INVALID }, "outside of the map the id is invalid"),
}

script_region: []kit.Step = {
	kit.MoveTo({100 + 16 * 8, 100 + 16 * 6}),
	kit.Wait(5),
	kit.Check(proc(ctx: ^kit.Context) -> bool { return ctx.backend.stats.draw_calls > 0 }, "the region around the mouse is drawn"),
}
