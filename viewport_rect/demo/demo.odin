package demo

// import "core:fmt"
import rl "vendor:raylib"
import vp ".."

render_texture:rl.RenderTexture

view_rect: vp.Rect
projected_rect: vp.Rect
view_size: vp.Vector2i = {320, 180}
window_size: vp.Vector2i = {320, 180}

scaler:[6]proc(^vp.Rect, ^vp.Rect, vp.Vector2i, vp.Vector2i)
scale_index:u8 = 0

main :: proc() {
	game_init_window()
	game_init()

	main_loop: for game_should_run() {
		update()
		draw()
	}

	game_shutdown()
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


game_init :: proc() {
	scaler[0] = vp.ViewportKeepAspectPixel
	scaler[1] = vp.ViewportKeepHeightPixel
	scaler[2] = vp.ViewportKeepWidthPixel
	scaler[3] = vp.ViewportKeepAspect
	scaler[4] = vp.ViewportKeepHeight
	scaler[5] = vp.ViewportKeepWidth

	window_size.x = rl.GetScreenWidth()
	window_size.y = rl.GetScreenHeight()
	UpdateResolution()
}

update :: proc() {
	if rl.IsKeyPressed(rl.KeyboardKey.TAB){
		scale_index = (scale_index + 1) % 6
		UpdateResolution()
	}
	if rl.IsWindowResized(){
		window_size.x = rl.GetScreenWidth()
		window_size.y = rl.GetScreenHeight()
		UpdateResolution()
	}
}

UpdateResolution::proc(){
	// Call viewport rectangle calculation
	scaler[scale_index](&view_rect, &projected_rect, view_size, window_size)

	// Change resolution for RenderTexture
	rl.UnloadRenderTexture(render_texture)
	render_texture = rl.LoadRenderTexture(cast(i32)view_rect.w, cast(i32)view_rect.h)

	// RenderTexture needs to be flipped
	view_rect.h *= -1.0
}

draw :: proc() {
	rl.BeginTextureMode(render_texture)
	// Draw game's viewport
	draw_scene()
	rl.EndTextureMode()

	modes:[]cstring = {
        "Keep aspect (pixel) \nTAB to change",
        "Keep height (pixel) \nTAB to change",
        "Keep width (pixel) \nTAB to change",
        "Keep aspect \nTAB to change",
        "Keep height \nTAB to change",
        "Keep width \nTAB to change",
    }
	origin:rl.Vector2 = {0, 0}

	// Draw native resolution GUI
    rl.BeginDrawing()
	rl.ClearBackground(rl.LIGHTGRAY)
	rl.DrawTexturePro(render_texture.texture, transmute(rl.Rectangle)view_rect, transmute(rl.Rectangle)projected_rect, origin, 0.0, rl.WHITE)
    rl.DrawRectangleLinesEx(transmute(rl.Rectangle)view_rect, 1, rl.BLACK)

	rl.DrawText(modes[scale_index], 10, 10, 20, rl.BLACK)
	
	rl.EndDrawing()
}

draw_scene :: proc(){
	mouse_position:rl.Vector2 = rl.GetMousePosition()
	view_position:rl.Vector2 = screen2view(mouse_position)
	
	rl.ClearBackground(rl.WHITE)
	rl.DrawCircleV(view_position, 20.0, rl.LIME)
}

screen2view :: proc(point:rl.Vector2)->rl.Vector2 {
	relative_position:rl.Vector2 = {point.x - projected_rect.x, point.y - projected_rect.y}
	ratio:rl.Vector2 = {view_rect.w / projected_rect.w, -view_rect.h / projected_rect.h}
	result:rl.Vector2 = relative_position * ratio
	return result
}