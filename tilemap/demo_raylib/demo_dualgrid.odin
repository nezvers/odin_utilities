#+private file
package demo_raylib

import tm ".."
import tm_glue "../raylib"
import rl "vendor:raylib"

@(private="package")
state_dualgrid:State = {
    init,
    nil,
    nil,
    draw,
}

DUALGRID_MAP_SIZE:vec2i: {16, 12}
TILE_GRASS:TileID: TILE_EMPTY
TILE_PATH:TileID: 1

// Data tilemap holds what user paints
dualgrid_data: Tilemap
dualgrid_data_buffer: [DUALGRID_MAP_SIZE.x * DUALGRID_MAP_SIZE.y]TileID
// Display tilemap is half tile offset, 1 cell bigger and holds tiles picked by 4 neighbour data cells
dualgrid_display: Tilemap
dualgrid_display_buffer: [(DUALGRID_MAP_SIZE.x + 1) * (DUALGRID_MAP_SIZE.y + 1)]TileID

init::proc(){
    dualgrid_data = tm.TilemapInit({100, 100}, DUALGRID_MAP_SIZE, TILE_SIZE, dualgrid_data_buffer[:])
    tm.TilemapClear(&dualgrid_data)
    dualgrid_display = tm.DualGridInit(&dualgrid_data, dualgrid_display_buffer[:])
    tm.DualGridUpdateTilemap(&dualgrid_data, &dualgrid_display, TILE_PATH, tm.DUAL_GRID_MASK_TO_TILE[:])
}

draw::proc(){
    @(static) position_state:vec2i
    mouse_position:Vector2 = rl.GetMousePosition()
    mouse_position_i:vec2i = {cast(i32)mouse_position.x, cast(i32)mouse_position.y}

    is_ctrl:bool = rl.IsKeyDown(rl.KeyboardKey.LEFT_CONTROL) || rl.IsKeyDown(rl.KeyboardKey.RIGHT_CONTROL)
    input_paint:InputState = InputState.NONE
    input_erase:InputState = InputState.NONE
    if is_ctrl {
        input_erase = tm.GetInputState(
            rl.IsMouseButtonPressed(rl.MouseButton.LEFT),
            rl.IsMouseButtonDown(rl.MouseButton.LEFT),
            rl.IsMouseButtonReleased(rl.MouseButton.LEFT),
        )
    } else {
        input_paint = tm.GetInputState(
            rl.IsMouseButtonPressed(rl.MouseButton.LEFT),
            rl.IsMouseButtonDown(rl.MouseButton.LEFT),
            rl.IsMouseButtonReleased(rl.MouseButton.LEFT),
        )
    }
    if input_erase == InputState.NONE {
        input_erase = tm.GetInputState(
            rl.IsMouseButtonPressed(rl.MouseButton.RIGHT),
            rl.IsMouseButtonDown(rl.MouseButton.RIGHT),
            rl.IsMouseButtonReleased(rl.MouseButton.RIGHT),
        )
    }

    if !is_hovering_buttons {
        if input_paint != InputState.NONE {
            tm.PaintTiles(&dualgrid_data, mouse_position_i, &position_state, TILE_PATH, input_paint)
        }
        if input_erase != InputState.NONE {
            tm.PaintTiles(&dualgrid_data, mouse_position_i, &position_state, TILE_GRASS, input_erase)
        }
        if input_paint != InputState.NONE || input_erase != InputState.NONE {
            // Display only changes under cursor, but whole update is cheap
            tm.DualGridUpdateTilemap(&dualgrid_data, &dualgrid_display, TILE_PATH, tm.DUAL_GRID_MASK_TO_TILE[:])
        }
    }

    // Grass is drawn below, because path tiles have transparent pixels
    grass_rect:Rectangle = {
        cast(f32)dualgrid_data.position.x,
        cast(f32)dualgrid_data.position.y,
        cast(f32)(dualgrid_data.size.x * dualgrid_data.tile_size.x),
        cast(f32)(dualgrid_data.size.y * dualgrid_data.tile_size.y),
    }
    rl.DrawRectangleRec(grass_rect, rl.GREEN)

    skip_zero:bool = true
    tm_glue.DrawTilemap(&dualgrid_display, &tileset_dualgrid, &tile_atlas_dualgrid, skip_zero, tm.TileRandType.NONE, &tileset_dualgrid_texture)
    tm_glue.DrawTilemapGrid(&dualgrid_data, rl.LIGHTGRAY)

    mouse_id:TileID = tm.TilemapGetTileWorld(&dualgrid_data, mouse_position_i)
    if mouse_id != TILE_INVALID {
        tm_glue.DrawTilemapCellRect(&dualgrid_data, mouse_position_i, mouse_id, rl.GetFontDefault(), 10, rl.WHITE)
    }

    rl.DrawText("draw_tilemap_dualgrid: left mouse paint path, right mouse or CTRL + left mouse erase", 10, 10, 20, rl.BLACK)
}
