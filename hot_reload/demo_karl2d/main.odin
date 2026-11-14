package main

import "core:fmt"
import "core:os"
import "../../karl2d"
import hot_reload ".."
import api "../demo_game/api"

DLL_DIRECTORY :: "hot_reload_demo"
DLL_PATH :: DLL_DIRECTORY + "/game.dll"

BUTTON_RECT :: karl2d.Rect{10, 40, 150, 30}

// Procs the game DLL draws with, the DLL never touches karl2d itself
host: api.Host = {
	draw_rect = proc(rect: api.Rect, color: api.Color) {
		karl2d.draw_rect({rect.x, rect.y, rect.z, rect.w}, color)
	},
	draw_text = proc(text: string, position: api.Vec2, size: f32, color: api.Color) {
		karl2d.draw_text(text, position, size, color)
	},
	frame_time = proc() -> f32 {
		return karl2d.get_frame_time()
	},
	screen_size = proc() -> api.Vec2 {
		return {f32(karl2d.get_screen_width()), f32(karl2d.get_screen_height())}
	},
}

reload_state: hot_reload.HotReload
loaded_buffer: [64]hot_reload.Api

main :: proc() {
	// To be sure resources/ assets are always relative directory,
	// set working directory where executable is.
	working_dir, err: = os.get_working_directory(context.allocator)
	defer delete(working_dir)
	// Return user to original directory in case project change it
	defer os.change_directory(working_dir)
	if err != nil {
		return
	}
	executable_directory: string
	executable_directory, err = os.get_executable_directory(context.allocator)
	defer delete(executable_directory)
	if err != nil {
		return
	}
	os.change_directory(executable_directory)

	os.make_directory_all(DLL_DIRECTORY)
	if !os.exists(DLL_PATH) && !api.BuildGameDll(DLL_PATH) {
		return
	}
	config: hot_reload.HotReloadConfig = {
		dll_path = DLL_PATH,
		copy_directory = DLL_DIRECTORY + "/copies",
		host = &host,
		allocator = context.allocator,
	}
	if !hot_reload.HotReloadInit(&reload_state, config, loaded_buffer[:]) {
		return
	}
	defer hot_reload.HotReloadShutdown(&reload_state)

	karl2d.init(1280, 720, "hot reload demo", options = {window_mode = .Windowed_Resizable})
	defer karl2d.shutdown()

	for karl2d.update() {
		karl2d.clear(karl2d.WHITE)

		running: bool = hot_reload.HotReloadUpdate(&reload_state)

		// The button is the trigger: rebuild the DLL, then ask for the reload
		mouse: karl2d.Vec2 = karl2d.get_mouse_position()
		hovering: bool = mouse.x >= BUTTON_RECT.x && mouse.x <= BUTTON_RECT.x + BUTTON_RECT.w && mouse.y >= BUTTON_RECT.y && mouse.y <= BUTTON_RECT.y + BUTTON_RECT.h
		karl2d.draw_rect(BUTTON_RECT, karl2d.LIGHT_GRAY if !hovering else karl2d.GRAY)
		karl2d.draw_text("Reload", {BUTTON_RECT.x + 8, BUTTON_RECT.y + 4}, 22, karl2d.BLACK)
		if hovering && karl2d.mouse_button_went_down(.Left) {
			if api.BuildGameDll(DLL_PATH) {
				hot_reload.HotReloadRequest(&reload_state)
			}
		}
		karl2d.draw_text(fmt.tprintf("reloads: %d  last: %s", reload_state.reload_count, reload_name()), {10, 80}, 20, karl2d.DARK_GRAY)
		karl2d.draw_text("edit demo_game/game.odin, then press Reload", {10, 110}, 20, karl2d.GRAY)

		karl2d.present()
		free_all(context.temp_allocator)
		if !running {
			break
		}
	}
}

reload_name :: proc() -> string {
	switch reload_state.last_result {
	case .NONE: return "-"
	case .KEPT: return "memory kept"
	case .REBUILT: return "memory rebuilt"
	case .FAILED: return "failed, old code still runs"
	}
	return ""
}
