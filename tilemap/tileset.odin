package tilemap


TilesetInit :: proc(tileset: ^Tileset, buffer:[]Tile, initial_length:u32){
    tileset.data = buffer
    tileset.length = initial_length
    tileset.capacity = cast(u32)len(buffer)
    tileset.random_seed = 0
}

TilesetAppend :: proc(tileset: ^Tileset, tile:Tile){
    if (tileset.length > tileset.capacity -1){
        assert(false)
        return
    }
    tileset.data[tileset.length] = tile
    tileset.length += 1
}

TilesetInsert :: proc(tileset: ^Tileset, tile:Tile, index:u32){
    if (tileset.length > tileset.capacity -1){
        assert(false)
        return
    }
    for i: = tileset.length; i > index; i -= 1 {
        tileset.data[i] = tileset.data[i - 1]
    }
    
    tileset.data[index] = tile
    tileset.length += 1
}

TilesetRemoveIndex :: proc(tileset: ^Tileset, index:u32){
    for i: = index; i < tileset.length -1; i += 1{
        tileset.data[i] = tileset.data[i +1]
    }
    tileset.length -= 1
}

TilesetGetId :: proc(tileset: ^Tileset, tile_id:TileID)->TileID {
    assert(tile_id != TILE_INVALID)
    if (tile_id > cast(u8)(tileset.length - 1)){
        return TILE_EMPTY
    }
    result:TileID = tileset.data[tile_id].data[0]
    return result
}

TilesetGetTile :: proc(tileset: ^Tileset, tile_id:TileID)->Tile {
    assert(tile_id != TILE_INVALID)
    if (tile_id > cast(u8)(tileset.length - 1)){
        return {}
    }
    result:Tile = tileset.data[tile_id]
    return result
}

rnd_int :: proc(seed: ^u32, min:int, max:int)->int{
    num:u32 = rnd(seed)
    result:int = cast(int)(num % cast(u32)(max - min)) + min
    return result
}

// Seed is mutated
// Use copy of tileset.random_seed before each batch of fetching to get repeatable results
TilesetGetTileAltRandom :: proc(tileset: ^Tileset, tile_id:TileID, seed: ^u32)->TileID {
    assert(tile_id != TILE_INVALID)
    if (tile_id > cast(u8)(tileset.length - 1)){
        return TILE_EMPTY
    }
    tile:Tile = tileset.data[tile_id]
    index_rnd:u32 = cast(u32)rnd_int(seed, 0, cast(int)tile.length)
    result:TileID = tile.data[index_rnd]
    return result
}

TilesetGetTileAltDeterministic :: proc(tileset: ^Tileset, tile_id:TileID, seed_x:i32, seed_y:i32)->TileID {
    assert(tile_id != TILE_INVALID)
    if (tile_id > cast(u8)(tileset.length - 1)){
        return TILE_EMPTY
    }
    tile:Tile = tileset.data[tile_id]
    index_rnd:u32 = cash(tileset.random_seed, cast(int)seed_x, cast(int)seed_y) % tile.length
    result:TileID = tile.data[index_rnd]
    return result
}