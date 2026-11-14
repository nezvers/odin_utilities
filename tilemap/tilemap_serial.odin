package tilemap

// Binary save and load of tilemaps, tile atlases and tilesets, as chunks of a serial file (see ../serial).
// A level can hold several tilemaps (layers), each with a name. Loading fills buffers the user provides, nothing allocates,
// and bad data (too big, inconsistent) is refused before anything is written to them.

import "../serial"
import "core:testing"

TAG_TILEMAP :: #force_inline proc "contextless" () -> serial.Tag { return serial.MakeTag('T', 'M', 'A', 'P') }
TAG_TILE_ATLAS :: #force_inline proc "contextless" () -> serial.Tag { return serial.MakeTag('T', 'A', 'T', 'L') }
TAG_TILESET :: #force_inline proc "contextless" () -> serial.Tag { return serial.MakeTag('T', 'S', 'E', 'T') }

TILEMAP_CHUNK_VERSION :: u16(1)
TILE_ATLAS_CHUNK_VERSION :: u16(1)
TILESET_CHUNK_VERSION :: u16(1)

// Most cells and most tiles per set that a file may claim, so bad data cannot ask for an absurd amount
SERIAL_MAX_CELLS :: 1 << 24
SERIAL_MAX_TILES :: 1 << 16

// ---------------------------------------------------------------- Tilemap

// One chunk: name, position, size, tile size and the cells, run length encoded (maps are mostly repeats)
TilemapSerialWrite :: proc(writer: ^serial.Writer, tilemap: ^Tilemap, name: string) {
    cells: int = int(tilemap.size.x) * int(tilemap.size.y)
    assert(tilemap.size.x >= 0 && tilemap.size.y >= 0 && cells <= len(tilemap.grid))
    serial.ChunkBegin(writer, TAG_TILEMAP(), TILEMAP_CHUNK_VERSION)
    serial.WriteString(writer, name)
    serial.WriteI32(writer, tilemap.position.x)
    serial.WriteI32(writer, tilemap.position.y)
    serial.WriteI32(writer, tilemap.size.x)
    serial.WriteI32(writer, tilemap.size.y)
    serial.WriteI32(writer, tilemap.tile_size.x)
    serial.WriteI32(writer, tilemap.tile_size.y)
    serial.RleWrite(writer, tilemap.grid[:cells])
    serial.ChunkEnd(writer)
}

// The cells of one tilemap chunk are not decoded yet: this reads its header, so the caller can size the buffer
TilemapSerialInfo :: struct {
    name: string,
    position: vec2i,
    size: vec2i,
    tile_size: vec2i,
}

@(private)
TilemapSerialHeader :: proc(payload: ^serial.Reader) -> (info: TilemapSerialInfo, ok: bool) {
    info.name = serial.ReadString(payload)
    info.position = {serial.ReadI32(payload), serial.ReadI32(payload)}
    info.size = {serial.ReadI32(payload), serial.ReadI32(payload)}
    info.tile_size = {serial.ReadI32(payload), serial.ReadI32(payload)}
    if !serial.ReaderOk(payload) { return }
    if info.size.x < 0 || info.size.y < 0 || i64(info.size.x) * i64(info.size.y) > SERIAL_MAX_CELLS { return }
    return info, true
}

// The nth tilemap chunk of the file (0 is the first): its name and size, to size the buffer
TilemapSerialPeek :: proc(file: serial.Reader, index: int) -> (info: TilemapSerialInfo, ok: bool) {
    payload := TilemapChunk(file, index) or_return
    return TilemapSerialHeader(&payload)
}

@(private)
TilemapChunk :: proc(file: serial.Reader, index: int) -> (payload: serial.Reader, ok: bool) {
    scan: serial.Reader = file
    found: int
    for {
        tag, version, chunk, next_ok := serial.ChunkNext(&scan)
        if !next_ok { return }
        if tag != TAG_TILEMAP() || version > TILEMAP_CHUNK_VERSION { continue }
        if found == index { return chunk, true }
        found += 1
    }
}

