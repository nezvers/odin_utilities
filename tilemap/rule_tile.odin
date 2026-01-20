package tilemap

RuleTile::struct {
    tile_id:TileID,
    group_id:TileID,
    included_cells:[]vec2i,
    excluded_cells:[]vec2i,
}

// Process single cell for tilemap_out
RuleTileUpdateCell::proc(tilemap_in:^Tilemap, tilemap_out:^Tilemap, rules:[]RuleTile, tile_pos:vec2i){
    assert(tile_pos.x > 0)
    assert(tile_pos.y > 0)
    assert(tile_pos.x < tilemap_in.tile_size.x)
    assert(tile_pos.y < tilemap_in.tile_size.y)
    assert(tile_pos.x < tilemap_out.tile_size.x)
    assert(tile_pos.y < tilemap_out.tile_size.y)

    rule:^RuleTile
    tile_in:TileID
    test_id:TileID
    include_match:bool
    exclude_match:bool

    index_out:int = tile_pos.x + tile_pos.y * tilemap_out.size.x

    for i:int; i < len(rules); i += 1 {
        rule = &rules[i]
        tile_in = TilemapGetTile(tilemap_in, tile_pos)
        if tile_in != rule.group_id {
            continue
        }
        
        include_match = true
        for j:int = 0; j < len(rule.included_cells); j += 1 {
            pos:vec2i = rule.included_cells[j]
            if pos.x < 0 || pos.x > (tilemap_in.size.x - 1) {
                include_match = false
                break
            }
            if pos.y < 0 || pos.y > (tilemap_in.size.y - 1) {
                include_match = false
                break
            }
            test_id = TilemapGetTile(tilemap_in, tile_pos)
            if test_id != rule.group_id {
                include_match = false
                break
            }
        }
        if !include_match {
            continue
        }

        exclude_match = true
        for j:int = 0; j < len(rule.excluded_cells); j += 1 {
            pos:vec2i = rule.excluded_cells[j]
            if pos.x < 0 || pos.x > (tilemap_in.size.x - 1) {
                exclude_match = false
                break
            }
            if pos.y < 0 || pos.y > (tilemap_in.size.y - 1) {
                exclude_match = false
                break
            }
            test_id = TilemapGetTile(tilemap_in, tile_pos)
            if test_id != rule.group_id {
                exclude_match = false
                break
            }
        }
        if !exclude_match {
            continue
        }

        // Match found
        tilemap_out.grid[index_out] = rule.tile_id
    }
}

RuleTileUpdateTilemap::proc(tilemap_in:^Tilemap, tilemap_out:^Tilemap, rules:[]RuleTile){
    assert(tilemap_in.size == tilemap_out.size)

    tile_pos:vec2i
    for y:int = 0; y < tilemap_in.size.y; y += 1 {
        for x:int = 0; x < tilemap_in.size.x; x += 1 {
            tile_pos = {x, y}
            RuleTileUpdateCell(tilemap_in, tilemap_out, rules[:], tile_pos)
        }
    }
}

RuleTileUpdateRect::proc(tilemap_in:^Tilemap, tilemap_out:^Tilemap, rules:[]RuleTile, region:recti){
    tile_pos:vec2i
    for y:int = region.y; y < (region.y + region.h); y += 1 {
        for x:int = region.x; x < (region.x + region.x); x += 1 {
            tile_pos = {x, y}
            RuleTileUpdateCell(tilemap_in, tilemap_out, rules[:], tile_pos)
        }
    }
}