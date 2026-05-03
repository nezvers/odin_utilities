#+ private file
package game

// import "core:fmt"
// import "core:math"
import "../karl2d"
import "ui"

@(private="package")
screen_title_state: GameState = {
    init,
    finit,
    process,
    draw,
    gui,
}

TITLE :: "Hellope!"

init :: proc() {
    background_color = karl2d.BLACK
}

finit :: proc() {}

process :: proc() {
    if is_any_key_held() {
        change_game_state(screen_game_state)
    }
}

draw :: proc() {
    // karl2d.clear(background_color)
}

gui :: proc() {
    window_size: = get_window_size()
    title_size:f32 = window_size.y * 0.25
    measure_title:Vec2 = karl2d.measure_text(TITLE, title_size, karl2d.FONT_DEFAULT)
    // title_position:Vec2 = {projected_rect.w - measure_title.x, projected_rect.h - measure_title.y} * {0.5, 0.3}
    title_position:Vec2 = ui.GetElementPosition({0,0,window_size.x, window_size.y}, measure_title, {0.5, 0.3})


	karl2d.draw_text(TITLE, {projected_rect.x, projected_rect.y} + title_position, title_size, karl2d.DARK_BLUE)
}