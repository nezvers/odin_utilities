package tilemap_karl2d

import "../../karl2d"
Vec2 :: karl2d.Vec2
Rect :: karl2d.Rect
Color :: karl2d.Color
Font :: karl2d.Font
Texture :: karl2d.Texture

import tm ".."
vec2i :: tm.vec2i
recti :: tm.recti
rectf :: tm.rectf
TileAtlas :: tm.TileAtlas
TileID :: tm.TileID
Tile :: tm.Tile
Tileset :: tm.Tileset
Tilemap :: tm.Tilemap
TileRandType :: tm.TileRandType
TILE_EMPTY :: tm.TILE_EMPTY
TILE_INVALID :: tm.TILE_INVALID

// Drawing a tile from atlas directly
DrawTileAtlas :: proc(tile_atlas: ^TileAtlas, tile_id:TileID, draw_pos:Vec2, texture: ^Texture){
	tex_pos:Vec2 = tile_atlas.data[tile_id]
	tex_rect:Rect = {tex_pos.x,tex_pos.y, tile_atlas.tile_size.x, tile_atlas.tile_size.y}

	// karl2d.DrawTextureRec(texture^, tex_rect, draw_pos, karl2d.WHITE)
    karl2d.draw_texture_section(texture^, tex_rect, draw_pos)
}