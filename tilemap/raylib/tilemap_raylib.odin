package tilemap_raylib

import rl "vendor:raylib"
import tm ".."

vec2i :: tm.vec2i
recti :: tm.recti
TileID :: tm.TileID
Tile :: tm.Tile
Tileset :: tm.Tileset
Tilemap :: tm.Tilemap
TILE_EMPTY :: tm.TILE_EMPTY
TILE_INVALID :: tm.TILE_INVALID

Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle
Color :: rl.Color
Font :: rl.Font

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

/* ============= DRAWING ===================== */

DrawTilemapGrid :: proc(tilemap: ^Tilemap, color:Color){
    map_width:int = tilemap.size.x * tilemap.tile_size.x
    map_height:int = tilemap.size.y * tilemap.tile_size.y

    // Vertical lines
    for x in 0..< tilemap.size.x + 1 {
        cell_x:int = tilemap.position.x + x + tilemap.tile_size.x
        rl.DrawLine(cast(i32)cell_x, cast(i32)tilemap.position.y, cast(i32)(cell_x + 1), cast(i32)(tilemap.position.y + map_height), color)
    }

    // Horizontal lines
    for _ in 0..< tilemap.size.y + 1 {
        cell_y:int = tilemap.position.y * tilemap.tile_size.y
        rl.DrawLine(cast(i32)tilemap.position.x, cast(i32)cell_y, cast(i32)(tilemap.position.x + map_width), cast(i32)cell_y, color)
    }
}

DrawTilemapTileId :: proc(tilemap: ^Tilemap, font:Font, font_size:int, color:Color){
    text_offset_y:int = (tilemap.tile_size.y - font_size) / 2
    for y:int = 0; y < tilemap.size.y; y += 1 {
        cell_y:int = tilemap.position.y + y * tilemap.tile_size.y
        for x:int; x < tilemap.size.x; x += 1{
            cell_x:int = tilemap.position.x + x * tilemap.tile_size.x
            cell_i:int = x + y * tilemap.size.x
            cell_id:tm.TileID = tilemap.grid[cell_i]
            if cell_id == 0 {
                continue // skip EMPTY
            }
            text:cstring = rl.TextFormat("%d", cell_id)
            text_measure:Vector2 = rl.MeasureTextEx(font, text, cast(f32)font_size, 0.0)
            text_offset_x:int = (tilemap.tile_size.x - cast(int)text_measure.x) / 2
            text_position:Vector2 = {cast(f32)(cell_x + text_offset_x), cast(f32)(cell_y + text_offset_y + 1)}
            rl.DrawTextEx(font, text, text_position, cast(f32)font_size, 0.0, color)
        }
    }
}

DrawTilemapCellRect :: proc(tilemap: ^Tilemap, world_pos:vec2i, tile_id:TileID, font:Font, font_size:int, color:Color)->TileID{
    tile_pos:vec2i = tm.TilemapGetPositionWorld2Tile(tilemap, world_pos)
    tile_x:int = tilemap.position.x + tile_pos.x * tilemap.tile_size.x
    tile_y:int = tilemap.position.y + tile_pos.y * tilemap.tile_size.y
    rl.DrawRectangleLines(cast(i32)tile_x, cast(i32)tile_y, cast(i32)tilemap.tile_size.x, cast(i32)tilemap.tile_size.y, color)

    text:cstring = rl.TextFormat("%d", tile_id)
    text_measure:Vector2 = rl.MeasureTextEx(font, text, cast(f32)font_size, 0.0)
    text_offset_x:int = (tilemap.tile_size.x - cast(int)text_measure.x) / 2
    text_offset_y:int = (tilemap.tile_size.y - font_size) / 2
    text_position:Vector2 = {cast(f32)(tile_x + text_offset_x), cast(f32)(tile_y + text_offset_y)}
    rl.DrawTextEx(font, text, text_position, cast(f32)font_size, 0.0, color)
    // TODO: is it needed, I forgot
    return tile_id
}

