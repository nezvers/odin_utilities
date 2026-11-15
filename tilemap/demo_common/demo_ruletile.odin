#+private file
package demo_common

// Rule tiles: a group tilemap says where solid ground is, the rules pick the tile of every cell by its neighbours.

import tm ".."
import tm_kit "../kit"
import kit "../../demo_kit"

@(private="package")
demo_ruletile: kit.Demo = {name = "ruletile", init = init, draw = draw, script = script}

AutotileRule:: tm.AutotileRule
RuleMatch:: tm.RuleMatch

RIGHTi:vec2i:   {1,0}
LEFTi:vec2i:    {-1,0}
UPi:vec2i:      {0,-1}
DOWNi:vec2i:    {0,1}
ZEROi:vec2i:    {0,0}


// Holds TileID of tileset groups (in example just one)
group_tilemap: Tilemap
group_buffer: [MAP_SIZE.x * MAP_SIZE.y]TileID

solid_id:TileID = 1 // Set group 1 at the same positions
// Can be procedurally generated or through custom editor
rules: []AutotileRule = {
        {1, {
            {solid_id, RIGHTi, false},
            {solid_id, ZEROi, false},
            {solid_id, DOWNi, false},
            {solid_id, LEFTi, true},
            {solid_id, UPi, true},
            },
        }, // Top-left corner
        {3, {
            {solid_id, ZEROi, false},
            {solid_id, LEFTi, false},
            {solid_id, DOWNi, false},
            {solid_id, RIGHTi, true},
            {solid_id, UPi, true},
            },
        }, // Top-right corner
        {21, {
            {solid_id, ZEROi, false},
            {solid_id, RIGHTi, false},
            {solid_id, UPi, false},
            {solid_id, LEFTi, true},
            {solid_id, DOWNi, true},
            },
        }, // Bottom-left corner
        {23, {
            {solid_id, ZEROi, false},
            {solid_id, LEFTi, false},
            {solid_id, UPi, false},
            {solid_id, RIGHTi, true},
            {solid_id, DOWNi, true},
            },
        }, // Bottom-right corner
        {2, {
            {solid_id, ZEROi, false},
            {solid_id, RIGHTi, false},
            {solid_id, LEFTi, false},
            {solid_id, DOWNi, false},
            {solid_id, UPi, true},
            },
        }, // Top-middle
        {11, {
            {solid_id, ZEROi, false},
            {solid_id, RIGHTi, false},
            {solid_id, DOWNi, false},
            {solid_id, UPi, false},
            {solid_id, LEFTi, true},
            },
        }, // Left-middle
        {13, {
            {solid_id, ZEROi, false},
            {solid_id, DOWNi, false},
            {solid_id, UPi, false},
            {solid_id, LEFTi, false},
            {solid_id, RIGHTi, true},
            },
        }, // Right-middle
        {22, {
            {solid_id, ZEROi, false},
            {solid_id, UPi, false},
            {solid_id, LEFTi, false},
            {solid_id, RIGHTi, false},
            {solid_id, DOWNi, true},
            },
        }, // Bottom-middle
        {4, {
            {solid_id, ZEROi, false},
            {solid_id, DOWNi, false},
            {solid_id, UPi, true},
            {solid_id, LEFTi, true},
            {solid_id, RIGHTi, true},
            },
        }, // Top single
        {14, {
            {solid_id, ZEROi, false},
            {solid_id, DOWNi, false},
            {solid_id, UPi, false},
            {solid_id, LEFTi, true},
            {solid_id, RIGHTi, true},
            },
        }, // Midle vertical single
        {24, {
            {solid_id, ZEROi, false},
            {solid_id, UPi, false},
            {solid_id, DOWNi, true},
            {solid_id, LEFTi, true},
            {solid_id, RIGHTi, true},
            },
        }, // Bottom single
        {34, {
            {solid_id, ZEROi, false},
            {solid_id, DOWNi, true},
            {solid_id, UPi, true},
            {solid_id, LEFTi, true},
            {solid_id, RIGHTi, true},
            },
        }, // Single block
        {31, {
            {solid_id, ZEROi, false},
            {solid_id, RIGHTi, false},
            {solid_id, DOWNi, true},
            {solid_id, UPi, true},
            {solid_id, LEFTi, true},
            },
        }, // Single left
        {32, {
            {solid_id, ZEROi, false},
            {solid_id, LEFTi, false},
            {solid_id, RIGHTi, false},
            {solid_id, DOWNi, true},
            {solid_id, UPi, true},
            },
        }, // Single horizontal middle
        {33, {
            {solid_id, ZEROi, false},
            {solid_id, LEFTi, false},
            {solid_id, DOWNi, true},
            {solid_id, UPi, true},
            {solid_id, RIGHTi, true},
            },
        }, // Single right
        {12, {{solid_id, ZEROi, false},}}, // Default to solid center
    }


init :: proc(ctx: ^kit.Context) {
    common_init(ctx)
    // same properties as main Tilemap
    group_tilemap = tm.TilemapInit(tilemap.position, tilemap.size, tilemap.tile_size, group_buffer[:])
    // reset map to predictable state
    tm.TilemapClear(&group_tilemap)
    // Init group tilemap: solid wherever the main one has a tile
    for y in 0 ..< group_tilemap.size.y {
        for x in 0 ..< group_tilemap.size.x {
            tile_pos: vec2i = {x, y}
            if tm.TilemapGetTile(&tilemap, tile_pos) == TILE_EMPTY { continue }
            tm.TilemapSetTile(&group_tilemap, tile_pos, solid_id)
        }
    }
    // Apply group rules to main Tilemap
    tm.AutotileRuleUpdateTilemap(&group_tilemap, &tilemap, rules[:])
}

draw :: proc(ctx: ^kit.Context) {
    skip_zero: bool = true
    tm_kit.DrawTilemap(ctx, &tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, tileset_texture)
    kit.DrawText(ctx, "Rule tile: Tilemap -> Tileset -> Tile -> TileAtlas (incomplete rule set)", {10, 10}, 20, kit.BLACK)
}

script: []kit.Step = {
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tm.TilemapGetTile(&group_tilemap, {2, 2}) == solid_id && tm.TilemapGetTile(&group_tilemap, {0, 0}) == TILE_EMPTY }, "the group tilemap is solid where the map had tiles"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tm.TilemapGetTile(&tilemap, {2, 2}) != TILE_EMPTY }, "the rules wrote tiles into the main tilemap"),
}
