package tilemap_karl2d

import "../../karl2d"
Vec2 :: karl2d.Vec2
Rect :: karl2d.Rect
Color :: karl2d.Color
Font :: karl2d.Font
Texture :: karl2d.Texture

import tm ".."
vec2i :: tm.vec2i
recti :: tm.recti
rectf :: tm.rectf
TileAtlas :: tm.TileAtlas
TileID :: tm.TileID
Tile :: tm.Tile
Tileset :: tm.Tileset
Tilemap :: tm.Tilemap
TileRandType :: tm.TileRandType
TILE_EMPTY :: tm.TILE_EMPTY
TILE_INVALID :: tm.TILE_INVALID

import "core:fmt"

// Drawing a tile from atlas directly
DrawTileAtlas :: proc(tile_atlas: ^TileAtlas, tile_id:TileID, draw_pos:Vec2, texture: ^Texture) {
	tex_pos:Vec2 = tile_atlas.data[tile_id]
	tex_rect:Rect = {tex_pos.x,tex_pos.y, tile_atlas.tile_size.x, tile_atlas.tile_size.y}

	// karl2d.DrawTextureRec(texture^, tex_rect, draw_pos, karl2d.WHITE)
    karl2d.draw_texture_section(texture^, tex_rect, draw_pos)
}

DrawTile :: proc(tile: ^Tile, tile_atlas: ^TileAtlas, draw_pos:Vec2, texture: ^Texture, subtile: TileID = 0) {
	tile_id:TileID = tile.data[subtile]
    DrawTileAtlas(tile_atlas, tile_id, draw_pos, texture)
}

DrawTileRand :: proc(tile: ^Tile, tile_atlas: ^TileAtlas, draw_pos:Vec2, rand_type:TileRandType, seed: ^u32, texture: ^Texture){
    tile_id:TileID
    switch(rand_type){
    case TileRandType.NONE:
        tile_id = tm.TileGetId(tile)
    case TileRandType.SEED:
        tile_id = tm.TileGetRandomSeed(tile, seed)
    case TileRandType.XY:
        tile_id = tm.TileGetRandomXY(tile, seed^, cast(int)draw_pos.x, cast(int)draw_pos.y)
    }
    DrawTileAtlas(tile_atlas, tile_id, draw_pos, texture)
}

// Draw 2D grid lines
DrawTilemapGrid :: proc(tilemap: ^Tilemap, color:Color){
    map_width:i32 = tilemap.size.x * tilemap.tile_size.x
    map_height:i32 = tilemap.size.y * tilemap.tile_size.y

    // Vertical lines
    for x in 0..< tilemap.size.x + 1 {
        cell_x:i32 = tilemap.position.x + x * tilemap.tile_size.x
		// TODO: check if need end.x + 1
		from:Vec2 = {cast(f32)cell_x, cast(f32)tilemap.position.y}
		to:Vec2 = {cast(f32)(cell_x + 1), cast(f32)(tilemap.position.y + map_height)}
		karl2d.draw_line(from, to, 1, color)
    }

    // Horizontal lines
    for y in 0..< tilemap.size.y + 1 {
        cell_y:i32 = tilemap.position.y + y * tilemap.tile_size.y
		// TODO: check if need end.x + 1
		from:Vec2 = {cast(f32)tilemap.position.x, cast(f32)cell_y}
		to:Vec2 = {cast(f32)(tilemap.position.x + map_width), cast(f32)cell_y}
		karl2d.draw_line(from, to, 1, color)
    }
}

// Draw ID on tile positions for whole tilemap
DrawTilemapTileId :: proc(tilemap: ^Tilemap, font:Font, font_size:f32, color:Color){
    text_offset_y:i32 = (tilemap.tile_size.y - cast(i32)font_size) / 2

    for y:i32 = 0; y < tilemap.size.y; y += 1 {
        cell_y:i32 = tilemap.position.y + y * tilemap.tile_size.y
        for x:i32; x < tilemap.size.x; x += 1{
            cell_x:i32 = tilemap.position.x + x * tilemap.tile_size.x
            cell_i:i32 = x + y * tilemap.size.x
            assert(cell_i < cast(i32)len(tilemap.grid))

            cell_id:tm.TileID = tilemap.grid[cell_i]
            if cell_id == 0 {
                continue // skip EMPTY
            }
            text:string = fmt.tprintf("%v", cell_id)
            text_measure:Vec2 = karl2d.measure_text(text, font_size, font)
            text_offset_x:i32 = (tilemap.tile_size.x - cast(i32)text_measure.x) / 2
            text_position:Vec2 = {cast(f32)(cell_x + text_offset_x), cast(f32)(cell_y + text_offset_y + 1)}
            karl2d.draw_text(text, text_position, font_size, color, font)
        }
    }
}

