package tilemap

Flags :: enum {
    TILEMAP_FLAGS_NONE          = 0,
    TILEMAP_FLAGS_WRITE_EMPTY   = 1,
    TILEMAP_FLAGS_CLEAR_SOURCE  = 2,
}

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
    return tilemap.grid[tilemap.size.x * tile_pos.y + tile_pos.x]
}

TilemapGetTileWorld :: proc(tilemap: ^Tilemap, world_pos: vec2i)->TileID {
    relative_pos: vec2i = world_pos - tilemap.position
    if relative_pos.x < 0 || relative_pos.y < 0 { return TILE_INVALID }

    tile_pos: vec2i = relative_pos / tilemap.tile_size
    if (tile_pos.x > tilemap.size.x - 1 || tile_pos.y > tilemap.size.y - 1) {return TILE_INVALID}

    return tilemap.grid[tilemap.size.x * tile_pos.y + tile_pos.x]
}
