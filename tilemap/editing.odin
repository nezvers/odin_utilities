package tilemap
import "core:math"
import "core:testing"

InputState :: enum {
    NONE,
    START,
    HOLD,
    RELEASE,
}

InputType :: enum {
    NONE,
    INCREASE,
    DECREASE,
}


GetInputState :: proc(is_pressed:bool, is_held:bool, is_released:bool)->InputState {
    if is_pressed {
        return InputState.START
    }
    if is_held {
        return InputState.HOLD
    }
    if is_released {
        return InputState.RELEASE
    }
    return InputState.NONE
}

GetInputType :: proc(is_increase:bool, is_decrease:bool)->InputType {
    if is_increase {
        return InputType.INCREASE
    }
    if is_decrease {
        return InputType.DECREASE
    }
    return InputType.NONE
}

// Draw a rectangle around tiles from press to release
CreateSelection :: proc(
    tilemap: ^Tilemap, 
    input_position:vec2i,
    position_state: ^vec2i,
    rect_state: ^recti,
    input_state:InputState,
){
    if input_state == InputState.START {
        position_state^ = TilemapGetWorld2Tile(tilemap, input_position)
    } else
    if (input_state == InputState.HOLD){
        drag_position: = TilemapGetWorld2Tile(tilemap, input_position)
        rect_state^ = RectiFromRange(position_state^, drag_position)
    }
}

// Copy tiles inside map_rect and drop them when released
DragTiles :: proc(
    tilemap: ^Tilemap,
    temp_tilemap_out: ^Tilemap,
    input_position:vec2i,
    drag_start_position: ^vec2i,
    selection_rect: ^recti,
    input_state: InputState,
    remove_from_source:bool,
    write_empty:bool,
    temp_buffer: []TileID,
){
    if (selection_rect.w == 0 || selection_rect.h == 0){
        return
    }
    if input_state == InputState.START {
        // trim selection outside borders
        tilemap_rect:recti = TilemapRecti(tilemap)
        RectiClipRecti(&tilemap_rect, selection_rect)

        if (selection_rect.w == 0 || selection_rect.h == 0){
            // no selection
            return
        }

        TilemapGetRegionData(tilemap, selection_rect^, temp_buffer)
        
        selection_position:vec2i = {selection_rect.x, selection_rect.y}
        map_position:vec2i = tilemap.position + tilemap.tile_size * selection_position
        map_size:vec2i = {selection_rect.w, selection_rect.h}
        temp_tilemap_out^ = TilemapInit(map_position, map_size, tilemap.tile_size, temp_buffer)
        // Alternatively - TilemapSetRegionData
        TilemapSetData(temp_tilemap_out, temp_buffer, cast(u32)map_size.x, cast(u32)map_size.y)

        tile_pos:vec2i = TilemapGetWorld2Tile(tilemap, input_position)
        drag_start_position^ = selection_position - tile_pos
    } else if (input_state == InputState.HOLD){

        tile_pos:vec2i = TilemapGetWorld2Tile(tilemap, input_position)
        tile_offset:vec2i = tile_pos + drag_start_position^
        temp_tilemap_out.position = tilemap.position + tile_offset * tilemap.tile_size
    } else if (input_state == InputState.RELEASE){
        // Place tile data
        tile_pos:vec2i = TilemapGetWorld2Tile(tilemap, input_position)
        tile_offset:vec2i = tile_pos + drag_start_position^
        temp_tilemap_out.position = tilemap.position + tile_offset * tilemap.tile_size

        if remove_from_source {
            TilemapSetTileIdBlock(tilemap, selection_rect.x, selection_rect.y, selection_rect.w, selection_rect.h, TILE_EMPTY)
        }

        data_rect:recti = {
            tile_offset.x,
            tile_offset.y,
            selection_rect.w,
            selection_rect.h,
        }
        TilemapSetRegionData(tilemap, data_rect, temp_buffer, write_empty)

        temp_tilemap_out.size = {0, 0}
        selection_rect.w = 0.0
        selection_rect.h = 0.0
    }
}

// Increase or decrease tile ID under input_position 
EditTiles :: proc(
    tilemap: ^Tilemap,
    input_position:vec2i,
    tile_id_state: ^TileID,
    input_type: InputType,
){
    if (input_type == InputType.NONE){
        return
    }

    tile_id:TileID = TilemapGetTileWorld(tilemap, input_position)
    if (tile_id == TILE_INVALID){
        return
    }

    // when the step is not possible (the reserved invalid id would be next) the tile keeps its own id
    tile_id_state^ = tile_id
    if (input_type == InputType.INCREASE && (tile_id + 1) != TILE_INVALID){
        tile_id_state^ = tile_id + 1
    } else if (input_type == InputType.DECREASE && (tile_id - 1) != TILE_INVALID){
        tile_id_state^ = tile_id - 1
    }

    TilemapSetTileWorld(tilemap, input_position, tile_id_state^)
}

