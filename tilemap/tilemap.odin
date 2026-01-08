// Tile data (index array) manipulation, without any allocations by using user provided buffers
package tilemap

Flags :: enum {
    TILEMAP_FLAGS_NONE          = 0,
    // If set value is TILE_EMPTY, use it for overwriting
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

TilemapGetUsedRecti :: proc(tilemap: ^Tilemap)->recti{
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
        result: recti = { tilemap.position.x, tilemap.position.y, 0, 0 }
        return result
    }

    result: recti = { left, top, right - left +1, bottom - top +1 }
    return result
}

TilemapClampRecti :: proc(tilemap: ^Tilemap, relative_rect:recti)->recti {
    result:recti = relative_rect
    if (result.x + result.w < 0         \
        || result.y + result.h < 0      \
        || result.x >= tilemap.size.x   \
        || result.y >= tilemap.size.y
    ) {
        result.w = 0.0
        result.h = 0.0
        return result
    }

    if (result.x < 0){
        result.w -= result.x
        result.x = 0.0
    }
    if (result.y < 0){
        result.h -= result.y
        result.y = 0.0
    }
    if (result.x + result.w < 0){
        result.w -= tilemap.size.x - (result.x + result.w)
    }
    if (result.y + result.h < 0){
        result.h -= tilemap.size.y - (result.y + result.h)
    }

    return result
}

TilemapSetTile :: proc(tilemap: ^Tilemap, tile_pos:vec2i, tile_id:TileID){
    if (tile_id == TILE_INVALID) {
        return
    }
    x_inside:bool = tile_pos.x > -1 && tile_pos.x < tilemap.size.x
    y_inside:bool = tile_pos.y > -1 && tile_pos.y < tilemap.size.y
    if (!x_inside || !y_inside){
        return
    }
    pos:int = tile_pos.x + tile_pos.y * tilemap.size.x
    tilemap.grid[pos] = tile_id
}

TilemapSetTileWorld :: proc(tilemap: ^Tilemap, world_pos:vec2i, tile_id:TileID){
    tile_pos:vec2i = TilemapGetPositionWorld2Tile(tilemap, world_pos)
    TilemapSetTile(tilemap, tile_pos, tile_id)
}

TilemapGetPositionWorld2Tile :: proc(tilemap: ^Tilemap, world_pos:vec2i)->vec2i{
    x:int = world_pos.x - tilemap.position.x
    y:int = world_pos.y - tilemap.position.y
    if (x < 0){
        x -= tilemap.tile_size.x
    }
    if (y < 0){
        y -= tilemap.tile_size.y
    }
    
    x /= tilemap.tile_size.x
    y /= tilemap.tile_size.y
    result:vec2i = {x, y}
    return result
}

TilemapGetPositionTile2World :: proc(tilemap: ^Tilemap, tile_pos:vec2i)->vec2i {
    x:int = tile_pos.x * tilemap.tile_size.x + tilemap.position.x
    y:int = tile_pos.y * tilemap.tile_size.y + tilemap.position.y
    result:vec2i = {x, y}
    return result
}

TilemapGetVec2i2Recti :: proc(from:vec2i, to:vec2i)->recti {
    result:recti = {}

    if (to.x < from.x){
        result.x = to.x
        result.w = from.x - to.x
    } else
    {
        result.x = from.x
        result.w = to.x - from.x
    }

    if (to.y < from.y){
        result.y = to.y
        result.h = from.y - to.y
    } else
    {
        result.y = from.y
        result.h = to.y - from.y
    }

    result.w += 1
    result.h += 1
    return result
}

