#+ private file
package game

// import "core:fmt"
import "core:math"
import "../karl2d"

@(private="package")
screen_title_state: GameState = {
    init,
    finit,
    process,
    draw,
    gui,
}

TITLE :: "Hellope!"

is_active:bool

init :: proc() {
    background_color = karl2d.BLACK
}

finit :: proc() {}

process :: proc() {
    is_active = is_any_key_held()
}

draw :: proc() {
    karl2d.clear(karl2d.BLACK)
}

gui :: proc() {
    window_size: = get_window_size()
    title_size:f32 = window_size.y * 0.1
    measure_title:Vec2 = karl2d.measure_text(TITLE, title_size, karl2d.FONT_DEFAULT)
    title_position:Vec2 = {projected_rect.w - measure_title.x, projected_rect.h - measure_title.y} * {0.5, 0.3}

	karl2d.draw_text(TITLE, {projected_rect.x, projected_rect.y} + title_position, title_size, karl2d.DARK_BLUE)
    if is_active {
        karl2d.draw_text("ACTIVE", title_position + {0, 100}, 20, karl2d.DARK_BLUE)
    }

}

is_any_key_held :: proc()->bool {
    for i:int=0; i < 349; i += 1 {
        if karl2d.key_is_held(cast(karl2d.Keyboard_Key)i){
            return true
        }
    }
    for i:int=0; i < 3; i += 1 {
        if karl2d.mouse_button_is_held(cast(karl2d.Mouse_Button)i){
            return true
        }
    }
    for gamepad:karl2d.Gamepad_Index=0; gamepad < karl2d.MAX_GAMEPADS; gamepad += 1 {
        if !karl2d.is_gamepad_active(gamepad) {continue}
        for button: = cast(karl2d.Gamepad_Button)0; button < karl2d.Gamepad_Button.Middle_Face_Right + cast(karl2d.Gamepad_Button)1; button += cast(karl2d.Gamepad_Button)1 {
            if karl2d.gamepad_button_is_held(gamepad, button) {
                return true
            }
        }
        for axis: = cast(karl2d.Gamepad_Axis)0; axis < karl2d.Gamepad_Axis.Right_Trigger + cast(karl2d.Gamepad_Axis)1; axis += cast(karl2d.Gamepad_Axis)1 {
            if math.abs(karl2d.get_gamepad_axis(gamepad, axis)) > 0.5 {
                return true
            }
        }
    }
    return false
}