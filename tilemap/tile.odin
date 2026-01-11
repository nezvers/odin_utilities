package tilemap

// 
TileInit :: proc(tile: ^Tile, index_buffer:[]TileID, initial_length:u32){
    tile.data = index_buffer
    tile.length = initial_length
    tile.capacity = cast(u32)len(index_buffer)
}

TileNewDefault :: proc(index_buffer:[]TileID, initial_length:u32, tile_id:TileID)->Tile{
    tile:Tile = {
        index_buffer,
        initial_length,
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

// Get default 0th ID or TILE_EMPTY if no IDs inside
TileGetId :: proc(tile: ^Tile)->TileID{
    if (tile.length == 0){
        assert(false)
        return TILE_EMPTY
    }
    result:TileID = tile.data[0]
    return result
}

// Use pointer to a seed copy when doing a batch of drawing to get repeatable results
// Seed is mutated
TileGetRandomSeed :: proc(tile: ^Tile, seed: ^u32)->TileID{
    if (tile.length == 0){
        assert(false)
        return TILE_EMPTY
    }
    index_rnd:u32 = cast(u32)rnd_int(seed, 0, cast(int)tile.length)
    result:TileID = tile.data[index_rnd]
    return result
}

TileGetRandomXY :: proc(tile: ^Tile, seed:u32, seed_x:int, seed_y:int)->TileID{
    if (tile.length == 0){
        assert(false)
        return TILE_EMPTY
    }
    index_rnd:u32 = cash(seed, seed_x, seed_y) % tile.length
    result:TileID = tile.data[index_rnd]
    return result
}