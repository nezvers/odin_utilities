#+private file
package game

import tm "../.."
import "../../../karl2d"
import tm_glue "../../karl2d"

@(private="package")
tilemap_dualgrid_state: GameState = {
    init,
    finit,
    process,
    draw,
}

// Ported from Karl2D example dual_grid_tilemap

DUALGRID_MAP_SIZE:vec2i: {16, 12}
TILE_GRASS:TileID: TILE_EMPTY
TILE_PATH:TileID: 1

// Data tilemap holds what user paints
dualgrid_data: Tilemap
dualgrid_data_buffer: [DUALGRID_MAP_SIZE.x * DUALGRID_MAP_SIZE.y]TileID
// Display tilemap is half tile offset, 1 cell bigger and holds tiles picked by 4 neighbour data cells
dualgrid_display: Tilemap
dualgrid_display_buffer: [(DUALGRID_MAP_SIZE.x + 1) * (DUALGRID_MAP_SIZE.y + 1)]TileID

init :: proc() {
    dualgrid_data = tm.TilemapInit({100, 100}, DUALGRID_MAP_SIZE, TILE_SIZE, dualgrid_data_buffer[:])
    tm.TilemapClear(&dualgrid_data)
    dualgrid_display = tm.DualGridInit(&dualgrid_data, dualgrid_display_buffer[:])
    tm.DualGridUpdateTilemap(&dualgrid_data, &dualgrid_display, TILE_PATH, tm.DUAL_GRID_MASK_TO_TILE[:])
}

finit :: proc() {}

process :: proc() {}

draw :: proc() {
    karl2d.clear(karl2d.WHITE)

    @(static) position_state:vec2i
    mouse_position:Vec2 = karl2d.get_mouse_position()
    mouse_position_i:vec2i = {cast(i32)mouse_position.x, cast(i32)mouse_position.y}

    is_ctrl:bool = karl2d.get_held_modifiers() == { .Control }
    input_paint:InputState = InputState.NONE
    input_erase:InputState = InputState.NONE
    if is_ctrl {
        input_erase = tm.GetInputState(
            karl2d.mouse_button_went_down(.Left),
            karl2d.mouse_button_is_held(.Left),
            karl2d.mouse_button_went_up(.Left),
        )
    } else {
        input_paint = tm.GetInputState(
            karl2d.mouse_button_went_down(.Left),
            karl2d.mouse_button_is_held(.Left),
            karl2d.mouse_button_went_up(.Left),
        )
    }
    if input_erase == InputState.NONE {
        input_erase = tm.GetInputState(
            karl2d.mouse_button_went_down(.Right),
            karl2d.mouse_button_is_held(.Right),
            karl2d.mouse_button_went_up(.Right),
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
    grass_rect:Rect = {
        cast(f32)dualgrid_data.position.x,
        cast(f32)dualgrid_data.position.y,
        cast(f32)(dualgrid_data.size.x * dualgrid_data.tile_size.x),
        cast(f32)(dualgrid_data.size.y * dualgrid_data.tile_size.y),
    }
    karl2d.draw_rect(grass_rect, karl2d.LIGHT_GREEN)

    skip_zero:bool = true
    tm_glue.DrawTilemap(&dualgrid_display, &tileset_dualgrid, &tile_atlas_dualgrid, skip_zero, tm.TileRandType.NONE, &tileset_dualgrid_texture)
    tm_glue.DrawTilemapGrid(&dualgrid_data, karl2d.LIGHT_GRAY)

    mouse_id:TileID = tm.TilemapGetTileWorld(&dualgrid_data, mouse_position_i)
    if mouse_id != TILE_INVALID {
        tm_glue.DrawTilemapCellRect(&dualgrid_data, mouse_position_i, mouse_id, karl2d.FONT_DEFAULT, 10, karl2d.WHITE)
    }

    karl2d.draw_text("left mouse paint path, right mouse or CTRL + left mouse erase", {10, 10}, 20, karl2d.BLACK)
}
