#+private file
package demo

import tm ".."
import tr "../raylib"
import rl "vendor:raylib"

AutotileRule:: tm.AutotileRule
RuleMatch:: tm.RuleMatch
RIGHTi::tm.RIGHTi
LEFTi::tm.LEFTi
UPi::tm.UPi
DOWNi::tm.DOWNi
ZEROi::tm.ZEROi

@(private="package")
state_ruletile:State = {
    init,
    nil,
    nil,
    draw,
}

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

init::proc(){
    group_tilemap = tm.TilemapInit({100, 100}, MAP_SIZE, {16,16}, group_buffer[:])
	// reset map to predictable state
	tm.TilemapClear(&group_tilemap)

    // Init group tilemap
    tile_id:TileID
    tile_pos:vec2i
    for y:int = 0; y < MAP_SIZE.y; y += 1 {
        for x:int = 0; x < MAP_SIZE.x; x += 1 {
            tile_pos = {x, y}
            tile_id = tm.TilemapGetTile(&tilemap, tile_pos)
            if tile_id == TILE_EMPTY {
                // Group tilemap already zeroed out
                continue
            }
            tm.TilemapSetTile(&group_tilemap, tile_pos, solid_id) // 
        }
    }

    // Apply group rules to main Tilemap
    tm.AutotileRuleUpdateTilemap(&group_tilemap, &tilemap, rules[:])
}

draw::proc(){
    
	skip_zero:bool = true
	tr.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)

	rl.DrawText("Ruletile: Tilemap -> Tileset -> Tile -> TileAtlas", 10, 10, 20, rl.BLACK)
}

