package tilemap

// Process single cell for tilemap_out
AutotileRuleUpdateCell::proc(tilemap_in:^Tilemap, tilemap_out:^Tilemap, rules:[]AutotileRule, tile_pos:vec2i){
    assert(tile_pos.x >= 0)
    assert(tile_pos.y >= 0)
    assert(tile_pos.x < tilemap_in.tile_size.x)
    assert(tile_pos.y < tilemap_in.tile_size.y)
    assert(tile_pos.x < tilemap_out.tile_size.x)
    assert(tile_pos.y < tilemap_out.tile_size.y)

    rule:^AutotileRule
    test_id:TileID
    is_matching:bool
    match_pos:vec2i
    match_rule:^RuleMatch
    
    index_out:int = tile_pos.x + tile_pos.y * tilemap_out.size.x
    // TODO: remove
    tile_in:TileID = TilemapGetTile(tilemap_in, tile_pos)
    if tile_in != TILE_EMPTY {
        tile_in = tile_in
    }

    for i:int; i < len(rules); i += 1 {
        rule = &rules[i]
        
        is_matching = true
        for j:int = 0; j < len(rule.match); j += 1 {
            match_rule = &rule.match[j]
            match_pos = tile_pos + match_rule.offset
            
            // Check X boundry
            if (match_pos.x < 0 || match_pos.x > (tilemap_in.size.x - 1)) {
                if !match_rule.exclude || match_rule.id == TILE_EMPTY {
                    is_matching = false
                    break
                }
                continue
            }
            // Check Y boundry
            if match_pos.y < 0 || match_pos.y > (tilemap_in.size.y - 1) {
                if !match_rule.exclude || match_rule.id == TILE_EMPTY {
                    is_matching = false
                    break
                }
                continue
            }

            test_id = TilemapGetTile(tilemap_in, match_pos)
            if test_id != match_rule.id && !match_rule.exclude {
                is_matching = false
                break
            }
            if test_id == match_rule.id && match_rule.exclude {
                is_matching = false
                break
            }
        }
        if !is_matching {
            continue
        }

        // Match found
        // TODO: optionaly random skip
        tilemap_out.grid[index_out] = rule.tile_id
        break
    }
}

AutotileRuleUpdateTilemap::proc(tilemap_in:^Tilemap, tilemap_out:^Tilemap, rules:[]AutotileRule){
    assert(tilemap_in.size == tilemap_out.size)

    tile_pos:vec2i
    for y:int = 0; y < tilemap_in.size.y; y += 1 {
        for x:int = 0; x < tilemap_in.size.x; x += 1 {
            tile_pos = {x, y}
            AutotileRuleUpdateCell(tilemap_in, tilemap_out, rules[:], tile_pos)
        }
    }
}

AutotileRuleUpdateRect::proc(tilemap_in:^Tilemap, tilemap_out:^Tilemap, rules:[]AutotileRule, region:recti){
    rect:recti = TilemapClampRecti(tilemap_in, region)
    tile_pos:vec2i
    for y:int = rect.y; y < (rect.y + rect.h); y += 1 {
        for x:int = rect.x; x < (rect.x + rect.x); x += 1 {
            tile_pos = {x, y}
            AutotileRuleUpdateCell(tilemap_in, tilemap_out, rules[:], tile_pos)
        }
    }
}

AutotileRuleUpdateNeighbours::proc(tilemap_in:^Tilemap, tilemap_out:^Tilemap, rules:[]AutotileRule, tile_pos:vec2i){
    neighbour_list:[]vec2i = {
        tile_pos - {-1, -1},
        tile_pos - {0, -1},
        tile_pos - {1, -1},
        tile_pos - {-1, 0},
        tile_pos - {1, 0},
        tile_pos - {-1, 1},
        tile_pos - {0, 1},
        tile_pos - {1, 1},
    }
    test_pos:vec2i
    for i:int = 0; i < len(neighbour_list); i += 1 {
        test_pos = neighbour_list[i]
        if (test_pos.x < 0 || test_pos.y < 0 ){
            continue
        }
        if (test_pos.x > tilemap_in.size.x -1 || test_pos.y > tilemap_in.size.y -1){
            continue
        }
        AutotileRuleUpdateCell(tilemap_in, tilemap_out, rules[:], test_pos)
    }
}