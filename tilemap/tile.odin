package tilemap
import "core:testing"

// 
TileInit :: proc(tile: ^Tile, index_buffer:[]TileID, initial_length:u32) {
    tile.data = index_buffer
    tile.length = initial_length
    tile.capacity = cast(u32)len(index_buffer)
}

TileNewDefault :: proc(index_buffer:[]TileID, initial_length:u32, tile_id:TileID)->Tile {
    tile:Tile = {
        index_buffer,
        initial_length,
        cast(u32)len(index_buffer),
    }
    tile.data[0] = tile_id
    return tile
}

TileAppend :: proc(tile: ^Tile, tile_id:TileID) {
    if (tile.length > tile.capacity -1){
        assert(false)
        return
    }
    tile.data[tile.length] = tile_id
    tile.length += 1
}

TileRemoveId :: proc(tile: ^Tile, tile_id:TileID) {
    is_removed:bool
    i:u32 = 0
    for ; i < tile.length; {
        if (tile.data[i] == tile_id) {
            is_removed = true
            break
        }
        i += 1
    }
    if (!is_removed) {
        return
    }

    for ; i < tile.length -1; {
        tile.data[i] = tile.data[i+1]
        i += 1
    }
    tile.length -= 1
}

TileRemoveIndex :: proc(tile: ^Tile, index:u32) {
    for i: = index; i < tile.length -1; i += 1 {
        tile.data[i] = tile.data[i +1]
    }
    tile.length -= 1
}

// Get default 0th ID or TILE_EMPTY if no IDs inside
TileGetId :: proc(tile: ^Tile)->TileID {
    if (tile.length == 0) {
        assert(false)
        return TILE_EMPTY
    }
    result:TileID = tile.data[0]
    return result
}

// Use pointer to a seed copy when doing a batch of drawing to get repeatable results
// Seed is mutated
TileGetRandomSeed :: proc(tile: ^Tile, seed: ^u32)->TileID {
    if (tile.length == 0) {
        assert(false)
        return TILE_EMPTY
    }
    index_rnd:u32 = cast(u32)rnd_int(seed, 0, cast(int)tile.length)
    result:TileID = tile.data[index_rnd]
    return result
}

TileGetRandomXY :: proc(tile: ^Tile, seed:u32, seed_x:int, seed_y:int)->TileID {
    if (tile.length == 0){
        assert(false)
        return TILE_EMPTY
    }
    index_rnd:u32 = cash(seed, seed_x, seed_y) % tile.length
    result:TileID = tile.data[index_rnd]
    return result
}

// --- Tests ---

@(test)
test_tile_editing :: proc(t: ^testing.T) {
    buffer: [4]TileID
    tile: Tile = TileNewDefault(buffer[:], 1, 10)
    testing.expect_value(t, tile.length, u32(1))
    testing.expect_value(t, tile.capacity, u32(4))
    testing.expect_value(t, TileGetId(&tile), TileID(10))

    TileAppend(&tile, 11)
    TileAppend(&tile, 12)
    testing.expect_value(t, tile.length, u32(3))
    testing.expect_value(t, tile.data[2], TileID(12))

    TileRemoveId(&tile, 11)
    testing.expect_value(t, tile.length, u32(2))
    testing.expect_value(t, tile.data[1], TileID(12))                                      // the tail moves up
    TileRemoveId(&tile, 99)                                                                // an id that is not there changes nothing
    testing.expect_value(t, tile.length, u32(2))

    TileRemoveIndex(&tile, 0)
    testing.expect_value(t, tile.length, u32(1))
    testing.expect_value(t, TileGetId(&tile), TileID(12))

    other: Tile
    TileInit(&other, buffer[:], 2)
    testing.expect_value(t, other.length, u32(2))
    testing.expect_value(t, other.capacity, u32(4))
}

@(test)
test_tile_random_alternatives :: proc(t: ^testing.T) {
    buffer: [4]TileID = {10, 11, 12, 13}
    tile: Tile
    TileInit(&tile, buffer[:], 4)

    seen: [4]bool
    seed: u32 = 1234
    for _ in 0 ..< 400 {
        id: TileID = TileGetRandomSeed(&tile, &seed)
        testing.expect(t, id >= 10 && id <= 13)
        seen[id - 10] = true
    }
    testing.expect_value(t, seen, [4]bool{true, true, true, true})                         // every alternative, including the last, can be picked

    first, second: u32 = 77, 77
    testing.expect_value(t, TileGetRandomSeed(&tile, &first), TileGetRandomSeed(&tile, &second))
    testing.expect(t, first == second, "the same seed walks the same way")

    single: Tile = TileNewDefault(buffer[:1], 1, 42)                                       // one alternative: no division by zero
    seed = 5
    testing.expect_value(t, TileGetRandomSeed(&single, &seed), TileID(42))

    testing.expect_value(t, TileGetRandomXY(&tile, 9, 3, 4), TileGetRandomXY(&tile, 9, 3, 4))
    variety: map[TileID]bool
    defer delete(variety)
    for x in 0 ..< 64 { variety[TileGetRandomXY(&tile, 9, x, 0)] = true }
    testing.expect(t, len(variety) > 1, "neighbouring cells do not all pick the same alternative")
}
