package game

import "core:fmt"
import "../../../karl2d"
import common "../../demo_common"

model: common.Model

init :: proc() {
	karl2d.init(1280, 720, "signal demo", options = {window_mode = .Windowed_Resizable})
	common.model_init(&model)
}

shutdown :: proc() {
	karl2d.shutdown()
}

step :: proc() -> bool {
	if !karl2d.update() { return false }

	if karl2d.key_went_down(.Space) { common.model_damage(&model, 15) }
	if karl2d.key_went_down(.H) { common.model_heal(&model, 10) }
	if karl2d.key_went_down(.R) { common.model_revive(&model) }
	if karl2d.key_went_down(.N1) { common.model_toggle_listener(&model, .HUD) }
	if karl2d.key_went_down(.N2) { common.model_toggle_listener(&model, .FLASH) }
	if karl2d.key_went_down(.N3) { common.model_toggle_listener(&model, .LOG) }
	if karl2d.key_went_down(.B) { common.model_toggle_blocked(&model) }
	if karl2d.key_went_down(.F) { common.model_rebind(&model) }
	common.model_update(&model, karl2d.get_frame_time())

	draw()
	free_all(context.temp_allocator)
	return true
}

draw :: proc() {
	karl2d.clear(karl2d.RL_RAYWHITE)
	screen_width: f32 = f32(karl2d.get_screen_width())

	// health bar, the red flash is a listener too
	bar: karl2d.Rect = {screen_width * 0.5 - 250, 120, 500, 40}
	karl2d.draw_rect(bar, karl2d.LIGHT_GRAY)
	karl2d.draw_rect({bar.x, bar.y, bar.w * model.hud_value / common.HEALTH_MAX, bar.h}, karl2d.DARK_GREEN)
	flash: karl2d.Color = karl2d.RED
	flash.a = u8(model.flash * 0.7 * 255)
	karl2d.draw_rect(bar, flash)
	karl2d.draw_rect_outline(bar, 2, karl2d.DARK_GRAY)
	karl2d.draw_text(fmt.tprintf("health %.0f%s", model.health, "   DOWN" if model.is_down else ""), {bar.x, bar.y - 30}, 24, karl2d.BLACK)

	karl2d.draw_text("Space: damage    H: heal    R: revive    B: block the signal    F: rebind like after a hot reload", {20, 20}, 20, karl2d.DARK_GRAY)
	listeners: [3]string = {"1  hud (the bar follows)", "2  flash (red on damage)", "3  log (deferred)"}
	for name, i in listeners {
		on: bool = common.model_is_listening(&model, common.Listener(i))
		karl2d.draw_text(fmt.tprintf("%s  %s", name, "connected" if on else "disconnected"), {20, 60 + f32(i) * 26}, 20, karl2d.DARK_GREEN if on else karl2d.GRAY)
	}
	karl2d.draw_text(fmt.tprintf("connections: %d   signal blocked: %v   rebinds: %d", common.model_connection_count(&model), common.model_is_blocked(&model), model.reloads), {20, 150}, 20, karl2d.DARK_BLUE)

	karl2d.draw_text("log (deferred lines come after the frame, the one shot line comes first)", {20, 220}, 20, karl2d.DARK_GRAY)
	for i in 0 ..< common.LOG_LINES {
		karl2d.draw_text(common.model_log_line(&model, i), {40, 250 + f32(i) * 24}, 20, karl2d.BLACK)
	}

	karl2d.present()
}
