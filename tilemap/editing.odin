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

CreateSelection :: proc(
    tilemap: ^Tilemap, 
    input_position:vec2i,
    selection_start_position: ^vec2i,
    selection_rect: ^recti,
    input_state:InputState,
){
    if input_state == InputState.START {
        selection_start_position^ = TilemapGetPositionWorld2Tile(tilemap, input_position)
    } else
    if (input_state == InputState.HOLD){
        drag_position: = TilemapGetPositionWorld2Tile(tilemap, input_position)
        selection_rect^ = TilemapGetVec2i2Recti(selection_start_position^, drag_position)
    }
}

DragTiles :: proc(
    tilemap: ^Tilemap,
    temp_tilemap_out: ^Tilemap,
    input_position:vec2i,
    drag_start_position: ^vec2i,
    map_start_position: ^vec2i,
    map_rect: ^recti,
    input_state: InputState,
    flags: Flags,
    temp_buffer: []TileID,
){
    if input_state == InputState.START {
        TilemapGetDataRecti(tilemap, map_rect^, temp_buffer)
        relative_distance:vec2i = input_position - tilemap.position
        rounded_distance:vec2i = tilemap.tile_size.x * tilemap.tile_size.y / relative_distance
        
        map_start_position.x = tilemap.position.x + map_rect.x * tilemap.tile_size.x
        map_start_position.y = tilemap.position.y + map_rect.y * tilemap.tile_size.y
        map_size:vec2i = {map_rect.w, map_rect.h}
        temp_tilemap_out^ = TilemapInit(map_start_position^, map_size, tilemap.tile_size, temp_buffer, cast(u32)len(temp_buffer))
        TilemapSetData(temp_tilemap_out, temp_buffer, cast(u32)map_size.x, cast(u32)map_size.y)
        // Alternatively - TilemapSetDataRecti

        // TODO: refactor to remove need for this variable
        drag_start_position^ = tilemap.position + rounded_distance
    } else if (input_state == InputState.HOLD){
        // Offset from start position
        drag_distance:vec2i = input_position - drag_start_position^
        tile_distance:vec2i = drag_distance / tilemap.tile_size

        if drag_distance.x < 0 {
            tile_distance.x -= 1
        }
        if drag_distance.y < 0 {
            tile_distance.y -= 1
        }

        temp_tilemap_out.position = map_start_position^ + tile_distance * tilemap.tile_size
    } else if (input_state == InputState.RELEASE){
        // Place tile data
        drag_distance:vec2i = temp_tilemap_out.position - map_start_position^
        tile_distance:vec2i = drag_distance / tilemap.tile_size
        temp_tilemap_out.position = map_start_position^ + tile_distance * tilemap.tile_size

        map_difference:vec2i = temp_tilemap_out.position - tilemap.position

        if cast(i32)(flags & Flags.CLEAR_SOURCE) != 0 {
            TilemapSetTileIdBlock(tilemap, map_rect.x, map_rect.y, map_rect.w, map_rect.h, TILE_EMPTY)
        }

        data_rect:recti = {
            map_difference.x / tilemap.tile_size.x,
            map_difference.y / tilemap.tile_size.y,
            map_rect.w,
            map_rect.h,
        }
        write_empty:bool = cast(i32)(flags & Flags.WRITE_EMPTY) != 0
        TilemapSetDataRecti(tilemap, data_rect, temp_buffer, write_empty)

        temp_tilemap_out.size = {0.0, 0.0}
        map_rect.w = 0.0
        map_rect.h = 0.0
    }
}


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

PaintTiles :: proc(
    tilemap: ^Tilemap,
    input_position:vec2i,
    state_position: ^vec2i,
    tile_id_state: ^TileID,
    input_state: InputState,
){
    if (tile_id_state^ == TILE_INVALID){
        return
    }

    if (input_state == InputState.START){
        state_position^ = TilemapGetPositionWorld2Tile(tilemap, input_position)
        tile_id:TileID = TilemapGetTile(tilemap, state_position^)
        if (tile_id == TILE_INVALID){
            return
        }
        TilemapSetTile(tilemap, state_position^, tile_id_state^)
    } else if (input_state == InputState.HOLD){
        new_position:vec2i = TilemapGetPositionWorld2Tile(tilemap, input_position)
        if (new_position == state_position^){
            return
        }
        state_position^ = new_position
        tile_id:TileID = TilemapGetTile(tilemap, state_position^)
        if (tile_id == TILE_INVALID){
            return
        }
        TilemapSetTile(tilemap, state_position^, tile_id_state^)
    }
}

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

