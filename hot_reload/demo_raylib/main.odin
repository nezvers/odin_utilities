package demo_raylib

import "core:os"
import "core:strings"
import rl "vendor:raylib"
import hot_reload ".."
import api "../demo_game/api"

DLL_DIRECTORY :: "hot_reload_demo"
DLL_PATH :: DLL_DIRECTORY + "/game.dll"

BUTTON_RECT :: rl.Rectangle{10, 40, 150, 30}

// Procs the game DLL draws with, the DLL never touches raylib itself
host: api.Host = {
	draw_rect = proc(rect: api.Rect, color: api.Color) {
		rl.DrawRectangleRec(transmute(rl.Rectangle)rect, rl.Color(color))
	},
	draw_text = proc(text: string, position: api.Vec2, size: f32, color: api.Color) {
		rl.DrawText(strings.clone_to_cstring(text, context.temp_allocator), i32(position.x), i32(position.y), i32(size), rl.Color(color))
	},
	frame_time = proc() -> f32 {
		return rl.GetFrameTime()
	},
	screen_size = proc() -> api.Vec2 {
		return {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	},
}

reload_state: hot_reload.HotReload
loaded_buffer: [64]hot_reload.Api

main :: proc() {
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

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "hot reload demo")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(rl.WHITE)

		running: bool = hot_reload.HotReloadUpdate(&reload_state)

		// The button is the trigger: rebuild the DLL, then ask for the reload
		if rl.GuiButton(BUTTON_RECT, "Reload") {
			if api.BuildGameDll(DLL_PATH) {
				hot_reload.HotReloadRequest(&reload_state)
			}
		}
		status: cstring = rl.TextFormat("reloads: %d  last: %s", i32(reload_state.reload_count), strings.clone_to_cstring(reload_name(), context.temp_allocator))
		rl.DrawText(status, 10, 80, 20, rl.DARKGRAY)
		rl.DrawText("edit demo_game/game.odin, then press Reload", 10, 110, 20, rl.GRAY)

		rl.EndDrawing()
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
