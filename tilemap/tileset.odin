package tilemap
import "core:testing"


TilesetInit :: proc(tileset: ^Tileset, buffer:[]Tile, initial_length:u32) {
    tileset.data = buffer
    tileset.length = initial_length
    tileset.capacity = cast(u32)len(buffer)
    tileset.random_seed = 0
}

TilesetAppend :: proc(tileset: ^Tileset, tile:Tile) {
    if (tileset.length > tileset.capacity -1) {
        assert(false)
        return
    }
    tileset.data[tileset.length] = tile
    tileset.length += 1
}

TilesetInsert :: proc(tileset: ^Tileset, tile:Tile, index:u32) {
    if (tileset.length > tileset.capacity -1) {
        assert(false)
        return
    }
    for i: = tileset.length; i > index; i -= 1 {
        tileset.data[i] = tileset.data[i - 1]
    }
    
    tileset.data[index] = tile
    tileset.length += 1
}

TilesetRemoveIndex :: proc(tileset: ^Tileset, index:u32) {
    for i: = index; i < tileset.length -1; i += 1 {
        tileset.data[i] = tileset.data[i +1]
    }
    tileset.length -= 1
}

TilesetGetId :: proc(tileset: ^Tileset, tile_id:TileID)->TileID {
    assert(tile_id != TILE_INVALID)
    if cast(u32)tile_id >= tileset.length {
        return TILE_EMPTY
    }
    result:TileID = tileset.data[tile_id].data[0]
    return result
}

TilesetGetTile :: proc(tileset: ^Tileset, tile_id:TileID)->Tile {
    assert(tile_id != TILE_INVALID)
    if cast(u32)tile_id >= tileset.length {
        return {}
    }
    result:Tile = tileset.data[tile_id]
    return result
}

// Seed is mutated
// Use copy of tileset.random_seed before each batch of fetching to get repeatable results
TilesetGetTileAltRandom :: proc(tileset: ^Tileset, tile_id:TileID, seed: ^u32)->TileID {
    assert(tile_id != TILE_INVALID)
    if cast(u32)tile_id >= tileset.length {
        return TILE_EMPTY
    }
    tile:Tile = tileset.data[tile_id]
    index_rnd:u32 = cast(u32)rnd_int(seed, 0, cast(int)tile.length)
    result:TileID = tile.data[index_rnd]
    return result
}

TilesetGetTileAltDeterministic :: proc(tileset: ^Tileset, tile_id:TileID, seed_x:i32, seed_y:i32)->TileID {
    assert(tile_id != TILE_INVALID)
    if cast(u32)tile_id >= tileset.length {
        return TILE_EMPTY
    }
    tile:Tile = tileset.data[tile_id]
    index_rnd:u32 = cash(tileset.random_seed, cast(int)seed_x, cast(int)seed_y) % tile.length
    result:TileID = tile.data[index_rnd]
    return result
}

// --- Tests ---

@(private="file")
make_tileset :: proc(tiles: []Tile, ids: []TileID) -> Tileset {
    tileset: Tileset
    TilesetInit(&tileset, tiles, 0)
    for i in 0 ..< 3 {
        tile: Tile = TileNewDefault(ids[i * 2:i * 2 + 2], 1, TileID(20 + i))
        tile.data[1] = TileID(30 + i)
        tile.length = 2
        TilesetAppend(&tileset, tile)
    }
    return tileset
}

@(test)
test_tileset_editing :: proc(t: ^testing.T) {
    tiles: [8]Tile
    ids: [8]TileID
    tileset: Tileset = make_tileset(tiles[:], ids[:])
    testing.expect_value(t, tileset.length, u32(3))
    testing.expect_value(t, tileset.capacity, u32(8))
    testing.expect_value(t, TilesetGetId(&tileset, 1), TileID(21))
    testing.expect_value(t, TilesetGetId(&tileset, 3), TILE_EMPTY)                         // past the end
    testing.expect_value(t, TilesetGetTile(&tileset, 2).length, u32(2))
    testing.expect_value(t, TilesetGetTile(&tileset, 9).length, u32(0))

    extra_ids: [2]TileID = {50, 51}
    TilesetInsert(&tileset, TileNewDefault(extra_ids[:], 1, 50), 1)
    testing.expect_value(t, tileset.length, u32(4))
    testing.expect_value(t, TilesetGetId(&tileset, 1), TileID(50))
    testing.expect_value(t, TilesetGetId(&tileset, 2), TileID(21))                         // the old second tile moved up one slot

    TilesetRemoveIndex(&tileset, 0)
    testing.expect_value(t, tileset.length, u32(3))
    testing.expect_value(t, TilesetGetId(&tileset, 0), TileID(50))

    empty: Tileset
    TilesetInit(&empty, tiles[:], 0)
    testing.expect_value(t, TilesetGetId(&empty, 0), TILE_EMPTY)                           // an empty set has no ids
    testing.expect_value(t, TilesetGetTile(&empty, 0).length, u32(0))
}

@(test)
test_tileset_alternatives :: proc(t: ^testing.T) {
    tiles: [8]Tile
    ids: [8]TileID
    tileset: Tileset = make_tileset(tiles[:], ids[:])
    tileset.random_seed = 99

    seen: [2]bool
    seed: u32 = tileset.random_seed
    for _ in 0 ..< 200 {
        id: TileID = TilesetGetTileAltRandom(&tileset, 1, &seed)
        testing.expect(t, id == 21 || id == 31)
        seen[0] = seen[0] || id == 21
        seen[1] = seen[1] || id == 31
    }
    testing.expect_value(t, seen, [2]bool{true, true})
    seed = 1
    testing.expect_value(t, TilesetGetTileAltRandom(&tileset, 7, &seed), TILE_EMPTY)

    first: TileID = TilesetGetTileAltDeterministic(&tileset, 2, 5, 6)
    testing.expect_value(t, TilesetGetTileAltDeterministic(&tileset, 2, 5, 6), first)
    testing.expect(t, first == 22 || first == 32)
    testing.expect_value(t, TilesetGetTileAltDeterministic(&tileset, 8, 5, 6), TILE_EMPTY)
}
