package demo

// import "core:fmt"
import rl "vendor:raylib"
import tilemap ".."

tilemap_buffer: [20 * 20]tilemap.TileID
tilemap:tilemap.Tilemap

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
	new_tilemap: = tilemap.TilemapInit({}, {20,20}, {16,16}, tilemap_buffer[:], len(tilemap_buffer))
	tilemap.TilemapClear(&new_tilemap)
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
