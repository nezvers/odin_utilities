#+private file
package game

// import "core:fmt"
import tm "../.."
import "../../../karl2d"
import tm_glue "../../karl2d"

@(private="package")
tilemap_drag_state: GameState = {
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
	@(static) selection_state:vec2i
	@(static) drag_pos_state:vec2i
	@(static) rect_state:recti
	@(static) temp_tilemap:Tilemap = {}
	@(static) temp_buffer:[MAP_SIZE.x * MAP_SIZE.y]TileID

	input_selection:InputState = tm.GetInputState(
		karl2d.mouse_button_went_down(.Left), 
		karl2d.mouse_button_is_held(.Left),
		karl2d.mouse_button_went_up(.Left),
	)

	input_drag:InputState = tm.GetInputState(
		karl2d.mouse_button_went_down(.Right), 
		karl2d.mouse_button_is_held(.Right),
		karl2d.mouse_button_went_up(.Right),
	)

	if (rect_state.w == 0 || rect_state.h == 0){
		// no drag without selection
		input_drag = InputState.NONE
	}
	
	mouse_position:Vec2 = karl2d.get_mouse_position()
	mouse_position_i:vec2i = {cast(i32)mouse_position.x, cast(i32)mouse_position.y}
	

	if (input_drag != InputState.NONE){
		write_empty:bool = karl2d.key_is_held(.Left_Alt) || karl2d.key_is_held(.Right_Alt)
		remove_source:bool = karl2d.key_is_held(.Left_Control) || karl2d.key_is_held(.Right_Control)
		
		tm.DragTiles(
			&tilemap,
			&temp_tilemap,
			mouse_position_i,
			&drag_pos_state,
			&rect_state,
			input_drag,
			remove_source,
			write_empty,
			temp_buffer[:],
		)

		// Don't allow to change selection
		if (input_selection != InputState.NONE){
			input_selection = InputState.NONE
		}
	}

	if (input_selection != InputState.NONE && !is_hovering_buttons){
		tm.CreateSelection(&tilemap, mouse_position_i, &selection_state, &rect_state, input_selection)
	}

	tm_glue.DrawTilemapGrid(&tilemap, karl2d.LIGHT_GRAY)
	skip_zero:bool = true
	tm_glue.DrawTilemap(&tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)
	if(temp_tilemap.size.x != 0 && rect_state.w != 0){
		temp_rect:recti = tm.TilemapRecti(&temp_tilemap)
		tm_glue.DrawTilemapSelection(&temp_tilemap, temp_rect, karl2d.GRAY)
		tm_glue.DrawTilemap(&temp_tilemap, &tileset, &tile_atlas, skip_zero, tm.TileRandType.NONE, &tileset_texture)
	}

	tm_glue.DrawTilemapSelection(&tilemap, rect_state, karl2d.BLACK)

	karl2d.draw_text("left mouse select, right mouse drag,\n\thold CTRL to remove source, ALT to write empty tiles", {10, 10}, 20, karl2d.BLACK)
}