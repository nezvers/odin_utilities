// Drawing of the tilemap library over the demo kit (odin_utilities/demo_kit): the same procs as raylib/ and karl2d/, but through kit.Context and
// kit.Texture, so a demo written against the kit draws tilemaps on any backend.
package tilemap_kit

import "core:fmt"
import tm ".."
import kit "../../demo_kit"

vec2i :: tm.vec2i
recti :: tm.recti
TileAtlas :: tm.TileAtlas
TileID :: tm.TileID
Tile :: tm.Tile
Tileset :: tm.Tileset
Tilemap :: tm.Tilemap
TileRandType :: tm.TileRandType

// Drawing a tile from atlas directly
DrawTileAtlas :: proc(ctx: ^kit.Context, tile_atlas: ^TileAtlas, tile_id: TileID, draw_pos: kit.Vec2, texture: kit.Texture) {
    tex_pos: kit.Vec2 = tile_atlas.data[tile_id]
    size: kit.Vec2 = tile_atlas.tile_size
    kit.DrawTextureRect(ctx, texture, {tex_pos.x, tex_pos.y, size.x, size.y}, {draw_pos.x, draw_pos.y, size.x, size.y})
}

DrawTile :: proc(ctx: ^kit.Context, tile: ^Tile, tile_atlas: ^TileAtlas, draw_pos: kit.Vec2, texture: kit.Texture, subtile: TileID = 0) {
    DrawTileAtlas(ctx, tile_atlas, tile.data[subtile], draw_pos, texture)
}

// Draw 2D grid lines
DrawTilemapGrid :: proc(ctx: ^kit.Context, tilemap: ^Tilemap, color: kit.Color) {
    map_width: f32 = f32(tilemap.size.x * tilemap.tile_size.x)
    map_height: f32 = f32(tilemap.size.y * tilemap.tile_size.y)
    origin: kit.Vec2 = {f32(tilemap.position.x), f32(tilemap.position.y)}
    // Vertical lines
    for x in 0 ..= tilemap.size.x {
        cell_x: f32 = origin.x + f32(x * tilemap.tile_size.x)
        kit.DrawLine(ctx, {cell_x, origin.y}, {cell_x, origin.y + map_height}, 1, color)
    }
    // Horizontal lines
    for y in 0 ..= tilemap.size.y {
        cell_y: f32 = origin.y + f32(y * tilemap.tile_size.y)
        kit.DrawLine(ctx, {origin.x, cell_y}, {origin.x + map_width, cell_y}, 1, color)
    }
}

// Draw ID on tile positions for whole tilemap
DrawTilemapTileId :: proc(ctx: ^kit.Context, tilemap: ^Tilemap, font_size: f32, color: kit.Color) {
    for y in 0 ..< tilemap.size.y {
        for x in 0 ..< tilemap.size.x {
            cell_id: TileID = tilemap.grid[x + y * tilemap.size.x]
            if cell_id == 0 { continue }        // skip EMPTY
            text: string = fmt.tprintf("%d", cell_id)
            DrawCellText(ctx, tilemap, {x, y}, text, font_size, color)
        }
    }
}

// Draw rectangle around tile and draw provided ID
DrawTilemapCellRect :: proc(ctx: ^kit.Context, tilemap: ^Tilemap, world_pos: vec2i, tile_id: TileID, font_size: f32, color: kit.Color) {
    tile_pos: vec2i = tm.TilemapGetWorld2Tile(tilemap, world_pos)
    cell: kit.Rect = {
        f32(tilemap.position.x + tile_pos.x * tilemap.tile_size.x),
        f32(tilemap.position.y + tile_pos.y * tilemap.tile_size.y),
        f32(tilemap.tile_size.x),
        f32(tilemap.tile_size.y),
    }
    kit.DrawRectOutline(ctx, cell, 1, color)
    DrawCellText(ctx, tilemap, tile_pos, fmt.tprintf("%d", tile_id), font_size, color)
}

// A text centered in a cell of the tilemap
DrawCellText :: proc(ctx: ^kit.Context, tilemap: ^Tilemap, cell: vec2i, text: string, font_size: f32, color: kit.Color) {
    measured: kit.Vec2 = kit.MeasureText(ctx, text, font_size)
    position: kit.Vec2 = {
        f32(tilemap.position.x + cell.x * tilemap.tile_size.x) + (f32(tilemap.tile_size.x) - measured.x) * 0.5,
        f32(tilemap.position.y + cell.y * tilemap.tile_size.y) + (f32(tilemap.tile_size.y) - font_size) * 0.5,
    }
    kit.DrawText(ctx, text, position, font_size, color)
}

// Draw lines around selection
DrawTilemapSelection :: proc(ctx: ^kit.Context, tilemap: ^Tilemap, rect: recti, color: kit.Color) {
    kit.DrawRectOutline(ctx, {
        f32(tilemap.position.x + rect.x * tilemap.tile_size.x),
        f32(tilemap.position.y + rect.y * tilemap.tile_size.y),
        f32(rect.w * tilemap.tile_size.x),
        f32(rect.h * tilemap.tile_size.y),
    }, 1, color)
}

// skip_zero = true if TILE_EMPTY doesn't map to tile_atlas
DrawTilemap :: proc(ctx: ^kit.Context, tilemap: ^Tilemap, tileset: ^Tileset, tile_atlas: ^TileAtlas, skip_zero: bool, rand_type: TileRandType, texture: kit.Texture) {
    DrawTilemapRecti(ctx, tilemap, tileset, tile_atlas, skip_zero, rand_type, {0, 0, tilemap.size.x, tilemap.size.y}, texture)
}

// Draw selected region. For optimization draw only what is on a screen.
DrawTilemapRecti :: proc(ctx: ^kit.Context, tilemap: ^Tilemap, tileset: ^Tileset, tile_atlas: ^TileAtlas, skip_zero: bool, rand_type: TileRandType, region_rect: recti, texture: kit.Texture) {
    rect: recti = region_rect
    if rect.x < 0 {
        rect.w += rect.x
        rect.x = 0
    }
    if rect.y < 0 {
        rect.h += rect.y
        rect.y = 0
    }
    rect.w += rect.x
    rect.h += rect.y
    rect.w = min(rect.w, tilemap.size.x)
    rect.h = min(rect.h, tilemap.size.y)

    seed: u32 = tileset.random_seed
    for y in rect.y ..< rect.h {
        for x in rect.x ..< rect.w {
            cell_id: TileID = tilemap.grid[x + y * tilemap.size.x]
            if cell_id == tm.TILE_EMPTY && skip_zero { continue }
            tile_id: TileID
            switch rand_type {
            case .NONE: tile_id = tm.TilesetGetId(tileset, cell_id)
            case .SEED: tile_id = tm.TilesetGetTileAltRandom(tileset, cell_id, &seed)
            case .XY: tile_id = tm.TilesetGetTileAltDeterministic(tileset, cell_id, x, y)
            }
            cell_pos: kit.Vec2 = {f32(tilemap.position.x + x * tilemap.tile_size.x), f32(tilemap.position.y + y * tilemap.tile_size.y)}
            DrawTileAtlas(ctx, tile_atlas, tile_id, cell_pos, texture)
        }
    }
}
