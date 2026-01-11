package tilemap

vec2f :: [2]f32
vec2i :: [2]int

recti :: struct {
    x: int,
    y: int,
    w: int,
    h: int,
}
rectf :: struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
}

TileID :: u8
TILE_EMPTY: TileID: 0
TILE_INVALID: TileID: 255

// Data about Texture positions
TileAtlas :: struct {
    data:[]vec2f,
    length:u32,
    capacity:u32,
    tile_size:vec2f,
}

// Grid map of IDs. Tilemap->Tile
Tilemap :: struct {
    position:vec2i,
    size:vec2i,
    tile_size:vec2i,
    grid: []TileID,
    capacity: u32,
}

// Array of atlas position IDs. Tile->TileAtlas.data
// Can hold IDs for alternative tiles
Tile :: struct {
    data: []TileID,
    length: u32,
    capacity: u32,
}

// Represents middle abstraction between Tilemap & Tile.
// It hold a set of tiles and used to calculate random alternative tiles
Tileset :: struct {
    data: []Tile,
    length: u32,
    capacity: u32,
    random_seed: u32,
}


TileRandType :: enum {
    // Default TileID
    NONE,
    // Using TileSet.random_seed. it is deterministic, if used same grid drawing conditions
    SEED,
    // Using deterministic Tileset.random_seed + cell X & Y
    XY,
}