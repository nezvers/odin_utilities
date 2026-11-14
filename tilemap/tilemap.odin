// Tile data (index array) manipulation, without any allocations by using user provided buffers
package tilemap

import "core:math"
import "core:testing"

Flags :: enum {
    NONE          = 0,
    // If set value is TILE_EMPTY, use it for overwriting
    WRITE_EMPTY   = 1,
    CLEAR_SOURCE  = 2,
}

// Optional initialization through a function
TilemapInit :: proc(position:vec2i, size:vec2i, tile_size:vec2i, buffer:[]TileID)->Tilemap {
    return { position, size, tile_size, buffer }
}

// Get rectangle representing tilemap's size
TilemapRecti :: proc(tilemap: ^Tilemap)->recti {
    return {0, 0, tilemap.size.x, tilemap.size.y}
}

// Writes TILE_EMPTY on all cells
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

// Get TileID by world coordinates
TilemapGetTileWorld :: proc(tilemap: ^Tilemap, world_pos: vec2i)->TileID {
    tile_pos: vec2i = TilemapGetWorld2Tile(tilemap, world_pos)
    result: = TilemapGetTile(tilemap, tile_pos)
    return result
}

// Get rectangle region of populated tiles 
TilemapGetUsedRecti :: proc(tilemap: ^Tilemap)->recti {
    // start past the far edge so the first used tile always pulls the bounds in
    left: i32 = tilemap.size.x
    top: i32 = tilemap.size.y
    right: i32 = 0
    bottom: i32 = 0
    for y:i32 = 0; y < tilemap.size.y; y += 1 {
        for x:i32 = 0; x < tilemap.size.x; x += 1 {
            if (tilemap.grid[tilemap.size.x * y + x] != TILE_EMPTY) {
                if (x > right) {
                    right = x
                }
                if (y > bottom) {
                    bottom = y
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

    if (left > right) {
        // No used tiles
        return {}
    }

    result: recti = { left, top, right - left +1, bottom - top +1 }
    return result
}

// Get rectangle that is clipped to tilemap
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

    // intersection with the tilemap area
    right:i32 = math.min(result.x + result.w, tilemap.size.x)
    bottom:i32 = math.min(result.y + result.h, tilemap.size.y)
    result.x = math.max(result.x, 0)
    result.y = math.max(result.y, 0)
    result.w = math.max(right - result.x, 0)
    result.h = math.max(bottom - result.y, 0)

    return result
}

// Set tile id in tile coordinates
TilemapSetTile :: proc(tilemap: ^Tilemap, tile_pos:vec2i, tile_id:TileID) {
    if (tile_id == TILE_INVALID) {
        return
    }
    x_inside:bool = tile_pos.x > -1 && tile_pos.x < tilemap.size.x
    y_inside:bool = tile_pos.y > -1 && tile_pos.y < tilemap.size.y
    if (!x_inside || !y_inside){
        return
    }
    pos:i32 = tile_pos.x + tile_pos.y * tilemap.size.x
    tilemap.grid[pos] = tile_id
}

// Set tile id in world coordinates
TilemapSetTileWorld :: proc(tilemap: ^Tilemap, world_pos:vec2i, tile_id:TileID) {
    tile_pos:vec2i = TilemapGetWorld2Tile(tilemap, world_pos)
    TilemapSetTile(tilemap, tile_pos, tile_id)
}

// Translate world coordinates to tile coordinates
TilemapGetWorld2Tile :: proc(tilemap: ^Tilemap, world_pos:vec2i)->vec2i {
    // floored division, so every cell is the same size on both sides of zero
    x:i32 = math.floor_div(world_pos.x - tilemap.position.x, tilemap.tile_size.x)
    y:i32 = math.floor_div(world_pos.y - tilemap.position.y, tilemap.tile_size.y)
    result:vec2i = {x, y}
    return result
}

// Translate tile coordinates to world coordinates
TilemapGetTile2World :: proc(tilemap: ^Tilemap, tile_pos:vec2i)->vec2i {
    x:i32 = tile_pos.x * tilemap.tile_size.x + tilemap.position.x
    y:i32 = tile_pos.y * tilemap.tile_size.y + tilemap.position.y
    result:vec2i = {x, y}
    return result
}

// Fills TileID in region
TilemapSetTileIdBlock :: proc(tilemap: ^Tilemap, left_x:i32, top_y:i32, columns:i32, rows:i32, tile_id:TileID) {
    if (tile_id == TILE_INVALID) {
        return
    }

    from:vec2i = {
        left_x > 0 ? left_x : 0,
        top_y > 0 ? top_y : 0,
    }
    // excluding. The end is measured from the requested start, so a block hanging over the edge is cut and not shifted
    to:vec2i = {
        (left_x + columns) < tilemap.size.x ? (left_x + columns) : tilemap.size.x,
        (top_y + rows) < tilemap.size.y ? (top_y + rows) : tilemap.size.y,
    }

    for y: = from.y; y < to.y; y += 1 {
        for x: = from.x; x < to.x; x += 1 {
            i:i32 = x + y * tilemap.size.x
            tilemap.grid[i] = tile_id
        }
    }
}

// Change position & size to fit rectangle, excess gets clipped
// Requires a temporary buffer to hold used rectangle
TilemapResize :: proc(tilemap: ^Tilemap, relative_rect:recti, temp_buffer:[]TileID) {
    used_rect:recti = TilemapGetUsedRecti(tilemap)
    assert(cast(i32)len(temp_buffer) >= used_rect.w * used_rect.h)

    TilemapGetRegionData(tilemap, used_rect, temp_buffer)
    // TODO: assert that current tilemap.grid is big enough for the new size
    tilemap.position.x += relative_rect.x * tilemap.tile_size.x
    tilemap.position.y += relative_rect.y * tilemap.tile_size.y
    tilemap.size.x = relative_rect.w
    tilemap.size.y = relative_rect.h
    TilemapClear(tilemap)

    used_rect.x -= relative_rect.x
    used_rect.y -= relative_rect.y
    write_empty:bool = true
    TilemapSetRegionData(tilemap, used_rect, temp_buffer, write_empty)
}

// Copy TileID from region and place as 1D array in out_buffer
TilemapGetRegionData :: proc(tilemap: ^Tilemap, rect_section:recti, out_buffer:[]TileID) {
    rect:recti = rect_section
    buffer_len: = cast(i32)len(out_buffer)
    assert(rect.w * rect.h <= buffer_len)
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

// Copy TileID from in_buffer assuming data is 1D array representing provided region in tile coordinates
TilemapSetRegionData :: proc(tilemap: ^Tilemap, rect_section:recti, in_buffer:[]TileID, write_empty:bool) {
    rect:recti = rect_section
    if (rect.w < 1 || rect.h < 1){return}
    if (rect.x > tilemap.size.x - 1){return}
    if (rect.y > tilemap.size.y - 1){return}

    right:i32 = rect.x + rect.w
    if (right - 1 < 0){return}
    bottom:i32 = rect.y + rect.h
    if (bottom - 1 < 0){return}

    tile_x:i32 = rect.x >= 0 ? rect.x : 0
    tile_y:i32 = rect.y >= 0 ? rect.y : 0
    tile_r:i32 = right < tilemap.size.x ? right : tilemap.size.x
    tile_b:i32 = bottom < tilemap.size.y ? bottom : tilemap.size.y

    for y:i32 = tile_y; y < tile_b; y += 1 {
        diff_y:i32 = y - rect.y
        for x:i32 = tile_x; x < tile_r; x += 1 {
            diff_x:i32 = x - rect.x
            data_i:u32 = cast(u32)(diff_x + diff_y * rect.w)
            value:TileID = in_buffer[data_i]
            if ((value == TILE_EMPTY) && !write_empty){
                continue
            }
            tile_i:u32 = cast(u32)(x + y * tilemap.size.x)
            tilemap.grid[tile_i] = value
        }
    }
}

// Copy TileID as 1D array from in_buffer starting from 0th index
TilemapSetData :: proc(tilemap: ^Tilemap, in_buffer:[]TileID, data_width:u32, data_height:u32) {
    width:u32 = data_width < cast(u32)tilemap.size.x ? data_width : cast(u32)tilemap.size.x
    height:u32 = data_height < cast(u32)tilemap.size.y ? data_height : cast(u32)tilemap.size.y

    for y:u32 = 0; y < height; y += 1 {
        for x:u32 = 0; x < width; x += 1 {
            data_i:u32 = x + y * data_width
            tile_i:u32 = x + y * cast(u32)tilemap.size.x
            value:TileID = in_buffer[data_i]
            tilemap.grid[tile_i] = value
        }
    }
}

// --- Tests ---

@(private="file")
make_test_map :: proc(buffer: []TileID) -> Tilemap {
    return TilemapInit({100, 50}, {6, 4}, {16, 16}, buffer)
}

@(test)
test_tilemap_get_set_and_bounds :: proc(t: ^testing.T) {
    buffer: [24]TileID
    tilemap: Tilemap = make_test_map(buffer[:])
    testing.expect_value(t, TilemapRecti(&tilemap), recti{0, 0, 6, 4})

    TilemapSetTile(&tilemap, {2, 1}, 7)
    testing.expect_value(t, TilemapGetTile(&tilemap, {2, 1}), TileID(7))
    testing.expect_value(t, buffer[2 + 1 * 6], TileID(7))                                  // row major
    testing.expect_value(t, TilemapGetTile(&tilemap, {0, 0}), TILE_EMPTY)

    testing.expect_value(t, TilemapGetTile(&tilemap, {-1, 0}), TILE_INVALID)
    testing.expect_value(t, TilemapGetTile(&tilemap, {6, 0}), TILE_INVALID)
    testing.expect_value(t, TilemapGetTile(&tilemap, {0, 4}), TILE_INVALID)

    TilemapSetTile(&tilemap, {9, 9}, 3)                                                    // outside: ignored
    TilemapSetTile(&tilemap, {-1, 0}, 3)
    TilemapSetTile(&tilemap, {0, 0}, TILE_INVALID)                                         // the invalid id is never written
    testing.expect_value(t, TilemapGetTile(&tilemap, {0, 0}), TILE_EMPTY)
    for id in buffer { testing.expect(t, id == TILE_EMPTY || id == 7) }

    TilemapClear(&tilemap)
    testing.expect_value(t, TilemapGetTile(&tilemap, {2, 1}), TILE_EMPTY)
}

@(test)
test_tilemap_world_and_tile_coordinates :: proc(t: ^testing.T) {
    buffer: [24]TileID
    tilemap: Tilemap = make_test_map(buffer[:])

    testing.expect_value(t, TilemapGetTile2World(&tilemap, {2, 1}), vec2i{132, 66})
    testing.expect_value(t, TilemapGetWorld2Tile(&tilemap, {132, 66}), vec2i{2, 1})
    testing.expect_value(t, TilemapGetWorld2Tile(&tilemap, {147, 81}), vec2i{2, 1})        // anywhere inside the cell
    testing.expect_value(t, TilemapGetWorld2Tile(&tilemap, {148, 82}), vec2i{3, 2})

    // left and above the map the cells keep counting down, with no repeated cell around zero
    testing.expect_value(t, TilemapGetWorld2Tile(&tilemap, {99, 50}), vec2i{-1, 0})
    testing.expect_value(t, TilemapGetWorld2Tile(&tilemap, {84, 50}), vec2i{-1, 0})        // exactly one tile to the left
    testing.expect_value(t, TilemapGetWorld2Tile(&tilemap, {83, 50}), vec2i{-2, 0})
    testing.expect_value(t, TilemapGetWorld2Tile(&tilemap, {100, 34}), vec2i{0, -1})

    TilemapSetTileWorld(&tilemap, {133, 67}, 4)
    testing.expect_value(t, TilemapGetTile(&tilemap, {2, 1}), TileID(4))
    testing.expect_value(t, TilemapGetTileWorld(&tilemap, {133, 67}), TileID(4))
    testing.expect_value(t, TilemapGetTileWorld(&tilemap, {84, 50}), TILE_INVALID)
    testing.expect_value(t, TilemapGetTileWorld(&tilemap, {99, 50}), TILE_INVALID)
}

@(test)
test_tilemap_used_rect :: proc(t: ^testing.T) {
    buffer: [24]TileID
    tilemap: Tilemap = make_test_map(buffer[:])

    empty: recti = TilemapGetUsedRecti(&tilemap)
    testing.expect_value(t, empty.w, i32(0))
    testing.expect_value(t, empty.h, i32(0))

    TilemapSetTile(&tilemap, {1, 1}, 5)
    TilemapSetTile(&tilemap, {4, 2}, 5)
    testing.expect_value(t, TilemapGetUsedRecti(&tilemap), recti{1, 1, 4, 2})

    TilemapClear(&tilemap)
    TilemapSetTile(&tilemap, {0, 0}, 5)
    testing.expect_value(t, TilemapGetUsedRecti(&tilemap), recti{0, 0, 1, 1})

    TilemapClear(&tilemap)
    TilemapSetTile(&tilemap, {5, 3}, 5)                                                    // the very last cell
    testing.expect_value(t, TilemapGetUsedRecti(&tilemap), recti{5, 3, 1, 1})
}

@(test)
test_tilemap_clamp_recti :: proc(t: ^testing.T) {
    buffer: [24]TileID
    tilemap: Tilemap = make_test_map(buffer[:])

    testing.expect_value(t, TilemapClampRecti(&tilemap, {1, 1, 2, 2}), recti{1, 1, 2, 2})  // inside: unchanged
    testing.expect_value(t, TilemapClampRecti(&tilemap, {-2, -1, 5, 4}), recti{0, 0, 3, 3})
    testing.expect_value(t, TilemapClampRecti(&tilemap, {4, 2, 5, 5}), recti{4, 2, 2, 2})  // hangs over the right and bottom
    testing.expect_value(t, TilemapClampRecti(&tilemap, {-3, -3, 20, 20}), recti{0, 0, 6, 4})

    far: recti = TilemapClampRecti(&tilemap, {10, 10, 2, 2})
    testing.expect_value(t, far.w, i32(0))
    testing.expect_value(t, far.h, i32(0))
}

@(test)
test_tilemap_set_block :: proc(t: ^testing.T) {
    buffer: [24]TileID
    tilemap: Tilemap = make_test_map(buffer[:])

    TilemapSetTileIdBlock(&tilemap, 1, 1, 2, 2, 9)
    for y in i32(0) ..< 4 {
        for x in i32(0) ..< 6 {
            inside: bool = x >= 1 && x <= 2 && y >= 1 && y <= 2
            testing.expect_value(t, TilemapGetTile(&tilemap, {x, y}), TileID(9) if inside else TILE_EMPTY)
        }
    }

    TilemapClear(&tilemap)
    TilemapSetTileIdBlock(&tilemap, -1, -1, 3, 3, 8)                                       // hangs over the corner: only a 2x2 part is inside
    testing.expect_value(t, TilemapGetTile(&tilemap, {0, 0}), TileID(8))
    testing.expect_value(t, TilemapGetTile(&tilemap, {1, 1}), TileID(8))
    testing.expect_value(t, TilemapGetTile(&tilemap, {2, 2}), TILE_EMPTY)                  // the block does not slide into the map

    TilemapClear(&tilemap)
    TilemapSetTileIdBlock(&tilemap, 4, 2, 10, 10, 6)                                       // and the far side is cut off
    testing.expect_value(t, TilemapGetTile(&tilemap, {5, 3}), TileID(6))
    TilemapSetTileIdBlock(&tilemap, 0, 0, 2, 2, TILE_INVALID)
    testing.expect_value(t, TilemapGetTile(&tilemap, {0, 0}), TILE_EMPTY)
}

@(test)
test_tilemap_region_data :: proc(t: ^testing.T) {
    buffer: [24]TileID
    tilemap: Tilemap = make_test_map(buffer[:])
    TilemapSetTile(&tilemap, {1, 1}, 1)
    TilemapSetTile(&tilemap, {2, 1}, 2)
    TilemapSetTile(&tilemap, {1, 2}, 3)

    region: [4]TileID
    TilemapGetRegionData(&tilemap, {1, 1, 2, 2}, region[:])
    testing.expect_value(t, region, [4]TileID{1, 2, 3, TILE_EMPTY})

    other_buffer: [24]TileID
    other: Tilemap = make_test_map(other_buffer[:])
    TilemapSetTile(&other, {4, 2}, 9)
    TilemapSetRegionData(&other, {4, 1, 2, 2}, region[:], false)                           // empty tiles in the data keep what was there
    testing.expect_value(t, TilemapGetTile(&other, {4, 1}), TileID(1))
    testing.expect_value(t, TilemapGetTile(&other, {5, 1}), TileID(2))
    testing.expect_value(t, TilemapGetTile(&other, {4, 2}), TileID(3))
    testing.expect_value(t, TilemapGetTile(&other, {5, 2}), TILE_EMPTY)

    TilemapSetTile(&other, {5, 2}, 9)
    TilemapSetRegionData(&other, {4, 1, 2, 2}, region[:], true)                            // empty tiles overwrite
    testing.expect_value(t, TilemapGetTile(&other, {5, 2}), TILE_EMPTY)

    TilemapSetRegionData(&other, {5, 3, 3, 3}, []TileID{1, 2, 3, 4, 5, 6, 7, 8, 9}, true)  // partly outside: clipped without a crash
    testing.expect_value(t, TilemapGetTile(&other, {5, 3}), TileID(1))
    TilemapSetRegionData(&other, {-1, -1, 2, 2}, region[:], true)                          // data that starts left of the map
    testing.expect_value(t, TilemapGetTile(&other, {0, 0}), region[3])
}

@(test)
test_tilemap_set_data_and_resize :: proc(t: ^testing.T) {
    buffer: [24]TileID
    tilemap: Tilemap = make_test_map(buffer[:])
    TilemapSetData(&tilemap, []TileID{1, 2, 3, 4, 5, 6}, 3, 2)                             // a 3x2 picture placed at the top left
    testing.expect_value(t, TilemapGetTile(&tilemap, {2, 0}), TileID(3))
    testing.expect_value(t, TilemapGetTile(&tilemap, {0, 1}), TileID(4))
    testing.expect_value(t, TilemapGetTile(&tilemap, {3, 0}), TILE_EMPTY)

    TilemapClear(&tilemap)
    TilemapSetTile(&tilemap, {1, 1}, 5)
    TilemapSetTile(&tilemap, {2, 2}, 6)
    temp: [16]TileID
    TilemapResize(&tilemap, {1, 1, 3, 3}, temp[:])
    testing.expect_value(t, tilemap.size, vec2i{3, 3})
    testing.expect_value(t, tilemap.position, vec2i{116, 66})                              // moved by one tile
    testing.expect_value(t, TilemapGetTile(&tilemap, {0, 0}), TileID(5))                   // the content stays where it was in the world
    testing.expect_value(t, TilemapGetTile(&tilemap, {1, 1}), TileID(6))
    testing.expect_value(t, TilemapGetTile(&tilemap, {2, 2}), TILE_EMPTY)
}