TilemapSetTileIdBlock :: proc(tilemap: ^Tilemap, left_x:int, top_y:int, columns:int, rows:int, tile_id:TileID){
    if (tile_id == TILE_INVALID) {
        return
    }

    from:vec2i = {
        left_x > 0 ? left_x : 0,
        top_y > 0 ? top_y : 0,
    }
    // excluding
    to:vec2i = {
        (from.x + columns) < tilemap.size.x ? (from.x + columns) : tilemap.size.x,
        (from.y + rows) < tilemap.size.y ? (from.y + rows) : tilemap.size.y,
    }

    for y in from.y..< to.y {
        for x in from.x..< to.x {
            i:int = x + y * tilemap.size.x
            tilemap.grid[i] = tile_id
        }
    }
}

TilemapResize :: proc(tilemap: ^Tilemap, relative_rect:recti, buffer:[]TileID){
    used_rect:recti = TilemapGetUsedRecti(tilemap)
    assert(len(buffer) > used_rect.w * used_rect.h)

    TilemapGetDataRecti(tilemap, used_rect, buffer)

    tilemap.position.x += relative_rect.x * tilemap.tile_size.x
    tilemap.position.y += relative_rect.y * tilemap.tile_size.y
    tilemap.size.x += (-relative_rect.x + relative_rect.w)
    tilemap.size.y += (-relative_rect.y + relative_rect.h)
    TilemapClear(tilemap)

    used_rect.x -= relative_rect.x
    used_rect.y -= relative_rect.y
    write_empty:bool = true
    TilemapSetDataRecti(tilemap, used_rect, buffer, write_empty)
}

TilemapGetDataRecti :: proc(tilemap: ^Tilemap, rect_section:recti, out_buffer:[]TileID){
    rect:recti = rect_section
    assert(rect.w * rect.h <= len(out_buffer))
    assert(rect.x >= 0)
    assert(rect.y >= 0)
    assert(rect.x + rect.w <= tilemap.size.x)
    assert(rect.y + rect.h <= tilemap.size.y)

    // place int 1D buffer
    i:u32 = 0
    for y in rect.y..< rect.y + rect.h {
        for x in rect.x..< rect.x + rect.w {
            value:TileID = tilemap.grid[x + y * tilemap.size.x]
            out_buffer[i] = value
            i += 1
        }
    }
}

TilemapSetDataRecti :: proc(tilemap: ^Tilemap, rect_section:recti, in_buffer:[]TileID, write_empty:bool){
    rect:recti = rect_section
    if (rect.w < 1 || rect.h < 1){return}
    if (rect.x > tilemap.size.x - 1){return}
    if (rect.y > tilemap.size.y - 1){return}

    right:int = rect.x + rect.w
    if (right - 1 < 0){return}
    bottom:int = rect.y + rect.h
    if (bottom - 1 < 0){return}

    tile_x:int = rect.x >= 0 ? rect.x : 0
    tile_y:int = rect.y >= 0 ? rect.y : 0
    tile_r:int = right < tilemap.size.x ? right : tilemap.size.x
    tile_b:int = bottom < tilemap.size.y ? bottom : tilemap.size.y

    for y in tile_y..< tile_b {
        diff_y:int = y - rect.y
        for x in tile_x..< tile_r {
            diff_x:int = x - rect.x
            data_i:u32 = cast(u32)(diff_x + diff_y * rect.w)
            tile_i:u32 = cast(u32)(x + y * tilemap.size.x)
            value:TileID = in_buffer[data_i]
            if ((value == TILE_EMPTY) && write_empty){
                tilemap.grid[tile_i] = value
            }
        }
    }
}

TilemapSetData :: proc(tilemap: ^Tilemap, in_data:[]TileID, data_width:u32, data_height:u32){
    width:u32 = data_width < cast(u32)tilemap.size.x ? data_width : cast(u32)tilemap.size.x
    height:u32 = data_height < cast(u32)tilemap.size.y ? data_height : cast(u32)tilemap.size.y

    for y in 0..< height {
        for x in 0..< width {
            data_i:u32 = x + y * data_width
            tile_i:u32 = x + y * cast(u32)tilemap.size.x
            value:TileID = in_data[data_i]
            tilemap.grid[tile_i] = value
        }
    }
}