// Draw with tile_id
PaintTiles :: proc(
    tilemap: ^Tilemap,
    input_position:vec2i,
    state_position: ^vec2i,
    tile_id_input: TileID,
    input_state: InputState,
){
    if (tile_id_input == TILE_INVALID){
        return
    }

    if (input_state == InputState.START){
        state_position^ = TilemapGetWorld2Tile(tilemap, input_position)
        tile_id:TileID = TilemapGetTile(tilemap, state_position^)
        if (tile_id == TILE_INVALID){
            return
        }
        TilemapSetTile(tilemap, state_position^, tile_id_input)
    } else if (input_state == InputState.HOLD){
        new_position:vec2i = TilemapGetWorld2Tile(tilemap, input_position)
        if (new_position == state_position^){
            return
        }
        state_position^ = new_position
        tile_id:TileID = TilemapGetTile(tilemap, state_position^)
        if (tile_id == TILE_INVALID){
            return
        }
        TilemapSetTile(tilemap, state_position^, tile_id_input)
    }
}

// Drag'n'Drop a tilemap
MoveTilemap :: proc(
    tilemap: ^Tilemap,
    input_position:vec2i,
    drag_start_position: ^vec2i,
    map_start_position: ^vec2i,
    input_state: InputState,
    grid_lock:bool,
){
    if (input_state == InputState.START){
        map_start_position^ = tilemap.position
        drag_start_position^ = input_position
    } else if (input_state == InputState.HOLD){
        drag_difference:vec2i = input_position - drag_start_position^
        if (!grid_lock){
            tilemap.position = map_start_position^ + drag_difference
            return
        }
        // floored, so the map snaps to the cell on the left and above the start in the same way as on the right
        tile_difference:vec2i = {
            math.floor_div(drag_difference.x, tilemap.tile_size.x),
            math.floor_div(drag_difference.y, tilemap.tile_size.y),
        }

        tilemap.position = map_start_position^ + tile_difference * tilemap.tile_size
    }
}

// --- Tests ---

@(private="file")
make_edit_map :: proc(buffer: []TileID) -> Tilemap {
    return TilemapInit({0, 0}, {6, 4}, {16, 16}, buffer)
}

@(test)
test_input_state_and_type :: proc(t: ^testing.T) {
    testing.expect_value(t, GetInputState(true, true, false), InputState.START)            // a press wins over the hold
    testing.expect_value(t, GetInputState(false, true, true), InputState.HOLD)
    testing.expect_value(t, GetInputState(false, false, true), InputState.RELEASE)
    testing.expect_value(t, GetInputState(false, false, false), InputState.NONE)
    testing.expect_value(t, GetInputType(true, true), InputType.INCREASE)
    testing.expect_value(t, GetInputType(false, true), InputType.DECREASE)
    testing.expect_value(t, GetInputType(false, false), InputType.NONE)
}

@(test)
test_create_selection :: proc(t: ^testing.T) {
    buffer: [24]TileID
    tilemap: Tilemap = make_edit_map(buffer[:])
    start: vec2i
    selection: recti

    CreateSelection(&tilemap, {20, 36}, &start, &selection, .START)
    testing.expect_value(t, start, vec2i{1, 2})
    CreateSelection(&tilemap, {70, 20}, &start, &selection, .HOLD)                         // dragged up and to the right
    testing.expect_value(t, selection, recti{1, 1, 4, 2})
    CreateSelection(&tilemap, {70, 20}, &start, &selection, .RELEASE)                      // release keeps the selection
    testing.expect_value(t, selection, recti{1, 1, 4, 2})
}

@(test)
test_paint_tiles :: proc(t: ^testing.T) {
    buffer: [24]TileID
    tilemap: Tilemap = make_edit_map(buffer[:])
    last: vec2i

    PaintTiles(&tilemap, {20, 20}, &last, 3, .START)
    testing.expect_value(t, TilemapGetTile(&tilemap, {1, 1}), TileID(3))
    PaintTiles(&tilemap, {40, 20}, &last, 3, .HOLD)
    testing.expect_value(t, TilemapGetTile(&tilemap, {2, 1}), TileID(3))
    testing.expect_value(t, last, vec2i{2, 1})

    TilemapSetTile(&tilemap, {2, 1}, 8)
    PaintTiles(&tilemap, {41, 21}, &last, 3, .HOLD)                                        // still the same cell: not painted again
    testing.expect_value(t, TilemapGetTile(&tilemap, {2, 1}), TileID(8))

    PaintTiles(&tilemap, {500, 20}, &last, 3, .HOLD)                                       // off the map
    PaintTiles(&tilemap, {20, 20}, &last, TILE_INVALID, .START)                            // the invalid id never paints
    testing.expect_value(t, TilemapGetTile(&tilemap, {1, 1}), TileID(3))
}

