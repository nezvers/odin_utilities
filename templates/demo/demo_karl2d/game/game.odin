package game

import "../../../karl2d"

window_width := 1280
window_height := 720
window_scale:f32 = 1
background_color: karl2d.Color = karl2d.BLACK

init :: proc() {
	karl2d.init(window_width, window_height, "Greetings from Karl2D!", options = { window_mode = .Windowed_Resizable})
	window_scale = karl2d.get_window_scale()
	when ODIN_OS != .JS {
		update_scale()
	}
    init_game_states()
    if state_list[state_index].init != nil { state_list[state_index].init() }
}

shutdown :: proc() {
    if state_list[state_index].finit != nil { state_list[state_index].finit() }
	karl2d.shutdown()
}

step :: proc() -> bool {
	if !karl2d.update() {
		return false
	}

	process_events()

	if state_list[state_index].update != nil { state_list[state_index].update() }

	draw()

	free_all(context.temp_allocator)
	return true
}

draw :: proc() {
		karl2d.clear(background_color)
		if state_list[state_index].draw != nil { state_list[state_index].draw() }
		if state_list[state_index].gui != nil { state_list[state_index].gui() }
		draw_state_menu()
		karl2d.present()
}

process_events :: proc() {
	events := karl2d.get_events()

	for event in events {
		#partial switch e in event {
		case karl2d.Event_Window_Scale_Changed:
			when ODIN_OS != .JS {
				window_scale = e.scale
				update_scale()
			}

		case karl2d.Event_Screen_Resize:
			window_scale = karl2d.get_window_scale()
			window_width = int(f32(e.width) / window_scale)
			window_height = int(f32(e.height) / window_scale)
		}
	}
}

// Get actual window size with scaling
get_window_size :: proc()->[2]f32 {
	return {(cast(f32)window_width * window_scale), (cast(f32)window_height * window_scale)}
}

get_local_mouse_position :: proc()->[2]f32 {
	return karl2d.get_mouse_position()
}

update_scale :: proc() {
	karl2d.set_screen_size(int(f32(window_width) * window_scale), int(f32(window_height) * window_scale))
}

// Called in main.odin inside for step() loop
update_desktop :: proc() {

}

