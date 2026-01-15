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

// clip off that is not inside the clip recti
RectiClipRecti :: proc(clip:^recti, rect:^recti) {
    if rect.x < clip.x {
        diff:int = clip.x - rect.x
        rect.w -= diff
        rect.x = 0
    }
    if rect.y < clip.y {
        diff:int = clip.y - rect.y
        rect.h -= diff
        rect.y = 0
    }
    if rect.x + rect.w > clip.w {
        diff:int = (rect.x + rect.w) - clip.w
        rect.w -= diff
    }
    if rect.y + rect.h > clip.h {
        diff:int = (rect.y + rect.h) - clip.h
        rect.h -= diff
    }
    if rect.w < 0 {
        rect.w = 0
    }
    if rect.h < 0 {
        rect.h = 0
    }
}

RectiFromRange :: proc(from:vec2i, to:vec2i)->recti {
    result:recti = {}

    if (to.x < from.x){
        result.x = to.x
        result.w = from.x - to.x
    } else
    {
        result.x = from.x
        result.w = to.x - from.x
    }

    if (to.y < from.y){
        result.y = to.y
        result.h = from.y - to.y
    } else
    {
        result.y = from.y
        result.h = to.y - from.y
    }

    result.w += 1
    result.h += 1
    return result
}