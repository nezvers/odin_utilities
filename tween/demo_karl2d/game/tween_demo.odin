#+private file
package game

import "core:fmt"
import "../../../karl2d"
import "core:math/ease"

import tw "../../"
Tween :: tw.Tween
Handle :: tw.Handle
handleNone :: tw.HandleNone

@(private="package")
tween_state: GameState = {
    init,
    finit,
    process,
    draw,
}

tween_system: tw.TweenSystem(512, 128)

animated_rect:Rect = {}

init :: proc() {
    background_color = karl2d.LIGHT_BLUE

    if tween, ok: = tw.TweenNew(&tween_system); ok {
        tween.length = 20.0
        tween.user_data = &animated_rect
        tween.on_update = proc(tween: ^Tween, t:f32) {
            // Animate rectangle
            rect:^Rect = cast(^Rect)tween.user_data
            _t:f32 = ease.quadratic_in(t)
            rect.x = 200.0 * _t
            rect.y = 200.0 * _t
            rect.w = 200.0 * _t
            rect.h = 200.0 * _t
        }
        tw.TweenStart(&tween_system, tween.handle)
    }
}

rect_width_anim :: proc(tween: ^Tween, t:f32) {
    rect:^Rect = cast(^Rect)tween.user_data
    _t:f32 = ease.cubic_out(t)
    rect.w = 0.0 + 200.0 * _t
}

finit :: proc() {}

process :: proc() {
    delta_time:f32 = karl2d.get_frame_time()
    tw.UpdateSystem(&tween_system, delta_time, true)
}

draw :: proc() {
    color:Color = karl2d.RL_SKYBLUE
    karl2d.draw_rect(animated_rect, color, {}, 0)

    stats_text:string = fmt.tprintf("window = (%v, %v), scale = %v, %v", window_width, window_height, window_scale, get_window_size())
	karl2d.draw_text(
        stats_text, 
        {50, 150}, 
        30, 
        karl2d.DARK_GRAY,
    )
}