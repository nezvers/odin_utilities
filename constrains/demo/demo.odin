package demo
// Based on Karl Zylinski's template - https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template

import constrains ".."
import rl "vendor:raylib"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"


USE_TRACKING_ALLOCATOR :: #config(USE_TRACKING_ALLOCATOR, false)

point_list:[6]rl.Vector2 = {
	{0.0, 0.0},
	{10.0, 5.0},
	{15.0, 0.0},
	{17.0, 10.0},
	{25.0, 15.0},
	{35.0, 5.0},
}

// gets initialized in game_init()
total_length:f32
length_buffer:[5]f32
start_fabrik:rl.Vector2
end_fabrik:rl.Vector2


main :: proc() {
	// Set working dir to dir of executable.
	exe_path := os.args[0]
	exe_dir := filepath.dir(string(exe_path), context.temp_allocator)
	os.set_current_directory(exe_dir)
	
	when USE_TRACKING_ALLOCATOR {
		default_allocator := context.allocator
		tracking_allocator: Tracking_Allocator
		tracking_allocator_init(&tracking_allocator, default_allocator)
		context.allocator = allocator_from_tracking_allocator(&tracking_allocator)
	}

	mode: int = 0
	when ODIN_OS == .Linux || ODIN_OS == .Darwin {
		mode = os.S_IRUSR | os.S_IWUSR | os.S_IRGRP | os.S_IROTH
	}

	logh, logh_err := os.open("log.txt", (os.O_CREATE | os.O_TRUNC | os.O_RDWR), mode)

	if logh_err == os.ERROR_NONE {
		os.stdout = logh
		os.stderr = logh
	}

	logger := logh_err == os.ERROR_NONE ? log.create_file_logger(logh) : log.create_console_logger()
	context.logger = logger

	game_init_window()
	game_init()

	for game_should_run() {
		update()
        draw()

		when USE_TRACKING_ALLOCATOR {
			for b in tracking_allocator.bad_free_array {
				log.error("Bad free at: %v", b.location)
			}

			clear(&tracking_allocator.bad_free_array)
		}

		free_all(context.temp_allocator)
	}

	free_all(context.temp_allocator)
	game_shutdown()
	rl.CloseWindow()
    
	if logh_err == os.ERROR_NONE {
        log.destroy_file_logger(logger)
	}
    
	when USE_TRACKING_ALLOCATOR {
        for key, value in tracking_allocator.allocation_map {
            log.error("%v: Leaked %v bytes\n", value.location, value.size)
		}
        
		tracking_allocator_destroy(&tracking_allocator)
	}
}


game_init :: proc() {
    total_length = constrains.calculate_lengths(point_list[:], length_buffer[:])
    start_fabrik = point_list[len(point_list)-1]
    end_fabrik = point_list[0]
}

update :: proc() {
    if (rl.IsMouseButtonPressed(rl.MouseButton.LEFT)){
		constrains.fabrik(point_list[:], length_buffer[:], rl.GetMousePosition(), 4, 0.01)
		//constrains.pull_front(point_list[:], length_buffer[:], rl.GetMousePosition())
		return
	}
    if (rl.IsMouseButtonDown(rl.MouseButton.RIGHT)){
		constrains.pull_back(point_list[:], length_buffer[:], rl.GetMousePosition())
		return
	}
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

    draw_lines(point_list[:])

    rl.EndDrawing()
}

draw_lines::proc(slice:[]rl.Vector2){
	for i in 0..<(len(slice)-1){
		rl.DrawLineV(slice[i], slice[i+1], rl.WHITE)
	}
}


game_init_window :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "constrains demo")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(500)
	rl.SetExitKey(nil)
}


game_should_run :: proc() -> bool {
    when ODIN_OS != .JS {
        // Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
            return false
		}
	}
    
	return !rl.IsKeyPressed(.ESCAPE)
}


game_shutdown :: proc() {
    
}