// How many tilemaps the file has
TilemapSerialCount :: proc(file: serial.Reader) -> int {
    return serial.ChunkCount(file, TAG_TILEMAP())
}

// Load the nth tilemap into `buffer`, which has to hold width * height cells. Nothing is written to it when the data is bad.
TilemapSerialRead :: proc(file: serial.Reader, index: int, buffer: []TileID) -> (tilemap: Tilemap, ok: bool) {
    payload := TilemapChunk(file, index) or_return
    info := TilemapSerialHeader(&payload) or_return
    cells: int = int(info.size.x) * int(info.size.y)
    if cells > len(buffer) { return }
    if !serial.RleRead(&payload, buffer[:cells]) { return }
    return TilemapInit(info.position, info.size, info.tile_size, buffer), true
}

// By the name that was saved with it
TilemapSerialReadNamed :: proc(file: serial.Reader, name: string, buffer: []TileID) -> (tilemap: Tilemap, ok: bool) {
    for index in 0 ..< TilemapSerialCount(file) {
        info, info_ok := TilemapSerialPeek(file, index)
        if info_ok && info.name == name {
            return TilemapSerialRead(file, index, buffer)
        }
    }
    return
}

// ---------------------------------------------------------------- Tile atlas

TileAtlasSerialWrite :: proc(writer: ^serial.Writer, atlas: ^TileAtlas) {
    serial.ChunkBegin(writer, TAG_TILE_ATLAS(), TILE_ATLAS_CHUNK_VERSION)
    serial.WriteF32(writer, atlas.tile_size.x)
    serial.WriteF32(writer, atlas.tile_size.y)
    serial.WriteU32(writer, atlas.length)
    for i in 0 ..< int(atlas.length) {
        serial.WriteF32(writer, atlas.data[i].x)
        serial.WriteF32(writer, atlas.data[i].y)
    }
    serial.ChunkEnd(writer)
}

// Load the atlas into `buffer` (its length is the capacity of the atlas)
TileAtlasSerialRead :: proc(file: serial.Reader, buffer: []vec2f) -> (atlas: TileAtlas, ok: bool) {
    version, payload, found := serial.ChunkFind(file, TAG_TILE_ATLAS())
    if !found || version > TILE_ATLAS_CHUNK_VERSION { return }
    tile_size: vec2f = {serial.ReadF32(&payload), serial.ReadF32(&payload)}
    count: int = serial.ReadCount(&payload, SERIAL_MAX_TILES, 8)
    if !serial.ReaderOk(&payload) || count > len(buffer) { return }
    TileAtlasInit(&atlas, tile_size, buffer)
    for i in 0 ..< count {
        buffer[i] = {serial.ReadF32(&payload), serial.ReadF32(&payload)}
    }
    atlas.length = u32(count)
    return atlas, serial.ReaderOk(&payload)
}

// ---------------------------------------------------------------- Tileset

TilesetSerialWrite :: proc(writer: ^serial.Writer, tileset: ^Tileset) {
    serial.ChunkBegin(writer, TAG_TILESET(), TILESET_CHUNK_VERSION)
    serial.WriteU32(writer, tileset.random_seed)
    serial.WriteU32(writer, tileset.length)
    for i in 0 ..< int(tileset.length) {
        tile: ^Tile = &tileset.data[i]
        serial.WriteU32(writer, tile.length)
        serial.WriteBytes(writer, tile.data[:tile.length])
    }
    serial.ChunkEnd(writer)
}

