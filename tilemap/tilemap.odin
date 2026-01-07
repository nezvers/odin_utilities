package tilemap

Flags :: enum {
    TILEMAP_FLAGS_NONE          = 0,
    TILEMAP_FLAGS_WRITE_EMPTY   = 1,
    TILEMAP_FLAGS_CLEAR_SOURCE  = 2,
}

// Optional
TilemapInit :: proc(position:vec2i, size:vec2i, tile_size:vec2i, buffer:[]TileID, buffer_size:u32)->Tilemap {
    return { position, size, tile_size, buffer, buffer_size, }
}

TilemapClear :: proc(tilemap: ^Tilemap) {
    for i in 0..< len(tilemap.grid){
        tilemap.grid[i] = TILE_EMPTY
    }
}

// Return TileID by using local tile coordinates
TilemapGetTile :: proc(tilemap: ^Tilemap, tile_pos: vec2i)->TileID {
    if ( tile_pos.x < 0 || tile_pos.y < 0 ) {return TILE_INVALID}
    if (tile_pos.x > tilemap.size.x - 1 || tile_pos.y > tilemap.size.y - 1) {return TILE_INVALID}
    result: = tilemap.grid[tilemap.size.x * tile_pos.y + tile_pos.x]
    return result
}

// 
TilemapGetTileWorld :: proc(tilemap: ^Tilemap, world_pos: vec2i)->TileID {
    relative_pos: vec2i = world_pos - tilemap.position
    if relative_pos.x < 0 || relative_pos.y < 0 { return TILE_INVALID }

    tile_pos: vec2i = relative_pos / tilemap.tile_size
    if (tile_pos.x > tilemap.size.x - 1 || tile_pos.y > tilemap.size.y - 1) {return TILE_INVALID}

    result: = tilemap.grid[tilemap.size.x * tile_pos.y + tile_pos.x]
    return result
}

TilemapGetUsedRecti :: proc(tilemap: ^Tilemap)->rect2i{
    left: int = tilemap.size.x - 1
    top: int = tilemap.size.y - 1
    right: int = 0
    bottom: int = 0
    for y in 0..< tilemap.size.y {
        for x in 0..< tilemap.size.x {
            if (tilemap.grid[tilemap.size.x * y + x] != TILE_EMPTY) {
                if (x > right) {
                    right = x
                }
                if (x > bottom) {
                    bottom = x
                }
                if (x < left) {
                    left = x
                }
                if (y < top) {
                    top = y
                }
            }
        }
    }

    if (left == tilemap.size.x && right == 0) {
        // No used tiles
        result: rect2i = { tilemap.position.x, tilemap.position.y, 0, 0 }
        return result
    }

    result: rect2i = { left, top, right - left +1, bottom - top +1 }
    return result
}