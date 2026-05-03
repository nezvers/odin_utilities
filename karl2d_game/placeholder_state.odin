#+ private file
package game

import "core:fmt"
import "../karl2d"

@(private="package")
placeholder_state: GameState = {
    init,
    finit,
    process,
    draw,
    gui,
}

init :: proc() {
    background_color = karl2d.LIGHT_BLUE
}

finit :: proc() {}

process :: proc() {}

draw :: proc() {
    karl2d.clear(karl2d.RL_LIME)
    karl2d.draw_rect({0,0,16,16}, karl2d.LIGHT_GRAY)
	karl2d.draw_text("Hellope!", {10, 10}, 20, karl2d.DARK_BLUE)
    
    stats_text:string = fmt.tprintf("game = (%v, %v), window = (%v, %v)", view_rect.w, view_rect.h, window_width, window_height, )
	karl2d.draw_text(
        stats_text, 
        {10, 35}, 
        20, 
        karl2d.DARK_GRAY,
    )
    
    stats_text = fmt.tprintf("scale = %v, %v", window_scale, get_window_size())
	karl2d.draw_text(
        stats_text, 
        {10, 60}, 
        20, 
        karl2d.DARK_GRAY,
    )
}

gui :: proc() {

}