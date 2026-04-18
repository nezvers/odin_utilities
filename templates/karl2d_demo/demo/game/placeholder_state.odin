#+ private file
package game

import "core:fmt"
import "../../../karl2d"

@(private="package")
placeholder_state: GameState = {
    init,
    finit,
    process,
    draw,
    gui,
}

init :: proc() {}

finit :: proc() {}

process :: proc() {}

draw :: proc() {
    karl2d.clear(karl2d.LIGHT_BLUE)
}

gui :: proc() {
	karl2d.draw_text("Hellope!", {game_rect.x + 50, game_rect.y + 50}, 100, karl2d.DARK_BLUE)
    
    stats_text:string = fmt.tprintf("game = (%v, %v), window = (%v, %v), scale = %v, %v", game_rect.w, game_rect.h, window_width, window_height, window_scale, get_window_size())
	karl2d.draw_text(
        stats_text, 
        {game_rect.x + 50, game_rect.y + 150}, 
        30, 
        karl2d.DARK_GRAY,
    )
    karl2d.draw_text( fmt.tprintf("mouse %v", get_local_mouse_position()), {game_rect.x + 50, game_rect.y + 190},30, karl2d.DARK_GRAY)
}