// Load the tileset: `tiles` holds the tiles, `ids` holds the alternative ids of all of them (each tile gets the part it needs).
// `spare_per_tile` leaves room in every tile to append alternatives later (the editor does).
TilesetSerialRead :: proc(file: serial.Reader, tiles: []Tile, ids: []TileID, spare_per_tile: u32 = 0) -> (tileset: Tileset, ok: bool) {
    version, payload, found := serial.ChunkFind(file, TAG_TILESET())
    if !found || version > TILESET_CHUNK_VERSION { return }
    seed: u32 = serial.ReadU32(&payload)
    count: int = serial.ReadCount(&payload, SERIAL_MAX_TILES, 4)
    if !serial.ReaderOk(&payload) || count > len(tiles) { return }

    TilesetInit(&tileset, tiles, 0)
    tileset.random_seed = seed
    used: int
    for _ in 0 ..< count {
        length: int = serial.ReadCount(&payload, SERIAL_MAX_TILES)
        room: int = length + int(spare_per_tile)
        if !serial.ReaderOk(&payload) || used + room > len(ids) { return }
        bytes: []byte = serial.ReadBytes(&payload, length)
        if !serial.ReaderOk(&payload) { return }
        tile: Tile
        TileInit(&tile, ids[used:used + room], u32(length))
        for value, j in bytes { tile.data[j] = value }
        TilesetAppend(&tileset, tile)
        used += room
    }
    return tileset, serial.ReaderOk(&payload)
}

// --- Tests ---

@(private="file")
write_test_file :: proc(buffer: []byte, writes: proc(writer: ^serial.Writer)) -> []byte {
    writer: serial.Writer
    serial.WriterInit(&writer, buffer)
    serial.FileBegin(&writer)
    writes(&writer)
    return serial.FileEnd(&writer)
}

@(test)
test_tilemap_round_trip :: proc(t: ^testing.T) {
    grid: [60]TileID
    tilemap: Tilemap = TilemapInit({-32, 48}, {10, 6}, {16, 16}, grid[:])
    TilemapSetTileIdBlock(&tilemap, 2, 1, 5, 3, 7)
    TilemapSetTile(&tilemap, {0, 0}, 1)
    TilemapSetTile(&tilemap, {9, 5}, 254)

    buffer: [512]byte
    writer: serial.Writer
    serial.WriterInit(&writer, buffer[:])
    serial.FileBegin(&writer)
    TilemapSerialWrite(&writer, &tilemap, "ground")
    file_bytes: []byte = serial.FileEnd(&writer)
    testing.expect(t, file_bytes != nil)

    file, _, opened := serial.FileOpen(file_bytes)
    testing.expect(t, opened)
    testing.expect_value(t, TilemapSerialCount(file), 1)
    info, info_ok := TilemapSerialPeek(file, 0)
    testing.expect(t, info_ok)
    testing.expect_value(t, info.name, "ground")
    testing.expect_value(t, info.size, vec2i{10, 6})

    loaded_grid: [60]TileID
    loaded, ok := TilemapSerialRead(file, 0, loaded_grid[:])
    testing.expect(t, ok)
    testing.expect_value(t, loaded.position, vec2i{-32, 48})
    testing.expect_value(t, loaded.size, vec2i{10, 6})
    testing.expect_value(t, loaded.tile_size, vec2i{16, 16})
    testing.expect_value(t, loaded_grid, grid)                                       // every cell is the same
    testing.expect_value(t, TilemapGetTile(&loaded, {9, 5}), TileID(254))
    testing.expect_value(t, TilemapGetTile(&loaded, {3, 2}), TileID(7))
}

@(test)
test_tilemap_is_stored_compactly_when_it_repeats :: proc(t: ^testing.T) {
    grid: [128 * 128]TileID                                                          // 16 KB of one tile
    tilemap: Tilemap = TilemapInit({0, 0}, {128, 128}, {8, 8}, grid[:])
    counting: serial.Writer
    serial.WriterInitCounting(&counting)
    TilemapSerialWrite(&counting, &tilemap, "empty")
    testing.expect(t, serial.WriterNeeded(&counting) < 600, "a 16 KB empty map is a few hundred bytes (runs hold up to 65535 cells)")
}

