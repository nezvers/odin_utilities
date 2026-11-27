#+private file
package demo_common

// Dual grid: the data tilemap holds what the user paints, a display tilemap is half a tile offset and one cell bigger, every display cell picks
// its tile from the 4 data cells around it. Draw the display tilemap with the usual DrawTilemap.

import tm ".."
import tm_kit "../kit"
import kit "../../demo_kit"

@(private="package")
demo_dualgrid: kit.Demo = {name = "dual grid", init = init, draw = draw, script = script}

DUALGRID_MAP_SIZE :: vec2i{16, 12}
TILE_GRASS :: TileID(TILE_EMPTY)
TILE_PATH :: TileID(1)

// Data tilemap holds what user paints
dualgrid_data: Tilemap
dualgrid_data_buffer: [DUALGRID_MAP_SIZE.x * DUALGRID_MAP_SIZE.y]TileID

// Display tilemap is half tile offset, 1 cell bigger and holds tiles picked by 4 neighbour data cells
dualgrid_display: Tilemap
dualgrid_display_buffer: [(DUALGRID_MAP_SIZE.x + 1) * (DUALGRID_MAP_SIZE.y + 1)]TileID
position_state: vec2i

init :: proc(ctx: ^kit.Context) {
    common_init(ctx)
    dualgrid_data = tm.TilemapInit({100, 100}, DUALGRID_MAP_SIZE, TILE_SIZE, dualgrid_data_buffer[:])
    tm.TilemapClear(&dualgrid_data)
    dualgrid_display = tm.DualGridInit(&dualgrid_data, dualgrid_display_buffer[:])
    tm.DualGridUpdateTilemap(&dualgrid_data, &dualgrid_display, TILE_PATH, tm.DUAL_GRID_MASK_TO_TILE[:])
}

draw :: proc(ctx: ^kit.Context) {
    mouse: vec2i = mouse_cell(ctx)
    is_ctrl: bool = kit.CtrlDown(&ctx.input)
    input_paint: InputState = InputState.NONE
    input_erase: InputState = InputState.NONE
    if is_ctrl {
        input_erase = mouse_state(ctx, .LEFT)
    } else {
        input_paint = mouse_state(ctx, .LEFT)
    }
    if input_erase == InputState.NONE {
        input_erase = mouse_state(ctx, .RIGHT)
    }

    if !ctx.ui_hover {
        if input_paint != InputState.NONE {
            tm.PaintTiles(&dualgrid_data, mouse, &position_state, TILE_PATH, input_paint)
        }
        if input_erase != InputState.NONE {
            tm.PaintTiles(&dualgrid_data, mouse, &position_state, TILE_GRASS, input_erase)
        }
        if input_paint != InputState.NONE || input_erase != InputState.NONE {
            // Display only changes under cursor, but whole update is cheap
            tm.DualGridUpdateTilemap(&dualgrid_data, &dualgrid_display, TILE_PATH, tm.DUAL_GRID_MASK_TO_TILE[:])
        }
    }

    // Grass is drawn below, because path tiles have transparent pixels
    kit.DrawRect(ctx, {
        f32(dualgrid_data.position.x),
        f32(dualgrid_data.position.y),
        f32(dualgrid_data.size.x * dualgrid_data.tile_size.x),
        f32(dualgrid_data.size.y * dualgrid_data.tile_size.y),
    }, kit.GREEN)
    skip_zero: bool = true
    tm_kit.DrawTilemap(ctx, &dualgrid_display, &tileset_dualgrid, &tile_atlas_dualgrid, skip_zero, tm.TileRandType.NONE, tileset_dualgrid_texture)
    tm_kit.DrawTilemapGrid(ctx, &dualgrid_data, kit.LIGHT_GRAY)
    mouse_id: TileID = tm.TilemapGetTileWorld(&dualgrid_data, mouse)
    if mouse_id != TILE_INVALID {
        tm_kit.DrawTilemapCellRect(ctx, &dualgrid_data, mouse, mouse_id, 10, kit.WHITE)
    }
    kit.DrawText(ctx, "draw_tilemap_dualgrid: left mouse paint path, right mouse or CTRL + left mouse erase", {10, 10}, 20, kit.BLACK)
}

path_cells :: proc() -> (count: int) {
    for id in dualgrid_data.grid { if id == TILE_PATH { count += 1 } }
    return
}

// how many kinds of tile the display uses: an empty map shows one, edges and corners add more
display_kinds :: proc() -> (count: int) {
    seen: [256]bool
    for id in dualgrid_display.grid {
        if !seen[id] { seen[id] = true; count += 1 }
    }
    return
}

kinds_before: int

script: []kit.Step = {
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        kinds_before = display_kinds()
        return path_cells() == 0 && kinds_before == 1
    }, "an empty map shows one kind of tile everywhere"),
    // paint a line of path cells with the left button: x 3 .. 6 on the row 4
    kit.MoveTo({100 + 16 * 3 + 4, 100 + 16 * 4 + 4}), kit.MouseDownStep(), kit.Wait(1), kit.MoveTo({100 + 16 * 6 + 4, 100 + 16 * 4 + 4}), kit.Wait(1), kit.MouseUpStep(), kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return path_cells() >= 2 }, "the left button paints path cells"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return display_kinds() > kinds_before }, "the display grid picks edge and corner tiles around the painted cells"),
    kit.Click({100 + 16 * 3 + 4, 100 + 16 * 4 + 4}, .RIGHT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return tm.TilemapGetTile(&dualgrid_data, {3, 4}) == TILE_GRASS }, "the right button erases"),
    kit.Wait(2),
    kit.Capture("tilemap_dualgrid_end"),
    kit.Wait(1),
}
