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
        tile.data[i] = tile.data[i+1]
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
        tileset.data[i+1] = tileset.data[i]
    }
    tileset.data[index+1] = tileset.data[index]
    tileset.length += 1
}

TilesetRemoveIndex :: proc(tileset: ^Tileset, index:u32){
    for i: = index; i < tileset.length -1; i += 1{
        tileset.data[i] = tileset.data[i+1]
    }
    tileset.length -= 1
}
