package demo

import rl "vendor:raylib"
import "core:os/os2"

// DEMO STATES
State :: struct {
	enter : proc(),
	exit : proc(),
	update : proc(),
	draw : proc(),
}

state_change :: proc(index:Example){
	if state_list[current_example].exit != nil{
		state_list[current_example].exit()
	}
	current_example = index
	if state_list[current_example].enter != nil{
		state_list[current_example].enter()
	}
}

main :: proc() {
	working_dir, err: = os2.get_working_directory(context.allocator)
	defer delete(working_dir)
	// Return user to original directory in case project change it
	defer os2.change_directory(working_dir)
	if err != nil {
		return
	}
	executable_directory:string
	executable_directory, err = os2.get_executable_directory(context.allocator)
	defer delete(executable_directory)
	if err != nil {
		return
	}
	os2.change_directory(executable_directory)

	game_init_window()
	game_init()

	main_loop: for game_should_run() {
		update()
		draw()
	}

	game_shutdown()
    rl.CloseWindow()
}

game_init_window :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "template demo")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(60)
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