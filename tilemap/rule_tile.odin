package tilemap
import "core:testing"

// Process single cell for tilemap_out
AutotileRuleUpdateCell::proc(tilemap_in:^Tilemap, tilemap_out:^Tilemap, rules:[]AutotileRule, tile_pos:vec2i) {
    assert(tile_pos.x >= 0)
    assert(tile_pos.y >= 0)
    assert(tile_pos.x < tilemap_in.size.x)
    assert(tile_pos.y < tilemap_in.size.y)
    assert(tile_pos.x < tilemap_out.size.x)
    assert(tile_pos.y < tilemap_out.size.y)

    rule:^AutotileRule
    test_id:TileID
    is_matching:bool
    match_pos:vec2i
    match_rule:^RuleMatch
    
    index_out:i32 = tile_pos.x + tile_pos.y * tilemap_out.size.x
    // TODO: remove
    tile_in:TileID = TilemapGetTile(tilemap_in, tile_pos)
    if (tile_in != TILE_EMPTY) {
        tile_in = tile_in
    }

    for i:i32; i < cast(i32)len(rules); i += 1 {
        rule = &rules[i]
        
        is_matching = true
        for j:i32 = 0; j < cast(i32)len(rule.match); j += 1 {
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

AutotileRuleUpdateTilemap::proc(tilemap_in:^Tilemap, tilemap_out:^Tilemap, rules:[]AutotileRule) {
    assert(tilemap_in.size == tilemap_out.size)
    assert(len(tilemap_in.grid) >= len(tilemap_out.grid))

    tile_pos:vec2i
    for y:i32 = 0; y < tilemap_in.size.y; y += 1 {
        for x:i32 = 0; x < tilemap_in.size.x; x += 1 {
            tile_pos = {x, y}
            AutotileRuleUpdateCell(tilemap_in, tilemap_out, rules[:], tile_pos)
        }
    }
}

AutotileRuleUpdateRect::proc(tilemap_in:^Tilemap, tilemap_out:^Tilemap, rules:[]AutotileRule, region:recti) {
    rect:recti = TilemapClampRecti(tilemap_in, region)
    tile_pos:vec2i
    for y:i32 = rect.y; y < (rect.y + rect.h); y += 1 {
        for x:i32 = rect.x; x < (rect.x + rect.w); x += 1 {
            tile_pos = {x, y}
            AutotileRuleUpdateCell(tilemap_in, tilemap_out, rules[:], tile_pos)
        }
    }
}

AutotileRuleUpdateNeighbours::proc(tilemap_in:^Tilemap, tilemap_out:^Tilemap, rules:[]AutotileRule, tile_pos:vec2i) {
    neighbour_list:[]vec2i = {
        tile_pos + {-1, -1},
        tile_pos + {0, -1},
        tile_pos + {1, -1},
        tile_pos + {-1, 0},
        tile_pos + {1, 0},
        tile_pos + {-1, 1},
        tile_pos + {0, 1},
        tile_pos + {1, 1},
    }
    test_pos:vec2i
    for i:int = 0; i < len(neighbour_list); i += 1 {
        test_pos = neighbour_list[i]
        if (test_pos.x < 0 || test_pos.y < 0 ) {
            continue
        }
        if (test_pos.x > tilemap_in.size.x -1 || test_pos.y > tilemap_in.size.y -1) {
            continue
        }
        AutotileRuleUpdateCell(tilemap_in, tilemap_out, rules[:], test_pos)
    }
}

// --- Tests ---

// A tilemap pair for the rule tests: id 1 is ground, anything else is air.
@(private="file")
RuleMaps :: struct {
    input, output: Tilemap,
    input_buffer, output_buffer: [128]TileID,
}

@(private="file")
init_rule_maps :: proc(maps: ^RuleMaps, size: vec2i, rows: []string) {
    // the tile size is small on purpose: it has nothing to do with the number of cells
    maps.input = TilemapInit({0, 0}, size, {4, 4}, maps.input_buffer[:size.x * size.y])
    maps.output = TilemapInit({0, 0}, size, {4, 4}, maps.output_buffer[:size.x * size.y])
    for y in 0 ..< size.y {
        for x in 0 ..< size.x {
            if rows[y][x] == '#' { TilemapSetTile(&maps.input, {x, y}, 1) }
        }
    }
}

@(private="file")
output_rows :: proc(tilemap: ^Tilemap, allocator := context.temp_allocator) -> []string {
    rows := make([]string, tilemap.size.y, allocator)
    for y in 0 ..< tilemap.size.y {
        row := make([]u8, tilemap.size.x, allocator)
        for x in 0 ..< tilemap.size.x {
            id: TileID = TilemapGetTile(tilemap, {x, y})
            row[x] = '.' if id == 0 else u8('0') + id
        }
        rows[y] = string(row)
    }
    return rows
}

@(test)
test_autotile_top_edge_rule :: proc(t: ^testing.T) {
    maps: RuleMaps
    init_rule_maps(&maps, {12, 3}, {"............", "############", "############"})

    rules: []AutotileRule = {
        {tile_id = 2, match = []RuleMatch{{id = 1}, {id = 1, offset = {0, -1}, exclude = true}}},   // ground with no ground above
        {tile_id = 3, match = []RuleMatch{{id = 1}}},                                               // any other ground
    }
    AutotileRuleUpdateTilemap(&maps.input, &maps.output, rules)

    rows: []string = output_rows(&maps.output)
    testing.expect_value(t, rows[0], "............")
    testing.expect_value(t, rows[1], "222222222222")
    testing.expect_value(t, rows[2], "333333333333")
}

@(test)
test_autotile_boundaries :: proc(t: ^testing.T) {
    maps: RuleMaps
    init_rule_maps(&maps, {4, 1}, {".###"})

    // a required neighbour outside the map never matches
    needs_left: []AutotileRule = {{tile_id = 4, match = []RuleMatch{{id = 1}, {id = 1, offset = {-1, 0}}}}}
    AutotileRuleUpdateTilemap(&maps.input, &maps.output, needs_left)
    testing.expect_value(t, output_rows(&maps.output)[0], "..44")                          // the first ground cell has air to its left

    // an excluded neighbour outside the map counts as "not that tile"
    TilemapClear(&maps.output)
    no_ground_left: []AutotileRule = {{tile_id = 5, match = []RuleMatch{{id = 1}, {id = 1, offset = {-1, 0}, exclude = true}}}}
    AutotileRuleUpdateTilemap(&maps.input, &maps.output, no_ground_left)
    testing.expect_value(t, output_rows(&maps.output)[0], ".5..")

    testing.expect_value(t, TilemapGetTile(&maps.input, {1, 0}), TileID(1))                // the input is only read
}

@(test)
test_autotile_cell_and_rect_updates :: proc(t: ^testing.T) {
    maps: RuleMaps
    init_rule_maps(&maps, {12, 3}, {"############", "############", "############"})
    rules: []AutotileRule = {{tile_id = 6, match = []RuleMatch{{id = 1}}}}

    AutotileRuleUpdateCell(&maps.input, &maps.output, rules, {10, 2})                      // far to the right, beyond the tile size
    testing.expect_value(t, output_rows(&maps.output)[2], "..........6.")

    TilemapClear(&maps.output)
    AutotileRuleUpdateRect(&maps.input, &maps.output, rules, {2, 1, 4, 1})
    rows: []string = output_rows(&maps.output)
    testing.expect_value(t, rows[0], "............")
    testing.expect_value(t, rows[1], "..6666......")                                        // the whole width of the region
    testing.expect_value(t, rows[2], "............")

    TilemapClear(&maps.output)
    AutotileRuleUpdateRect(&maps.input, &maps.output, rules, {-5, -5, 7, 7})               // clipped to the map
    rows = output_rows(&maps.output)
    testing.expect_value(t, rows[0], "66..........")
    testing.expect_value(t, rows[1], "66..........")
    testing.expect_value(t, rows[2], "............")
}

@(test)
test_autotile_neighbour_updates :: proc(t: ^testing.T) {
    maps: RuleMaps
    init_rule_maps(&maps, {3, 3}, {"###", "###", "###"})
    rules: []AutotileRule = {{tile_id = 9, match = []RuleMatch{{id = 1}}}}

    AutotileRuleUpdateNeighbours(&maps.input, &maps.output, rules, {1, 1})
    rows: []string = output_rows(&maps.output)
    testing.expect_value(t, rows[0], "999")
    testing.expect_value(t, rows[1], "9.9")                                                // everything around the changed cell, but not the cell itself
    testing.expect_value(t, rows[2], "999")

    TilemapClear(&maps.output)
    AutotileRuleUpdateNeighbours(&maps.input, &maps.output, rules, {0, 0})                 // a corner has only three neighbours
    rows = output_rows(&maps.output)
    testing.expect_value(t, rows[0], ".9.")
    testing.expect_value(t, rows[1], "99.")
    testing.expect_value(t, rows[2], "...")
}
