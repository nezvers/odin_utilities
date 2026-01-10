package tilemap_raylib

import rl "vendor:raylib"
import tm ".."

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

DrawTilemapGrid :: proc(tilemap: ^tm.Tilemap, color:rl.Color){
    map_width:int = tilemap.size.x * tilemap.tile_size.x
    map_height:int = tilemap.size.y * tilemap.tile_size.y

    // Vertical lines
    for x in 0..< tilemap.size.x + 1 {
        cell_x:int = tilemap.position.x + x + tilemap.tile_size.x
        rl.DrawLine(cast(i32)cell_x, cast(i32)tilemap.position.y, cast(i32)(cell_x + 1), cast(i32)tilemap.position.y + map_height, color)
    }

    // Horizontal lines
    for y in 0..< tilemap.size.y + 1 {
        cell_y:int = tilemap.position.y * tilemap.tile_size.y
        rl.DrawLine(cast(i32)tilemap.position.x, cast(i32)cell_y, cast(i32)(tilemap.position.x + map_width), cast(i32)cell_y, color)
    }
}

DrawTilemapTileId :: proc(tilemap: ^tm.Tilemap, font:rl.Font, font_size:i32, color:rl.Color){
    text_offset_y:i32 = (cast(i32)tilemap.tile_size.y - font_size) / 2
    for y:i32 = 0; y < cast(i32)tilemap.size.y; y += 1 {
        cell_y:i32 = cast(i32)tilemap.position.y + y * cast(i32)tilemap.tile_size.y
        for x:i32; x < cast(i32)tilemap.size.x; x += 1{
            cell_x:i32 = cast(i32)tilemap.position.x + x * cast(i32)tilemap.tile_size.x
            cell_i:i32 = x + y * cast(i32)tilemap.size.x
            cell_id:tm.TileID = tilemap.grid[cell_i]
            if cell_id == 0 {
                continue // skip EMPTY
            }
            text:cstring = rl.TextFormat("%d", cast(i32)cell_id)
            text_measure:rl.Vector2 = rl.MeasureTextEx(font, text, cast(f32)font_size, 0.0)
            text_offset_x:i32 = (cast(i32)tilemap.tile_size.x - cast(i32)text_measure.x) / 2
            text_position:rl.Vector2 = {cast(f32)(cell_x + text_offset_x), cast(f32)(cell_y + text_offset_y + 1)}
            rl.DrawTextEx(font, text, text_position, cast(f32)font_size, 0.0, color)
        }
    }
}