@(test)
test_several_layers_by_index_and_by_name :: proc(t: ^testing.T) {
    ground_cells: [6]TileID = {1, 1, 1, 2, 2, 2}
    ground: Tilemap = TilemapInit({0, 0}, {3, 2}, {16, 16}, ground_cells[:])
    walls_cells: [4]TileID = {9, 0, 0, 9}
    walls: Tilemap = TilemapInit({16, 0}, {2, 2}, {16, 16}, walls_cells[:])

    buffer: [512]byte
    writer: serial.Writer
    serial.WriterInit(&writer, buffer[:])
    serial.FileBegin(&writer)
    TilemapSerialWrite(&writer, &ground, "ground")
    TilemapSerialWrite(&writer, &walls, "walls")
    file, _, _ := serial.FileOpen(serial.FileEnd(&writer))
    testing.expect_value(t, TilemapSerialCount(file), 2)

    cells: [6]TileID
    second, second_ok := TilemapSerialRead(file, 1, cells[:])
    testing.expect(t, second_ok)
    testing.expect_value(t, second.size, vec2i{2, 2})
    testing.expect_value(t, cells[3], TileID(9))

    named, named_ok := TilemapSerialReadNamed(file, "ground", cells[:])
    testing.expect(t, named_ok)
    testing.expect_value(t, named.size, vec2i{3, 2})
    testing.expect_value(t, cells, ground_cells)
    _, missing := TilemapSerialReadNamed(file, "sky", cells[:])
    testing.expect(t, !missing)
    _, past := TilemapSerialRead(file, 2, cells[:])
    testing.expect(t, !past)
}

@(test)
test_tilemap_that_does_not_fit_or_lies_is_refused_untouched :: proc(t: ^testing.T) {
    cells: [20]TileID
    tilemap: Tilemap = TilemapInit({0, 0}, {5, 4}, {16, 16}, cells[:])
    for &cell in cells { cell = 3 }
    buffer: [256]byte
    writer: serial.Writer
    serial.WriterInit(&writer, buffer[:])
    serial.FileBegin(&writer)
    TilemapSerialWrite(&writer, &tilemap, "map")
    file, _, _ := serial.FileOpen(serial.FileEnd(&writer))

    small: [19]TileID
    for &cell in small { cell = 99 }
    _, fits := TilemapSerialRead(file, 0, small[:])
    testing.expect(t, !fits, "one cell too few in the buffer")
    for cell in small { testing.expect_value(t, cell, TileID(99)) }                  // not touched

    // a map that claims a size beyond the limit, in a frame with a valid checksum
    lie_buffer: [128]byte
    lie: serial.Writer
    serial.WriterInit(&lie, lie_buffer[:])
    serial.FileBegin(&lie)
    serial.ChunkBegin(&lie, TAG_TILEMAP(), 1)
    serial.WriteString(&lie, "huge")
    for value in ([]i32{0, 0, 100_000, 100_000, 16, 16}) { serial.WriteI32(&lie, value) }
    serial.RleWrite(&lie, nil)
    serial.ChunkEnd(&lie)
    lie_file, _, _ := serial.FileOpen(serial.FileEnd(&lie))
    _, huge_ok := TilemapSerialRead(lie_file, 0, small[:])
    testing.expect(t, !huge_ok)
    _, peek_ok := TilemapSerialPeek(lie_file, 0)
    testing.expect(t, !peek_ok, "the size is checked before it is reported")

    // a negative size
    serial.WriterInit(&lie, lie_buffer[:])
    serial.FileBegin(&lie)
    serial.ChunkBegin(&lie, TAG_TILEMAP(), 1)
    serial.WriteString(&lie, "negative")
    for value in ([]i32{0, 0, -3, 4, 16, 16}) { serial.WriteI32(&lie, value) }
    serial.RleWrite(&lie, nil)
    serial.ChunkEnd(&lie)
    negative_file, _, _ := serial.FileOpen(serial.FileEnd(&lie))
    _, negative_ok := TilemapSerialRead(negative_file, 0, small[:])
    testing.expect(t, !negative_ok)
}

