package tilemap

TileAtlasInit :: proc(tile_atlas: ^TileAtlas, tile_size:vec2f, buffer: []vec2f){
    tile_atlas.data = buffer
    tile_atlas.length = 0
    tile_atlas.capacity = cast(u32)len(buffer)
    tile_atlas.tile_size = tile_size
}

TileAtlasInsert :: proc(tile_atlas: ^TileAtlas, texture_position:vec2f, index:u32){
    if (tile_atlas.length > tile_atlas.capacity - 1){
        assert(false)
        return
    }
    if (index > tile_atlas.length || index < 0){
        assert(false)
        return
    }
    if index == tile_atlas.length {
        tile_atlas.data[index] = texture_position
        tile_atlas.length += 1
        return
    }

    for i:u32 = tile_atlas.length; i > index; i -= 1 {
        tile_atlas.data[i] = tile_atlas.data[i - 1]
    }
    
    tile_atlas.data[index] = texture_position
    tile_atlas.length += 1
}

TileAtlasRemoveIndex :: proc(tile_atlas: ^TileAtlas, index:u32){
    for i: = index; i < tile_atlas.length -1; i += 1{
        tile_atlas.data[i] = tile_atlas.data[i +1]
    }
    tile_atlas.length -= 1
}