package tilemap

TileInit :: proc(tile: ^Tile, index_buffer:[]TileID){
    tile.data = index_buffer
    tile.length = 0
    tile.capacity = cast(u32)len(index_buffer)
}

TileGetDefault :: proc(tile_id:TileID, index_buffer:[]TileID)->Tile{
    tile:Tile = {
        index_buffer,
        1,
        cast(u32)len(index_buffer),
    }
    tile.data[0] = tile_id
    return tile
}

TileAppend :: proc(tile: ^Tile, tile_id:TileID){
    if (tile.length > tile.capacity -1){
        assert(false)
        return
    }
    tile.data[tile.length] = tile_id
    tile.length += 1
}

TileRemoveId :: proc(tile: ^Tile, tile_id:TileID){
    is_removed:bool
    i:u32 = 0
    for ; i < tile.length; {
        if (tile.data[i] == tile_id){
            is_removed = true
            break
        }
        i += 1
    }
    if (!is_removed){
        return
    }

    for ; i < tile.length -1; {
        tile.data[i] = tile.data[i+1]
        i += 1
    }
    tile.length -= 1
}

TileRemoveIndex :: proc(tile: ^Tile, index:u32){
    for i: = index; i < tile.length -1; i += 1 {
        tile.data[i] = tile.data[i +1]
    }
    tile.length -= 1
}

TilesetInit :: proc(tileset: ^Tileset, buffer:[]Tile){
    tileset.data = buffer
    tileset.length = 0
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
        tileset.data[i +1] = tileset.data[i]
    }
    tileset.data[index +1] = tileset.data[index]
    tileset.data[index] = tile
    tileset.length += 1
}

TilesetRemoveIndex :: proc(tileset: ^Tileset, index:u32){
    for i: = index; i < tileset.length -1; i += 1{
        tileset.data[i] = tileset.data[i +1]
    }
    tileset.length -= 1
}

TilesetGetTile :: proc(tileset: ^Tileset, tile_id:TileID)->TileID {
    assert(tile_id != TILE_INVALID)
    if (tile_id > cast(u8)(tileset.length - 1)){
        return TILE_EMPTY
    }
    result:TileID = tileset.data[tile_id].data[0]
    return result
}

rnd :: proc(seed: ^u32)->u32{
    /* Taken from OneLoneCoder: https://github.com/OneLoneCoder/Javidx9/blob/0c8ec20a9ed3b2daf76a925034ac5e7e6f4096e0/PixelGameEngine/SmallerProjects/OneLoneCoder_PGE_ProcGen_Universe.cpp#L170 */
    seed^ += 0xe120fc15
    tmp:u64 = cast(u64)(seed^ * 0x4a39b70d)
    m1:u32 = cast(u32)((tmp >> 32) ~ tmp)
    tmp = cast(u64)(m1 * 0x12fad5c9)
    m2:u32 = cast(u32)((tmp >> 32) ~ tmp)
    return m2
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

cash :: proc(seed:u32, x:int, y:int)->u32 {
    /* https://stackoverflow.com/a/37221804 */
    h:u32 = seed + cast(u32)x * 374761393 + cast(u32)y * 668265263 //all constants are prime
    h = (h ~ (h >> 13)) * 1274126177
    result:u32 = h ~ (h >> 16)
    return result
}

TilesetGetTileAltDeterministic :: proc(tileset: ^Tileset, tile_id:TileID, seed_x:int, seed_y:int)->TileID {
    assert(tile_id != TILE_INVALID)
    if (tile_id > cast(u8)(tileset.length - 1)){
        return TILE_EMPTY
    }
    tile:Tile = tileset.data[tile_id]
    index_rnd:u32 = cash(tileset.random_seed, seed_x, seed_y) % tile.length
    result:TileID = tile.data[index_rnd]
    return result
}