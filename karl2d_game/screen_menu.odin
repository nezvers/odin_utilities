#+ private file
package game

import "core:fmt"
// import "core:math"
import "ui"
import "../karl2d"
import "assets"

@(private="package")
screen_menu_state: GameState = {
    init,
    finit,
    process,
    draw,
    gui,
}

TITLE :: "Start"
HINT :: "WASD: move\nLeft mouse: shoot"

music:karl2d.Audio_Stream

init :: proc() {
    background_color = karl2d.BLACK

    music = karl2d.load_audio_stream_from_bytes(assets.music_lost_hope)
    karl2d.set_audio_stream_loop(music, true)
    karl2d.play_audio_stream(music)
    karl2d.set_audio_stream_volume(music, 0.6)
}

finit :: proc() {
    karl2d.stop_audio_stream(music)
    karl2d.destroy_audio_stream(music)
}

process :: proc() {
    karl2d.update_audio_stream(music)
    if is_any_key_released() {
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
    title_position:Vec2 = ui.GetElementPosition({0,0,window_size.x, window_size.y}, measure_title, {0.5, 0.3})
	karl2d.draw_text(TITLE, title_position, title_size, karl2d.DARK_BLUE)

    if kill_count > 0 {
        score_size:f32 = window_size.y * 0.07
        score_text:string = fmt.tprintf("KILL COUNT: %v", kill_count)
        score_measure:Vec2 = karl2d.measure_text(score_text, score_size, karl2d.FONT_DEFAULT)
        score_position:Vec2 = ui.GetElementPosition({0,0,window_size.x, window_size.y}, score_measure, {0.001, 0.001}, {0,0})
        karl2d.draw_text(score_text, score_position, score_size, karl2d.DARK_BLUE)
    }
    
    hint_size:f32 = window_size.y * 0.1
    measure_hint:Vec2 = karl2d.measure_text(HINT, hint_size, karl2d.FONT_DEFAULT)
    hint_position:Vec2 = ui.GetElementPosition({0,0,window_size.x, window_size.y}, measure_hint, {0.5, 0.7})
	karl2d.draw_text(HINT, hint_position, hint_size, karl2d.DARK_BLUE)
}