#+private file
package game

import "core:fmt"
import "../../../karl2d"

@(private="package")
placeholder_state: GameState = {
    init,
    finit,
    process,
    draw,
}

init :: proc() {}

finit :: proc() {}

process :: proc() {}

draw :: proc() {
    karl2d.clear(karl2d.LIGHT_BLUE)
	karl2d.draw_text("Hellope!", {50, 50}, 100, karl2d.DARK_BLUE)
    
    stats_text:string = fmt.tprintf("window = (%v, %v), scale = %v, %v", window_width, window_height, window_scale, get_window_size())
	karl2d.draw_text(
        stats_text, 
        {50, 150}, 
        30, 
        karl2d.DARK_GRAY,
    )
    karl2d.draw_text( fmt.tprintf("mouse %v", get_local_mouse_position()), {50, 190},30, karl2d.DARK_GRAY)
}