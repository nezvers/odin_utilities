// Implements drawing functionality speciffic to Raylib
package tilemap_raylib

import rl "vendor:raylib"
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

Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
Color :: rl.Color
Font :: rl.Font
Texture2D :: rl.Texture2D

// Draw 2D grid lines
DrawTilemapGrid :: proc(tilemap: ^Tilemap, color:Color){
    map_width:int = tilemap.size.x * tilemap.tile_size.x
    map_height:int = tilemap.size.y * tilemap.tile_size.y

    // Vertical lines
    for x in 0..< tilemap.size.x + 1 {
        cell_x:int = tilemap.position.x + x * tilemap.tile_size.x
        rl.DrawLine(cast(i32)cell_x, cast(i32)tilemap.position.y, cast(i32)(cell_x + 1), cast(i32)(tilemap.position.y + map_height), color)
    }

    // Horizontal lines
    for y in 0..< tilemap.size.y + 1 {
        cell_y:int = tilemap.position.y + y * tilemap.tile_size.y
        rl.DrawLine(cast(i32)tilemap.position.x, cast(i32)cell_y, cast(i32)(tilemap.position.x + map_width), cast(i32)cell_y, color)
    }
}

// Draw ID on tile positions for whole tilemap
DrawTilemapTileId :: proc(tilemap: ^Tilemap, font:Font, font_size:int, color:Color){
    text_offset_y:int = (tilemap.tile_size.y - font_size) / 2

    for y:int = 0; y < tilemap.size.y; y += 1 {
        cell_y:int = tilemap.position.y + y * tilemap.tile_size.y
        for x:int; x < tilemap.size.x; x += 1{
            cell_x:int = tilemap.position.x + x * tilemap.tile_size.x
            cell_i:int = x + y * tilemap.size.x
            assert(cell_i < len(tilemap.grid))

            cell_id:tm.TileID = tilemap.grid[cell_i]
            if cell_id == 0 {
                continue // skip EMPTY
            }
            text:cstring = rl.TextFormat("%d", cell_id)
            text_measure:Vector2 = rl.MeasureTextEx(font, text, cast(f32)font_size, 0.0)
            text_offset_x:int = (tilemap.tile_size.x - cast(int)text_measure.x) / 2
            text_position:Vector2 = {cast(f32)(cell_x + text_offset_x), cast(f32)(cell_y + text_offset_y + 1)}
            rl.DrawTextEx(font, text, text_position, cast(f32)font_size, 0.0, color)
        }
    }
}

// Draw rectangle around tile and draw provided ID
DrawTilemapCellRect :: proc(tilemap: ^Tilemap, world_pos:vec2i, tile_id:TileID, font:Font, font_size:int, color:Color){
    tile_pos:vec2i = tm.TilemapGetWorld2Tile(tilemap, world_pos)
    tile_x:int = tilemap.position.x + tile_pos.x * tilemap.tile_size.x
    tile_y:int = tilemap.position.y + tile_pos.y * tilemap.tile_size.y
    rl.DrawRectangleLines(cast(i32)tile_x, cast(i32)tile_y, cast(i32)tilemap.tile_size.x, cast(i32)tilemap.tile_size.y, color)

    text:cstring = rl.TextFormat("%d", tile_id)
    text_measure:Vector2 = rl.MeasureTextEx(font, text, cast(f32)font_size, 0.0)
    text_offset_x:int = (tilemap.tile_size.x - cast(int)text_measure.x) / 2
    text_offset_y:int = (tilemap.tile_size.y - font_size) / 2
    text_position:Vector2 = {cast(f32)(tile_x + text_offset_x), cast(f32)(tile_y + text_offset_y)}
    rl.DrawTextEx(font, text, text_position, cast(f32)font_size, 0.0, color)
}

// Draw lines around selection
DrawTilemapSelection :: proc(tilemap: ^Tilemap, rect:recti, color:Color){
    rectangle:Rectangle = {
        cast(f32)(tilemap.position.x + rect.x * tilemap.tile_size.x),
        cast(f32)(tilemap.position.y + rect.y * tilemap.tile_size.y),
        cast(f32)(rect.w * tilemap.tile_size.x),
        cast(f32)(rect.h * tilemap.tile_size.y),
    }
    rl.DrawRectangleLinesEx(rectangle, 1.0, color)
}


// skip_zero = true if TILE_EMPTY doesn't map to tile_atlas
DrawTilemap :: proc(
    tilemap: ^Tilemap, 
    tileset: ^Tileset, 
    tile_atlas: ^TileAtlas, 
    skip_zero:bool, 
    rand_type:TileRandType,
    texture: ^Texture2D,
){
    tex_rect:rectf = {0.0, 0.0, tile_atlas.tile_size.x, tile_atlas.tile_size.y}
    seed:u32 = tileset.random_seed

    for y:int = 0; y < tilemap.size.y; y += 1 {
        cell_y:int = tilemap.position.y + y * tilemap.tile_size.y
        for x:int = 0; x < tilemap.size.x; x += 1 {
            cell_x:int = tilemap.position.x + x * tilemap.tile_size.x
            cell_i:int = x + y * tilemap.size.x
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
            cell_pos:Vector2 = {cast(f32)cell_x, cast(f32)cell_y}
            tex_pos:Vector2 = tile_atlas.data[tile_id]
            tex_rect.x = tex_pos.x
            tex_rect.y = tex_pos.y
            rl.DrawTextureRec(texture^, transmute(Rectangle)tex_rect, cell_pos, rl.WHITE)
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
    texture: ^Texture2D,
){
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

    for y:int = rect.y; y < rect.h; y += 1 {
        cell_y:int = tilemap.position.y + y * tilemap.tile_size.y
        for x:int = rect.x; x < rect.w; x += 1 {
            cell_x:int = tilemap.position.x + x * tilemap.tile_size.x
            cell_i:int = x + y * tilemap.size.x
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
            cell_pos:Vector2 = {cast(f32)cell_x, cast(f32)cell_y}
            tex_pos:Vector2 = tile_atlas.data[tile_id]
            tex_rect.x = tex_pos.x
            tex_rect.y = tex_pos.y
            rl.DrawTextureRec(texture^, transmute(Rectangle)tex_rect, cell_pos, rl.WHITE)
        }
    }
}

// Drawing a tile from atlas directly
DrawTileAtlas :: proc(tile_atlas: ^TileAtlas, tile_id:TileID, draw_pos:Vector2, texture: ^Texture2D){
	tex_pos:Vector2 = tile_atlas.data[tile_id]
	tex_rect:Rectangle = {tex_pos.x,tex_pos.y, tile_atlas.tile_size.x, tile_atlas.tile_size.y}

	rl.DrawTextureRec(texture^, tex_rect, draw_pos, rl.WHITE)
}

DrawTile :: proc(tile: ^Tile, tile_atlas: ^TileAtlas, draw_pos:Vector2, texture: ^Texture2D){
    tile_id:TileID = tile.data[0]
    DrawTileAtlas(tile_atlas, tile_id, draw_pos, texture)
}

DrawTileRand :: proc(tile: ^Tile, tile_atlas: ^TileAtlas, draw_pos:Vector2, rand_type:TileRandType, seed: ^u32, texture: ^Texture2D){
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
