package tilemap

// 
TileInit :: proc(tile: ^Tile, index_buffer:[]TileID, initial_length:u32){
    tile.data = index_buffer
    tile.length = initial_length
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