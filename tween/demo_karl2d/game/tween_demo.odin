#+private file
package game

import "core:fmt"
import "../../../karl2d"
import "core:math/ease"

import tw "../../"
Tween :: tw.Tween
TweenQueue :: tw.TweenQueue
TweenPool :: tw.TweenPool

@(private="package")
tween_state: GameState = {
    init,
    finit,
    process,
    draw,
}

waiting_buffer: [128]TweenQueue
active_buffer: [128]TweenQueue
waiting_tween_pool: TweenPool = {list = waiting_buffer[:]}
active_tween_pool: TweenPool = {list = active_buffer[:]}

animated_rect:Rect = {10, 10, 200, 200}

init :: proc() {
    background_color = karl2d.LIGHT_BLUE

    temp_queue:TweenQueue = {}
    item: ^TweenQueue
    append_ok:bool
    temp_queue.tween = {
        length = 30.0,
        user_data = &animated_rect,
        update = rect_width_anim,
    }
    item, append_ok = tw.PoolAppend(&waiting_tween_pool, &temp_queue)
}

rect_width_anim :: proc(tween: ^Tween, t:f32) {
    rect:^Rect = cast(^Rect)tween.user_data
    _t:f32 = ease.cubic_out(t)
    rect.w = 0.0 + 200.0 * _t
}

finit :: proc() {}

process :: proc() {
    delta_time:f32 = karl2d.get_frame_time()
    tw.UpdateSystem(&waiting_tween_pool, &active_tween_pool, delta_time, true)
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