DrawTilemapSelection :: proc(tilemap: ^Tilemap, rect:recti, color:Color){
    rectangle:Rectangle = {
        cast(f32)(tilemap.position.x + rect.x * tilemap.tile_size.x),
        cast(f32)(tilemap.position.y + rect.y * tilemap.tile_size.y),
        cast(f32)(rect.w * tilemap.tile_size.x),
        cast(f32)(rect.h * tilemap.tile_size.y),
    }
    rl.DrawRectangleLinesEx(rectangle, 1.0, color)
}

/* ================= EDITING =================== */

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
        selection_start_position^ = tm.TilemapGetPositionWorld2Tile(tilemap, input_position)
    } else
    if (input_state == InputState.HOLD){
        drag_position: = tm.TilemapGetPositionWorld2Tile(tilemap, input_position)
        selection_rect^ = tm.TilemapGetVec2i2Recti(selection_start_position^, drag_position)
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
    flags: tm.Flags,
    temp_buffer: []TileID,
){
    if input_state == InputState.START {
        tm.TilemapGetDataRecti(tilemap, map_rect^, temp_buffer)
        relative_distance:vec2i = input_position - tilemap.position
        rounded_distance:vec2i = tilemap.tile_size.x * tilemap.tile_size.y / relative_distance
        
        map_start_position.x = tilemap.position.x + map_rect.x * tilemap.tile_size.x
        map_start_position.y = tilemap.position.y + map_rect.y * tilemap.tile_size.y
        map_size:vec2i = {map_rect.w, map_rect.h}
        temp_tilemap_out^ = tm.TilemapInit(map_start_position^, map_size, tilemap.tile_size, temp_buffer, cast(u32)len(temp_buffer))
        tm.TilemapSetData(temp_tilemap_out, temp_buffer, cast(u32)map_size.x, cast(u32)map_size.y)
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

        if cast(i32)(flags & tm.Flags.TILEMAP_FLAGS_CLEAR_SOURCE) != 0 {
            tm.TilemapSetTileIdBlock(tilemap, map_rect.x, map_rect.y, map_rect.w, map_rect.h, TILE_EMPTY)
        }

        data_rect:recti = {
            map_difference.x / tilemap.tile_size.x,
            map_difference.y / tilemap.tile_size.y,
            map_rect.w,
            map_rect.h,
        }
        write_empty:bool = cast(i32)(flags & tm.Flags.TILEMAP_FLAGS_WRITE_EMPTY) != 0
        tm.TilemapSetDataRecti(tilemap, data_rect, temp_buffer, write_empty)

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

    tile_id:TileID = tm.TilemapGetTileWorld(tilemap, input_position)
    if (tile_id == TILE_INVALID){
        return
    }

    if (input_type == InputType.INCREASE && (tile_id + 1) != TILE_INVALID){
        tile_id_state^ = tile_id + 1
    } else if (input_type == InputType.DECREASE && (tile_id - 1) != TILE_INVALID){
        tile_id_state^ = tile_id - 1
    }

    tm.TilemapSetTileWorld(tilemap, input_position, tile_id_state^)
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
        state_position^ = tm.TilemapGetPositionWorld2Tile(tilemap, input_position)
        tile_id:TileID = tm.TilemapGetTile(tilemap, state_position^)
        if (tile_id == TILE_INVALID){
            return
        }
        tm.TilemapSetTile(tilemap, state_position^, tile_id_state^)
    } else if (input_state == InputState.HOLD){
        new_position:vec2i = tm.TilemapGetPositionWorld2Tile(tilemap, input_position)
        if (new_position == state_position^){
            return
        }
        state_position^ = new_position
        tile_id:TileID = tm.TilemapGetTile(tilemap, state_position^)
        if (tile_id == TILE_INVALID){
            return
        }
        tm.TilemapSetTile(tilemap, state_position^, tile_id_state^)
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

