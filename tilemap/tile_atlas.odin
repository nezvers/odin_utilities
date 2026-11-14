package tilemap
import "core:testing"

TileAtlasInit :: proc(tile_atlas: ^TileAtlas, tile_size:vec2f, buffer: []vec2f) {
    tile_atlas.data = buffer
    tile_atlas.length = 0
    tile_atlas.capacity = cast(u32)len(buffer)
    tile_atlas.tile_size = tile_size
}

TileAtlasInsert :: proc(tile_atlas: ^TileAtlas, texture_position:vec2f, index:u32) {
    if (tile_atlas.length > tile_atlas.capacity - 1) {
        assert(false)
        return
    }
    if (index > tile_atlas.length || index < 0) {
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

TileAtlasRemoveIndex :: proc(tile_atlas: ^TileAtlas, index:u32) {
    for i: = index; i < tile_atlas.length -1; i += 1 {
        tile_atlas.data[i] = tile_atlas.data[i +1]
    }
    tile_atlas.length -= 1
}

// --- Tests ---

@(test)
test_tile_atlas_insert_and_remove :: proc(t: ^testing.T) {
    buffer: [4]vec2f
    atlas: TileAtlas
    TileAtlasInit(&atlas, {16, 16}, buffer[:])
    testing.expect_value(t, atlas.capacity, u32(4))
    testing.expect_value(t, atlas.tile_size, vec2f{16, 16})

    TileAtlasInsert(&atlas, {0, 0}, 0)
    TileAtlasInsert(&atlas, {16, 0}, 1)
    TileAtlasInsert(&atlas, {32, 0}, 2)
    testing.expect_value(t, atlas.length, u32(3))

    TileAtlasInsert(&atlas, {99, 99}, 1)                                                   // inserting in the middle pushes the rest up
    testing.expect_value(t, atlas.length, u32(4))
    testing.expect_value(t, atlas.data[0], vec2f{0, 0})
    testing.expect_value(t, atlas.data[1], vec2f{99, 99})
    testing.expect_value(t, atlas.data[2], vec2f{16, 0})
    testing.expect_value(t, atlas.data[3], vec2f{32, 0})

    TileAtlasRemoveIndex(&atlas, 1)
    testing.expect_value(t, atlas.length, u32(3))
    testing.expect_value(t, atlas.data[1], vec2f{16, 0})
    testing.expect_value(t, atlas.data[2], vec2f{32, 0})
}
