package tilemap
import "core:testing"

// Dual grid tiling: the data tilemap stores what each cell is, the display tilemap is shifted by half a tile
// and each of its cells picks a tile by looking at 4 surrounding data cells.

// Maps a bitmask to a TileID (TileAtlas position). Mask bits:
// 1 - Top-left data cell is set
// 2 - Top-right data cell is set
// 4 - Bottom-right data cell is set
// 8 - Bottom-left data cell is set
// Default table expects 4x4 tile sheet where TileID = 1 + x + y * 4 (0 is TILE_EMPTY)
DUAL_GRID_MASK_TO_TILE: [16]TileID = {
    13, // 0000
    16, // 0001
    9,  // 0010
    10, // 0011
    14, // 0100
    5,  // 0101
    2,  // 0110
    11, // 0111
    1,  // 1000
    12, // 1001
    15, // 1010
    8,  // 1011
    4,  // 1100
    3,  // 1101
    6,  // 1110
    7,  // 1111
}

// Create display tilemap for data tilemap. It is 1 cell bigger and moved half a tile
// buffer length has to be at least (data.size.x + 1) * (data.size.y + 1)
DualGridInit :: proc(data:^Tilemap, buffer:[]TileID)->Tilemap {
    size:vec2i = data.size + {1, 1}
    assert(cast(i32)len(buffer) >= size.x * size.y)
    position:vec2i = data.position - data.tile_size / 2
    return TilemapInit(position, size, data.tile_size, buffer)
}

// Process single display cell. display_pos is in display tilemap coordinates
DualGridUpdateCell :: proc(data:^Tilemap, display:^Tilemap, group_id:TileID, mask_to_tile:[]TileID, display_pos:vec2i) {
    assert(len(mask_to_tile) >= 16)
    assert(display_pos.x >= 0)
    assert(display_pos.y >= 0)
    assert(display_pos.x < display.size.x)
    assert(display_pos.y < display.size.y)

    mask:u32 = 0
    if TilemapGetTile(data, display_pos + {-1, -1}) == group_id {
        mask |= 1
    }
    if TilemapGetTile(data, display_pos + {0, -1}) == group_id {
        mask |= 2
    }
    if TilemapGetTile(data, display_pos) == group_id {
        mask |= 4
    }
    if TilemapGetTile(data, display_pos + {-1, 0}) == group_id {
        mask |= 8
    }

    index_out:i32 = display_pos.x + display_pos.y * display.size.x
    display.grid[index_out] = mask_to_tile[mask]
}

// Recalculate whole display tilemap
DualGridUpdateTilemap :: proc(data:^Tilemap, display:^Tilemap, group_id:TileID, mask_to_tile:[]TileID) {
    assert(display.size == data.size + {1, 1})

    for y:i32 = 0; y < display.size.y; y += 1 {
        for x:i32 = 0; x < display.size.x; x += 1 {
            DualGridUpdateCell(data, display, group_id, mask_to_tile, {x, y})
        }
    }
}

// Recalculate 4 display cells that are touching changed data cell. data_pos is in data tilemap coordinates
DualGridUpdateNeighbours :: proc(data:^Tilemap, display:^Tilemap, group_id:TileID, mask_to_tile:[]TileID, data_pos:vec2i) {
    assert(display.size == data.size + {1, 1})

    for y:i32 = data_pos.y; y <= data_pos.y + 1; y += 1 {
        for x:i32 = data_pos.x; x <= data_pos.x + 1; x += 1 {
            if x < 0 || y < 0 || x >= display.size.x || y >= display.size.y {
                continue
            }
            DualGridUpdateCell(data, display, group_id, mask_to_tile, {x, y})
        }
    }
}

// --- Tests ---

@(private="file")
dual_group :: TileID(1)

@(test)
test_dual_grid_init :: proc(t: ^testing.T) {
    data_buffer: [9]TileID
    data: Tilemap = TilemapInit({100, 50}, {3, 3}, {16, 16}, data_buffer[:])
    display_buffer: [16]TileID
    display: Tilemap = DualGridInit(&data, display_buffer[:])
    testing.expect_value(t, display.size, vec2i{4, 4})
    testing.expect_value(t, display.position, vec2i{92, 42})                               // half a tile up and to the left
    testing.expect_value(t, display.tile_size, vec2i{16, 16})
}