@(test)
test_atlas_and_tileset_round_trip :: proc(t: ^testing.T) {
    atlas_buffer: [8]vec2f
    atlas: TileAtlas
    TileAtlasInit(&atlas, {16, 16}, atlas_buffer[:])
    TileAtlasInsert(&atlas, {0, 0}, 0)
    TileAtlasInsert(&atlas, {16, 0}, 1)
    TileAtlasInsert(&atlas, {32, 16}, 2)

    tile_buffer: [4]Tile
    id_buffer: [16]TileID
    tileset: Tileset
    TilesetInit(&tileset, tile_buffer[:], 0)
    tileset.random_seed = 1234
    TilesetAppend(&tileset, TileNewDefault(id_buffer[0:3], 1, 1))
    TilesetAppend(&tileset, TileNewDefault(id_buffer[3:8], 1, 2))
    TileAppend(&tileset.data[1], 3)
    TileAppend(&tileset.data[1], 4)

    buffer: [512]byte
    writer: serial.Writer
    serial.WriterInit(&writer, buffer[:])
    serial.FileBegin(&writer)
    TileAtlasSerialWrite(&writer, &atlas)
    TilesetSerialWrite(&writer, &tileset)
    file, _, _ := serial.FileOpen(serial.FileEnd(&writer))

    loaded_atlas_buffer: [8]vec2f
    loaded_atlas, atlas_ok := TileAtlasSerialRead(file, loaded_atlas_buffer[:])
    testing.expect(t, atlas_ok)
    testing.expect_value(t, loaded_atlas.length, u32(3))
    testing.expect_value(t, loaded_atlas.tile_size, vec2f{16, 16})
    testing.expect_value(t, loaded_atlas.data[2], vec2f{32, 16})
    testing.expect_value(t, loaded_atlas.capacity, u32(8))

    loaded_tiles: [4]Tile
    loaded_ids: [32]TileID
    loaded, tileset_ok := TilesetSerialRead(file, loaded_tiles[:], loaded_ids[:], 2)
    testing.expect(t, tileset_ok)
    testing.expect_value(t, loaded.length, u32(2))
    testing.expect_value(t, loaded.random_seed, u32(1234))
    testing.expect_value(t, TilesetGetId(&loaded, 0), TileID(1))
    second: Tile = TilesetGetTile(&loaded, 1)
    testing.expect_value(t, second.length, u32(3))
    testing.expect_value(t, second.data[2], TileID(4))
    testing.expect_value(t, second.capacity, u32(5))                                 // room for two more alternatives, for the editor
    TileAppend(&loaded.data[1], 5)
    testing.expect_value(t, loaded.data[1].length, u32(4))

    tiny_ids: [3]TileID
    _, too_small := TilesetSerialRead(file, loaded_tiles[:], tiny_ids[:])
    testing.expect(t, !too_small, "the id buffer cannot hold the alternatives")
    tiny_atlas: [2]vec2f
    _, atlas_small := TileAtlasSerialRead(file, tiny_atlas[:])
    testing.expect(t, !atlas_small)
}

@(test)
test_a_file_without_those_chunks_is_not_an_error_just_not_found :: proc(t: ^testing.T) {
    buffer: [64]byte
    writer: serial.Writer
    serial.WriterInit(&writer, buffer[:])
    serial.FileBegin(&writer)
    serial.ChunkBegin(&writer, serial.MakeTag('O', 'T', 'H', 'R'), 1)
    serial.WriteU32(&writer, 1)
    serial.ChunkEnd(&writer)
    file, _, _ := serial.FileOpen(serial.FileEnd(&writer))

    cells: [4]TileID
    _, tilemap_ok := TilemapSerialRead(file, 0, cells[:])
    testing.expect(t, !tilemap_ok)
    testing.expect_value(t, TilemapSerialCount(file), 0)
    atlas: [2]vec2f
    _, atlas_ok := TileAtlasSerialRead(file, atlas[:])
    testing.expect(t, !atlas_ok)
}