@(test)
test_edit_tiles_increase_and_decrease :: proc(t: ^testing.T) {
    buffer: [24]TileID
    tilemap: Tilemap = make_edit_map(buffer[:])
    TilemapSetTile(&tilemap, {1, 1}, 5)
    state: TileID

    EditTiles(&tilemap, {20, 20}, &state, .INCREASE)
    testing.expect_value(t, TilemapGetTile(&tilemap, {1, 1}), TileID(6))
    testing.expect_value(t, state, TileID(6))
    EditTiles(&tilemap, {20, 20}, &state, .DECREASE)
    testing.expect_value(t, TilemapGetTile(&tilemap, {1, 1}), TileID(5))
    EditTiles(&tilemap, {20, 20}, &state, .NONE)
    testing.expect_value(t, TilemapGetTile(&tilemap, {1, 1}), TileID(5))

    EditTiles(&tilemap, {500, 500}, &state, .INCREASE)                                     // outside the map
    TilemapSetTile(&tilemap, {1, 1}, 254)
    EditTiles(&tilemap, {20, 20}, &state, .INCREASE)                                       // 255 is reserved and is not reached
    testing.expect_value(t, TilemapGetTile(&tilemap, {1, 1}), TileID(254))
    TilemapSetTile(&tilemap, {1, 1}, 0)
    EditTiles(&tilemap, {20, 20}, &state, .DECREASE)
    testing.expect_value(t, TilemapGetTile(&tilemap, {1, 1}), TileID(0))
}

@(test)
test_move_tilemap :: proc(t: ^testing.T) {
    buffer: [24]TileID
    tilemap: Tilemap = make_edit_map(buffer[:])
    tilemap.position = {32, 32}
    drag_start, map_start: vec2i

    MoveTilemap(&tilemap, {50, 50}, &drag_start, &map_start, .START, false)
    MoveTilemap(&tilemap, {57, 44}, &drag_start, &map_start, .HOLD, false)
    testing.expect_value(t, tilemap.position, vec2i{39, 26})                               // follows the pointer exactly

    MoveTilemap(&tilemap, {70, 50}, &drag_start, &map_start, .HOLD, true)                  // locked to the grid: 20 px is one tile
    testing.expect_value(t, tilemap.position, vec2i{48, 32})
    MoveTilemap(&tilemap, {34, 50}, &drag_start, &map_start, .HOLD, true)                  // -16 px is exactly one tile left
    testing.expect_value(t, tilemap.position, vec2i{16, 32})
    MoveTilemap(&tilemap, {33, 50}, &drag_start, &map_start, .HOLD, true)                  // -17 px is already past it
    testing.expect_value(t, tilemap.position, vec2i{0, 32})
}

@(test)
test_drag_tiles_moves_a_selection :: proc(t: ^testing.T) {
    buffer: [24]TileID
    tilemap: Tilemap = make_edit_map(buffer[:])
    TilemapSetTileIdBlock(&tilemap, 1, 1, 2, 2, 5)

    drag_buffer: [4]TileID
    dragged: Tilemap
    drag_start: vec2i
    selection: recti = {1, 1, 2, 2}

    DragTiles(&tilemap, &dragged, {20, 20}, &drag_start, &selection, .START, true, false, drag_buffer[:])
    testing.expect_value(t, dragged.size, vec2i{2, 2})
    testing.expect_value(t, dragged.position, vec2i{16, 16})
    testing.expect_value(t, drag_buffer, [4]TileID{5, 5, 5, 5})                            // the picked up tiles

    DragTiles(&tilemap, &dragged, {68, 20}, &drag_start, &selection, .HOLD, true, false, drag_buffer[:])
    testing.expect_value(t, dragged.position, vec2i{64, 16})                               // the preview follows the pointer

    DragTiles(&tilemap, &dragged, {68, 20}, &drag_start, &selection, .RELEASE, true, false, drag_buffer[:])
    testing.expect_value(t, TilemapGetTile(&tilemap, {1, 1}), TILE_EMPTY)                  // removed from where it was
    testing.expect_value(t, TilemapGetTile(&tilemap, {2, 2}), TILE_EMPTY)
    testing.expect_value(t, TilemapGetTile(&tilemap, {4, 1}), TileID(5))                   // and dropped at the new place
    testing.expect_value(t, TilemapGetTile(&tilemap, {5, 2}), TileID(5))
    testing.expect_value(t, selection.w, i32(0))                                           // the selection is used up
    testing.expect_value(t, dragged.size, vec2i{0, 0})
}

@(test)
test_drag_tiles_ignores_empty_selection :: proc(t: ^testing.T) {
    buffer: [24]TileID
    tilemap: Tilemap = make_edit_map(buffer[:])
    TilemapSetTile(&tilemap, {1, 1}, 5)
    drag_buffer: [4]TileID
    dragged: Tilemap
    drag_start: vec2i
    selection: recti

    DragTiles(&tilemap, &dragged, {20, 20}, &drag_start, &selection, .START, true, false, drag_buffer[:])
    testing.expect_value(t, dragged.size, vec2i{0, 0})

    outside: recti = {20, 20, 2, 2}                                                        // a selection that is not on the map
    DragTiles(&tilemap, &dragged, {20, 20}, &drag_start, &outside, .START, true, false, drag_buffer[:])
    testing.expect_value(t, dragged.size, vec2i{0, 0})
    testing.expect_value(t, TilemapGetTile(&tilemap, {1, 1}), TileID(5))
}


