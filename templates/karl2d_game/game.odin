package game

import karl2d "../karl2d"
Rect :: karl2d.Rect
Vec2 :: karl2d.Vec2

import viewport "../viewport_rect"

window_width:int = 1280
window_height:int = 720
game_width:int = 480
game_height:int = 270
window_scale:f32 = 1
background_color: karl2d.Color = karl2d.BLACK
view_rect: Rect
projected_rect: Rect
game_texture: karl2d.Render_Texture
use_game_texture :bool: #config(GAME_TEXTURE, true)

init :: proc() {
	karl2d.init(window_width, window_height, "Greetings from Karl2D!", options = { window_mode = .Windowed_Resizable})
	window_scale = karl2d.get_window_scale()
	when ODIN_OS != .JS && use_game_texture  {
		update_scale()
	}
	update_game_center()

    
	current_state = screen_title_state
    if current_state.init != nil { current_state.init() }
}

shutdown :: proc() {
    if current_state.finit != nil { current_state.finit() }
	karl2d.destroy_render_texture(game_texture)
	karl2d.shutdown()
}

step :: proc() -> bool {
	if !karl2d.update() {
		return false
	}

	process_events()

	if current_state.update != nil { current_state.update() }

	draw()

	free_all(context.temp_allocator)
	return true
}

draw :: proc() {
	if use_game_texture {
		karl2d.set_render_texture(game_texture)
		if current_state.draw != nil { current_state.draw() }
		karl2d.set_render_texture(nil)
		
		karl2d.clear(background_color)
		// karl2d.draw_texture(game_texture.texture, {view_rect.x, view_rect.y})
		karl2d.draw_texture_fit(game_texture.texture, view_rect, projected_rect)
		if current_state.gui != nil { current_state.gui() }
		karl2d.present()
	} else {
		karl2d.clear(background_color)
		if current_state.draw != nil { current_state.draw() }
		if current_state.gui != nil { current_state.gui() }
		karl2d.present()
	}
}

process_events :: proc() {
	events := karl2d.get_events()

	for event in events {
		#partial switch e in event {
		case karl2d.Event_Window_Scale_Changed:
			when ODIN_OS != .JS && use_game_texture  {
				window_scale = e.scale
				update_scale()
			}

		case karl2d.Event_Screen_Resize:
			window_scale = karl2d.get_window_scale()
			window_width = int(f32(e.width) / window_scale)
			window_height = int(f32(e.height) / window_scale)
			update_game_center()
		}
	}
}

// Get actual window size with scaling
get_window_size :: proc()->[2]f32 {
	return {(cast(f32)window_width * window_scale), (cast(f32)window_height * window_scale)}
}

get_local_mouse_position :: proc()->[2]f32 {
	mouse_pos: = karl2d.get_mouse_position()
	return {mouse_pos.x - view_rect.x, mouse_pos.y - view_rect.y}
}

update_scale :: proc() {
	karl2d.set_screen_size(int(f32(window_width) * window_scale), int(f32(window_height) * window_scale))
}

update_game_center :: proc() {
	window_size: = get_window_size()
	// view_rect.x = (window_size.x - view_rect.w) * 0.5
	// view_rect.y = (window_size.y - view_rect.h) * 0.5
	viewport.ViewportKeepHeightPixel(
		cast(^viewport.Rect)&view_rect, 
		cast(^viewport.Rect)&projected_rect, 
		{cast(i32)game_width, cast(i32)game_height}, 
		{cast(i32)window_size.x, cast(i32)window_size.y},
	)

	karl2d.destroy_render_texture(game_texture)
	game_texture = karl2d.create_render_texture(cast(int)view_rect.w, cast(int)view_rect.h)
}

// Called in main.odin inside for step() loop
update_desktop :: proc() {

}

