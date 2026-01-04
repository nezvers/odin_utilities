package demo
// Based on Karl Zylinski's template - https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template

import rl "vendor:raylib"
import "core:log"
import "core:os"
import "core:path/filepath"

import spring ".."


USE_TRACKING_ALLOCATOR :: #config(USE_TRACKING_ALLOCATOR, false)

spring_params:spring.SpringParams = {}
spring_cache:[4 * 60]f32
spring_min:f32
spring_max:f32

calculate_spring::proc(){
	position:f32 = 0.0
	target:f32 = 1.0
	spring_min = 0.0
	spring_max = 1.0

	for i in 0..<len(spring_cache){
		spring_cache[i] = position
		if (position < spring_min) {
			spring_min = position
		} else
		if (position > spring_max) {
			spring_max = position
		}
		position = spring.Spring(&spring_params, 0.016, position, target)
	}
}

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
	spring_params.k = 37.24
	spring_params.m = 0.3
	spring_params.zeta = 1.7
	spring_params.omega = 6.0
	spring_params.category = spring.SpringCategory.UnderdampedStable
	calculate_spring()
}

update :: proc() {
    if (rl.IsMouseButtonDown(rl.MouseButton.LEFT)){
		
	}
    if (rl.IsMouseButtonDown(rl.MouseButton.RIGHT)){

	}
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)



	x:i32 = 10
	y:i32 = 400
	scale:f32 = -100.0
	
	rl.DrawLine(x, y, x + 60 * 4, y, rl.DARKGRAY)
	rl.DrawLine(x, y + i32(scale), x + 60 * 4, y + i32(scale), rl.GRAY)

	for i in 0..< (len(spring_cache) - 1) {
		y1:i32 = i32(spring_cache[i] * scale) + y
		y2:i32 = i32(spring_cache[i + 1] * scale) + y
		x1:i32 = x + i32(i)
		x2:i32 = x1 + 1
		rl.DrawLine(x1, y1, x2, y2, rl.WHITE)
	}

    rl.EndDrawing()
}

game_init_window :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "template demo")
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
