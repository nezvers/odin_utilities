package demo_raylib

import "core:fmt"
import rl "vendor:raylib"
import common "../demo_common"

model: common.Model
screen_size: rl.Vector2

game_init :: proc() {
	screen_size = {cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}
	common.model_init(&model)
}

game_shutdown :: proc() {
}

update :: proc() {
	if rl.IsWindowResized() {
		screen_size = {cast(f32)rl.GetScreenWidth(), cast(f32)rl.GetScreenHeight()}
	}
	if rl.IsKeyPressed(.SPACE) { common.model_damage(&model, 15) }
	if rl.IsKeyPressed(.H) { common.model_heal(&model, 10) }
	if rl.IsKeyPressed(.R) { common.model_revive(&model) }
	if rl.IsKeyPressed(.ONE) { common.model_toggle_listener(&model, .HUD) }
	if rl.IsKeyPressed(.TWO) { common.model_toggle_listener(&model, .FLASH) }
	if rl.IsKeyPressed(.THREE) { common.model_toggle_listener(&model, .LOG) }
	if rl.IsKeyPressed(.B) { common.model_toggle_blocked(&model) }
	common.model_update(&model, rl.GetFrameTime())
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.RAYWHITE)

	// health bar, the red flash is a listener too
	bar: rl.Rectangle = {screen_size.x * 0.5 - 250, 120, 500, 40}
	rl.DrawRectangleRec(bar, rl.LIGHTGRAY)
	rl.DrawRectangleRec({bar.x, bar.y, bar.width * model.hud_value / common.HEALTH_MAX, bar.height}, rl.DARKGREEN)
	rl.DrawRectangleRec(bar, rl.Fade(rl.RED, model.flash * 0.7))
	rl.DrawRectangleLinesEx(bar, 2, rl.DARKGRAY)
	rl.DrawText(fmt.ctprintf("health %.0f%s", model.health, "   DOWN" if model.is_down else ""), i32(bar.x), i32(bar.y) - 30, 24, rl.BLACK)

	rl.DrawText("Space: damage    H: heal    R: revive    B: block the signal", 20, 20, 20, rl.DARKGRAY)
	listeners: [3]string = {"1  hud (the bar follows)", "2  flash (red on damage)", "3  log (deferred)"}
	for name, i in listeners {
		on: bool = common.model_is_listening(&model, common.Listener(i))
		rl.DrawText(fmt.ctprintf("%s  %s", name, "connected" if on else "disconnected"), 20, 60 + i32(i) * 26, 20, rl.DARKGREEN if on else rl.GRAY)
	}
	rl.DrawText(fmt.ctprintf("connections: %d   signal blocked: %v", common.model_connection_count(&model), common.model_is_blocked(&model)), 20, 150, 20, rl.DARKBLUE)

	rl.DrawText("log (deferred lines come after the frame, the one shot line comes first)", 20, 220, 20, rl.DARKGRAY)
	for i in 0 ..< common.LOG_LINES {
		rl.DrawText(fmt.ctprintf("%s", common.model_log_line(&model, i)), 40, 250 + i32(i) * 24, 20, rl.BLACK)
	}

	rl.EndDrawing()
	free_all(context.temp_allocator)
}
