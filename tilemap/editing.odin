package tilemap

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
    map_start_position: ^vec2i, // TODO: not needed
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

        temp_tilemap_out.size = {0.0, 0.0}
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
        tile_difference:vec2i = drag_difference / tilemap.tile_size
        if (drag_difference.x < 0 ){
            tile_difference.x -= 1
        }
        if (drag_difference.y < 0 ){
            tile_difference.y -= 1
        }

        tilemap.position = map_start_position^ + tile_difference * tilemap.tile_size
    }
}