// Draw rectangle around tile and draw provided ID
DrawTilemapCellRect :: proc(tilemap: ^Tilemap, world_pos:vec2i, tile_id:TileID, font:Font, font_size:f32, color:Color) {
    tile_pos:vec2i = tm.TilemapGetWorld2Tile(tilemap, world_pos)
    tile_x:i32 = tilemap.position.x + tile_pos.x * tilemap.tile_size.x
    tile_y:i32 = tilemap.position.y + tile_pos.y * tilemap.tile_size.y
	rect:Rect = {cast(f32)tile_x, cast(f32)tile_y, cast(f32)tilemap.tile_size.x, cast(f32)tilemap.tile_size.y}
	karl2d.draw_rect_outline(rect, 1, color)

	text:string = fmt.tprintf("%v", tile_id)
	text_measure:Vec2 = karl2d.measure_text(text, font_size, font)
    text_offset_x:i32 = (tilemap.tile_size.x - cast(i32)text_measure.x) / 2
    text_offset_y:i32 = (tilemap.tile_size.y - cast(i32)font_size) / 2
    text_position:Vec2 = {cast(f32)(tile_x + text_offset_x), cast(f32)(tile_y + text_offset_y)}
    karl2d.draw_text(text, text_position, font_size, color, font)
}

// Draw lines around selection
DrawTilemapSelection :: proc(tilemap: ^Tilemap, rect:recti, color:Color) {
    rectangle:Rect = {
        cast(f32)(tilemap.position.x + rect.x * tilemap.tile_size.x),
        cast(f32)(tilemap.position.y + rect.y * tilemap.tile_size.y),
        cast(f32)(rect.w * tilemap.tile_size.x),
        cast(f32)(rect.h * tilemap.tile_size.y),
    }
	karl2d.draw_rect_outline(rectangle, 1, color)
}


// skip_zero = true if TILE_EMPTY doesn't map to tile_atlas
DrawTilemap :: proc(
    tilemap: ^Tilemap, 
    tileset: ^Tileset, 
    tile_atlas: ^TileAtlas, 
    skip_zero:bool, 
    rand_type:TileRandType,
    texture: ^Texture,
) {
    tex_rect:rectf = {0.0, 0.0, tile_atlas.tile_size.x, tile_atlas.tile_size.y}
    seed:u32 = tileset.random_seed

    for y:i32 = 0; y < tilemap.size.y; y += 1 {
        cell_y:i32 = tilemap.position.y + y * tilemap.tile_size.y
        for x:i32 = 0; x < tilemap.size.x; x += 1 {
            cell_x:i32 = tilemap.position.x + x * tilemap.tile_size.x
            cell_i:i32 = x + y * tilemap.size.x
            cell_id:TileID = tilemap.grid[cell_i]
            if (cell_id == TILE_EMPTY && skip_zero){
                continue
            }

            tile_id:TileID
            switch(rand_type){
            case TileRandType.NONE:
                tile_id = tm.TilesetGetId(tileset, cell_id)
            case TileRandType.SEED:
                tile_id = tm.TilesetGetTileAltRandom(tileset, cell_id, &seed)
            case TileRandType.XY:
                tile_id = tm.TilesetGetTileAltDeterministic(tileset, cell_id, x, y)
            }

            // Framework specific implementation
            cell_pos:Vec2 = {cast(f32)cell_x, cast(f32)cell_y}
            tex_pos:Vec2 = tile_atlas.data[tile_id]
            tex_rect.x = tex_pos.x
            tex_rect.y = tex_pos.y
			karl2d.draw_texture_section(texture^, cast(Rect)tex_rect, cell_pos)
        }
    }
}

// Draw selected region. For optimization draw only what is on a screen.
DrawTilemapRecti :: proc(
    tilemap: ^Tilemap, 
    tileset: ^Tileset, 
    tile_atlas: ^TileAtlas, 
    skip_zero:bool, 
    rand_type:TileRandType, 
    region_rect:recti,
    texture: ^Texture,
) {
    rect:recti = region_rect
    if rect.x < 0 {
        rect.w += rect.x
        rect.x = 0
    }
    if rect.y < 0 {
        rect.h += rect.y
        rect.y = 0
    }
    rect.w += rect.x
    rect.h += rect.y
    if rect.w > tilemap.size.x {
        rect.w = tilemap.size.x
    }
    if rect.h > tilemap.size.y {
        rect.h = tilemap.size.y
    }

    tex_rect:rectf = {0.0, 0.0, tile_atlas.tile_size.x, tile_atlas.tile_size.y}
    seed:u32 = tileset.random_seed

    for y:i32 = rect.y; y < rect.h; y += 1 {
        cell_y:i32 = tilemap.position.y + y * tilemap.tile_size.y
        for x:i32 = rect.x; x < rect.w; x += 1 {
            cell_x:i32 = tilemap.position.x + x * tilemap.tile_size.x
            cell_i:i32 = x + y * tilemap.size.x
            cell_id:TileID = tilemap.grid[cell_i]
            if (cell_id == TILE_EMPTY && skip_zero){
                continue
            }

            tile_id:TileID
            switch(rand_type){
            case TileRandType.NONE:
                tile_id = tm.TilesetGetId(tileset, cell_id)
            case TileRandType.SEED:
                tile_id = tm.TilesetGetTileAltRandom(tileset, cell_id, &seed)
            case TileRandType.XY:
                tile_id = tm.TilesetGetTileAltDeterministic(tileset, cell_id, x, y)
            }

            // Framework specific implementation
            cell_pos:Vec2 = {cast(f32)cell_x, cast(f32)cell_y}
            tex_pos:Vec2 = tile_atlas.data[tile_id]
            tex_rect.x = tex_pos.x
            tex_rect.y = tex_pos.y
			karl2d.draw_texture_section(texture^, cast(Rect)tex_rect, cell_pos)
        }
    }
}