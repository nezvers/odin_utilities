package demo
// Based on Karl Zylinski's template - https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template

// import geometry2d ".."
import rl "vendor:raylib"
import "core:log"
import "core:os"
import "core:path/filepath"


USE_TRACKING_ALLOCATOR :: #config(USE_TRACKING_ALLOCATOR, false)

// DEMO STATES
State :: struct {
	enter : proc(),
	exit : proc(),
	update : proc(),
	draw : proc(),
}

state_list: []State = {
	state_draw_shapes,
}
StateIndex :: enum {
	DRAW_SHAPES,
}
state_index:StateIndex = StateIndex.DRAW_SHAPES

state_change :: proc(index:StateIndex){
	if state_list[state_index].exit != nil{
		state_list[state_index].exit()
	}
	state_index = index
	if state_list[state_index].enter != nil{
		state_list[state_index].enter()
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
	if state_list[state_index].enter != nil{
		state_list[state_index].enter()
	}
}

update :: proc() {
    if (rl.IsMouseButtonDown(rl.MouseButton.LEFT)){
		
	}
    if (rl.IsMouseButtonDown(rl.MouseButton.RIGHT)){

	}
	if state_list[state_index].update != nil{
		state_list[state_index].update()
	}
}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	if state_list[state_index].draw != nil{
		state_list[state_index].draw()
	}

    rl.EndDrawing()
}

draw_lines::proc(slice:[]rl.Vector2){
	LINE_COUNT:= len(slice)-1
	for i in 0..< LINE_COUNT {
		rl.DrawLineV(slice[i], slice[i+1], rl.WHITE)
	}
}


game_init_window :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "geometry demo")
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
	if state_list[state_index].exit != nil{
		state_list[state_index].exit()
	}
}