@(test)
test_dual_grid_corner_masks :: proc(t: ^testing.T) {
    data_buffer: [9]TileID
    data: Tilemap = TilemapInit({0, 0}, {3, 3}, {16, 16}, data_buffer[:])
    display_buffer: [16]TileID
    display: Tilemap = DualGridInit(&data, display_buffer[:])
    TilemapSetTile(&data, {1, 1}, dual_group)                                              // one set cell in the middle
    DualGridUpdateTilemap(&data, &display, dual_group, DUAL_GRID_MASK_TO_TILE[:])

    // the four display cells around it each see it from a different corner
    testing.expect_value(t, TilemapGetTile(&display, {1, 1}), DUAL_GRID_MASK_TO_TILE[0b0100])   // it is the bottom right of this cell
    testing.expect_value(t, TilemapGetTile(&display, {2, 1}), DUAL_GRID_MASK_TO_TILE[0b1000])   // bottom left
    testing.expect_value(t, TilemapGetTile(&display, {1, 2}), DUAL_GRID_MASK_TO_TILE[0b0010])   // top right
    testing.expect_value(t, TilemapGetTile(&display, {2, 2}), DUAL_GRID_MASK_TO_TILE[0b0001])   // top left
    testing.expect_value(t, TilemapGetTile(&display, {0, 0}), DUAL_GRID_MASK_TO_TILE[0])
    testing.expect_value(t, TilemapGetTile(&display, {3, 3}), DUAL_GRID_MASK_TO_TILE[0])
}

@(test)
test_dual_grid_filled_block_and_edges :: proc(t: ^testing.T) {
    data_buffer: [4]TileID
    data: Tilemap = TilemapInit({0, 0}, {2, 2}, {16, 16}, data_buffer[:])
    display_buffer: [9]TileID
    display: Tilemap = DualGridInit(&data, display_buffer[:])
    TilemapSetTileIdBlock(&data, 0, 0, 2, 2, dual_group)
    DualGridUpdateTilemap(&data, &display, dual_group, DUAL_GRID_MASK_TO_TILE[:])

    testing.expect_value(t, TilemapGetTile(&display, {1, 1}), DUAL_GRID_MASK_TO_TILE[0b1111])   // surrounded
    testing.expect_value(t, TilemapGetTile(&display, {0, 0}), DUAL_GRID_MASK_TO_TILE[0b0100])   // outer corners see one cell
    testing.expect_value(t, TilemapGetTile(&display, {2, 0}), DUAL_GRID_MASK_TO_TILE[0b1000])
    testing.expect_value(t, TilemapGetTile(&display, {1, 0}), DUAL_GRID_MASK_TO_TILE[0b1100])   // the top edge sees two
    testing.expect_value(t, TilemapGetTile(&display, {0, 1}), DUAL_GRID_MASK_TO_TILE[0b0110])
}

@(test)
test_dual_grid_neighbour_update_touches_four_cells :: proc(t: ^testing.T) {
    data_buffer: [9]TileID
    data: Tilemap = TilemapInit({0, 0}, {3, 3}, {16, 16}, data_buffer[:])
    display_buffer: [16]TileID
    display: Tilemap = DualGridInit(&data, display_buffer[:])
    for &id in display_buffer { id = 99 }

    TilemapSetTile(&data, {1, 1}, dual_group)
    DualGridUpdateNeighbours(&data, &display, dual_group, DUAL_GRID_MASK_TO_TILE[:], {1, 1})
    for y in i32(0) ..< 4 {
        for x in i32(0) ..< 4 {
            touched: bool = x >= 1 && x <= 2 && y >= 1 && y <= 2
            testing.expect_value(t, TilemapGetTile(&display, {x, y}) != 99, touched)
        }
    }

    for &id in display_buffer { id = 99 }
    DualGridUpdateNeighbours(&data, &display, dual_group, DUAL_GRID_MASK_TO_TILE[:], {2, 2})   // at the edge of the data: nothing is read out of range
    testing.expect_value(t, TilemapGetTile(&display, {3, 3}), DUAL_GRID_MASK_TO_TILE[0])
}
