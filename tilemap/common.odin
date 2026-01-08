package tilemap

vec2i :: [2]int

recti :: struct {
    x: int,
    y: int,
    w: int,
    h: int,
}

TileID :: u8
TILE_EMPTY: TileID: 0
TILE_INVALID: TileID: 255

Tilemap :: struct {
    position:vec2i,
    size:vec2i,
    tile_size:vec2i,
    grid: []TileID,
    capacity: u32,
}

// Represents set of alternative tiles that can be randomly chosen
Tile :: struct {
    data: []TileID,
    length: u32,
    capacity: u32,
}

// Represents whole set of tiles
Tileset :: struct {
    data: []Tile,
    length: u32,
    capacity: u32,
    random_seed: u32,
}

