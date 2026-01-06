package demo

// import "core:fmt"
import rl "vendor:raylib"

main :: proc() {
	game_init_window()
	game_init()

	main_loop: for game_should_run() {
		update()
		draw()
	}

	game_shutdown()
}


game_init :: proc() {

}

update :: proc() {

}

draw :: proc() {
    rl.BeginDrawing()
	rl.ClearBackground(rl.WHITE)


    rl.EndDrawing()
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

game_shutdown :: proc() {
    rl.CloseWindow()
}
