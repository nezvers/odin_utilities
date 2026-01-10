package tilemap_raylib

import rl "vendor:raylib"
import tm ".."

// vec2i :: tm.vec2i
// recti :: tm.recti
// TileID :: tm.TileID
// Tile :: tm.Tile
// Tileset :: tm.Tileset
// Tilemap :: tm.Tilemap
// TILE_EMPTY :: tm.TILE_EMPTY
// TILE_INVALID :: tm.TILE_INVALID

// Vector2 :: rl.Vector2
// Rectangle :: rl.Rectangle
// Color :: rl.Color
Texture2D :: rl.Texture2D

TileAtlas :: struct {
    data:[]Vector2,
    length:u32,
    capacity:u32,
    tile_size:Vector2,
    texture: ^Texture2D,
}

TileRandType :: enum {
    // Default TileID
    NONE,
    // Using TileSet.random_seed. it is deterministic, if used same grid drawing conditions
    SEED,
    // Using deterministic Tileset.random_seed + cell X & Y
    XY,
}

TileListInit :: proc(tile_atlas: ^TileAtlas, tile_size:Vector2, texture: ^Texture2D, buffer: []Vector2){
    tile_atlas.data = buffer
    tile_atlas.length = 0
    tile_atlas.capacity = cast(u32)len(buffer)
    tile_atlas.texture = texture
    tile_atlas.tile_size = tile_size
}

TileListInsert :: proc(tile_atlas: ^TileAtlas, texture_position:Vector2, index:u32){
    if (tile_atlas.length > tile_atlas.capacity - 1){
        assert(false)
        return
    }
    if (index > tile_atlas.length){
        assert(false)
        return
    }
    for i:u32 = tile_atlas.length -1; i > index; i -= 1 {
        tile_atlas.data[i + 1] = tile_atlas.data[i]
    }
    tile_atlas.data[index + 1] = tile_atlas.data[index]
    tile_atlas.data[index] = texture_position
    tile_atlas.length += 1
}

TileListRemoveIndex :: proc(tile_atlas: ^TileAtlas, index:u32){
    for i: = index; i < tile_atlas.length -1; i += 1{
        tile_atlas.data[i] = tile_atlas.data[i +1]
    }
    tile_atlas.length -= 1
}

// skip_zero = true if TILE_EMPTY doesn't map to tile_atlas
DrawTileset :: proc(
    tilemap: ^Tilemap, 
    tileset: ^Tileset, 
    tile_atlas: ^TileAtlas, 
    skip_zero:bool, 
    rand_type:TileRandType
){
    tex_rect:Rectangle = {0.0, 0.0, tile_atlas.tile_size.x, tile_atlas.tile_size.y}
    seed:u32 = tileset.random_seed

    for y:int = 0; y < tilemap.size.y; y += 1 {
        cell_y:int = tilemap.position.y + y * tilemap.tile_size.y
        for x:int = 0; x < tilemap.size.x; x += 1 {
            cell_x:int = tilemap.size.x + x * tilemap.tile_size.x
            cell_i:int = x + y * tilemap.size.x
            cell_id:TileID = tilemap.grid[cell_i]
            if (cell_id == TILE_EMPTY && skip_zero){
                continue
            }

            tile_id:TileID
            switch(rand_type){
                case TileRandType.NONE:
                    tile_id = tm.TilesetGetTile(tileset, cell_id)
                case TileRandType.SEED:
                    tile_id = tm.TilesetGetTileAltRandom(tileset, cell_id, &seed)
                case TileRandType.XY:
                    tile_id = tm.TilesetGetTileAltDeterministic(tileset, cell_id, x, y)
            }

            cell_pos:Vector2 = {cast(f32)cell_x, cast(f32)cell_y}
            tex_pos:Vector2 = tile_atlas.data[tile_id]
            tex_rect.x = tex_pos.x
            tex_rect.y = tex_pos.y
            rl.DrawTextureRec(tile_atlas.texture^, tex_rect, cell_pos, rl.WHITE)
        }
    }
}

DrawTilesetRecti :: proc(
    tilemap: ^Tilemap, 
    tileset: ^Tileset, 
    tile_atlas: ^TileAtlas, 
    skip_zero:bool, 
    rand_type:TileRandType, 
    region_rect:recti
){
    if region_rect.x < 0 {
        region_rect.w += region_rect.x
        region_rect.x = 0
    }
    if region_rect.y < 0 {
        region_rect.h += region_rect.y
        region_rect.y = 0
    }
    region_rect.w += region_rect.x
    region_rect.h += region_rect.y
    if region_rect.w > tilemap.size.x {
        region_rect.w = tilemap.size.x
    }
    if region_rect.h > tilemap.size.y {
        region_rect.h = tilemap.size.y
    }

    tex_rect:Rectangle = {0.0, 0.0, tile_atlas.tile_size.x, tile_atlas.tile_size.y}
    seed:u32 = tileset.random_seed

    for y:int = region_rect.y; y < region_rect.h; y += 1 {
        cell_y:int = tilemap.position.y + y * tilemap.tile_size.y
        for x:int = region_rect.x; x < region_rect.w; x += 1 {
            cell_x:int = tilemap.size.x + x * tilemap.tile_size.x
            cell_i:int = x + y * tilemap.size.x
            cell_id:TileID = tilemap.grid[cell_i]
            if (cell_id == TILE_EMPTY && skip_zero){
                continue
            }

            tile_id:TileID
            switch(rand_type){
                case TileRandType.NONE:
                    tile_id = tm.TilesetGetTile(tileset, cell_id)
                case TileRandType.SEED:
                    tile_id = tm.TilesetGetTileAltRandom(tileset, cell_id, &seed)
                case TileRandType.XY:
                    tile_id = tm.TilesetGetTileAltDeterministic(tileset, cell_id, x, y)
            }

            cell_pos:Vector2 = {cast(f32)cell_x, cast(f32)cell_y}
            tex_pos:Vector2 = tile_atlas.data[tile_id]
            tex_rect.x = tex_pos.x
            tex_rect.y = tex_pos.y
            rl.DrawTextureRec(tile_atlas.texture^, tex_rect, cell_pos, rl.WHITE)
        }
    }
}