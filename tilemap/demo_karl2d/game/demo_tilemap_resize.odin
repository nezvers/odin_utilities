#+private file
package game

import "core:fmt"
import tm "../.."
import "../../../karl2d"
import tm_glue "../../karl2d"

@(private="package")
tilemap_resize_state: GameState = {
    init,
    finit,
    process,
    draw,
}

init :: proc() {}

finit :: proc() {}

process :: proc() {}

draw :: proc() {
    karl2d.clear(karl2d.WHITE)
	
    // Persistent variables to hold state
	@(static) rect_state:recti
	@(static) selection_state:vec2i
	@(static) temp_buffer:[MAP_SIZE.x * MAP_SIZE.y]TileID

	size_error:bool

	input_selection:InputState = tm.GetInputState(
		karl2d.mouse_button_went_down(.Left), 
		karl2d.mouse_button_is_held(.Left),
		karl2d.mouse_button_went_up(.Left),
	)

	if (is_hovering_buttons){
		input_selection = InputState.NONE
		rect_state.w = 0
		rect_state.h = 0
	}

	mouse_position:Vec2 = karl2d.get_mouse_position()
	mouse_position_i:vec2i = {cast(i32)mouse_position.x, cast(i32)mouse_position.y}

	if (input_selection != InputState.NONE){
		tm.CreateSelection(&tilemap, mouse_position_i, &selection_state, &rect_state, input_selection)
	}

	rect_area:i32 = rect_state.w * rect_state.h
	size_error = rect_area > cast(i32)len(tilemap.grid)

	if (input_selection == InputState.RELEASE){
		if (!size_error && rect_area > 0){
			tm.TilemapResize(&tilemap, rect_state, temp_buffer[:])
		}
		rect_state.w = 0
		rect_state.h = 0
	}

	tm_glue.DrawTilemapGrid(&tilemap, karl2d.LIGHT_GRAY)
	skip_zero:bool = true
	tm_glue.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)

	tm_glue.DrawTilemapSelection(&tilemap, rect_state, karl2d.BLACK)

	karl2d.draw_text("left mouse select, release to resize", {10, 10}, 20, karl2d.BLACK)
	if size_error {
		text:string = fmt.tprintf("ERROR: tilemap grid buffer overflow (%v > %v)", rect_area, len(tilemap.grid))
		karl2d.draw_text(text, {10, 30}, 20, karl2d.RED)
	}
}