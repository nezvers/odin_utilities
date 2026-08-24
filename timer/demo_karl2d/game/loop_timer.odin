#+private file
package game

import "core:fmt"
import "../../../karl2d"
import timerPackage "../.."
Timer :: timerPackage.Timer

@(private="package")
loop_timer_state: GameState = {
    init,
    finit,
    process,
    draw,
}

HEIGHT_CLOCK :: 160
InputValue :: struct{
    digits: [6]u8,
    count: u8,
}
input_value:InputValue

loop_timer: Timer = {
    mode = .loop,
    callbacks = {timeout},
}
measure_clock:Vec2
numbers: []string = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}
alert_clip: karl2d.Audio_Clip
flash_value:f32 = 0

init :: proc() {
    background_color = karl2d.WHITE

    // Start input
    input_value.count = 3
    input_value.digits[2] = 2
    input_value.digits[1] = 0
    input_value.digits[0] = 0
    loop_timer.wait = input_to_seconds()

    timerPackage.Reset(&loop_timer)
    measure_clock = karl2d.measure_text("00:00:00.000", HEIGHT_CLOCK)
    alert_clip = karl2d.load_audio_clip_from_bytes(#load("../../../assets/sounds/alert_sound.wav"))
}

finit :: proc() {}

process :: proc() {
    delta_time:f32 = karl2d.get_frame_time()
    timerPackage.Update(&loop_timer, delta_time)
    flash_update(delta_time)
    update_keyboard_input()
}

draw :: proc() {
    window_size: = get_window_size()
	center_x:f32 = (window_size.x / 2)
    center_y:f32 = (window_size.y / 2)
    // Clock
    text_clock:string = seconds_to_clock(loop_timer.remain)
    karl2d.draw_text(
        text_clock,
        {center_x - measure_clock.x / 2, center_y - measure_clock.y / 2},
        HEIGHT_CLOCK,
        karl2d.BLACK,
    )
    
    // Input
    is_valid:bool = input_is_valid()
    input_y:f32 = center_y - HEIGHT_CLOCK
    input_right:f32 = center_x + measure_clock.x / 2 - measure_clock.x / 5
    OFF_INPUT :: 75
    number_x:f32 = input_right
    for i:int = 0; i < len(input_value.digits); i += 1 {
        color:karl2d.Color = karl2d.LIGHT_GRAY
        number_x -= OFF_INPUT
        if cast(u8)i < input_value.count {
            if is_valid {
                color = karl2d.GRAY
            } else {
                color = karl2d.RED
            }
        }
        karl2d.draw_text(numbers[input_value.digits[i]], {number_x, input_y}, HEIGHT_CLOCK / 2, color)

        if i != 1 && i != 3 { continue }
        number_x -= OFF_INPUT / 2
        karl2d.draw_text(":", {number_x, input_y}, HEIGHT_CLOCK / 2, color)
    }

    percent:f32 = loop_timer.remain / loop_timer.wait
    progress_rect:Rect = {
        (center_x - measure_clock.x / 2),
        (center_y + HEIGHT_CLOCK / 2),
        (measure_clock.x),
        (HEIGHT_CLOCK / 2),
    }

    karl2d.draw_rect_outline(progress_rect, 5, karl2d.LIGHT_GRAY)
    progress_rect.w *= percent
    karl2d.draw_rect(progress_rect, karl2d.RL_LIME)
}



timeout :: proc( timer: ^Timer) {
    // TODO: play a sound & flash a screen
    fmt.printfln("Timeout: ")
    flash_value = 1
    karl2d.play_audio_clip(alert_clip)
}

seconds_to_clock :: proc(sec:f32)->string {
    seconds,minutes,hours,ms: = timerPackage.seconds_to_clock(sec)
    return fmt.tprintf("%02d:%02d:%02d.%03d", hours, minutes, seconds, ms)
}

input_pop :: proc() {
    if input_value.count == 0 { return }
    input_value.count -= 1

    for i:int=0; i < len(input_value.digits) - 1; i += 1 {
        input_value.digits[i] = input_value.digits[i + 1]
    }
    input_value.digits[len(input_value.digits) - 1] = 0
}

input_push :: proc(value: u8) {
    if input_value.count == len(input_value.digits) { return }
    assert(value < 10)

    last:int = len(input_value.digits) - 1
    for i:int=0; i < last; i += 1 {
        input_value.digits[last - i] = input_value.digits[last - i - 1]
    }
    input_value.digits[0] = value
    input_value.count += 1
}

input_is_valid :: proc()->bool {
    return input_value.digits[1] < 7 && input_value.digits[3] < 7
}

update_keyboard_input :: proc() {
    if karl2d.key_went_down(.Backspace) || karl2d.key_went_down(.Delete) {
        input_pop()
    }
    if karl2d.key_went_down(.N0) || karl2d.key_went_down(.NP_0) {
        input_push(0)
    }
    if karl2d.key_went_down(.N1) || karl2d.key_went_down(.NP_1) {
        input_push(1)
    }
    if karl2d.key_went_down(.N2) || karl2d.key_went_down(.NP_2) {
        input_push(2)
    }
    if karl2d.key_went_down(.N3) || karl2d.key_went_down(.NP_3) {
        input_push(3)
    }
    if karl2d.key_went_down(.N4) || karl2d.key_went_down(.NP_4) {
        input_push(4)
    }
    if karl2d.key_went_down(.N5) || karl2d.key_went_down(.NP_5) {
        input_push(5)
    }
    if karl2d.key_went_down(.N6) || karl2d.key_went_down(.NP_6) {
        input_push(6)
    }
    if karl2d.key_went_down(.N7) || karl2d.key_went_down(.NP_7) {
        input_push(7)
    }
    if karl2d.key_went_down(.N8) || karl2d.key_went_down(.NP_8) {
        input_push(8)
    }
    if karl2d.key_went_down(.N9) || karl2d.key_went_down(.NP_9) {
        input_push(9)
    }
    if karl2d.key_went_down(.Enter) && input_is_valid() {
        loop_timer.wait = input_to_seconds()
        loop_timer.active = false
        timerPackage.Reset(&loop_timer)
    }
    if karl2d.key_went_down(.Space) {
        if loop_timer.mode == .loop {
            loop_timer.active = !loop_timer.active
        } else if loop_timer.mode == .single {
            if loop_timer.remain > 0 {
                loop_timer.active = !loop_timer.active
            } else {
                timerPackage.Start(&loop_timer)
            }
        }
    }
}

input_to_seconds :: proc()->f32 {
    hours:u32 = cast(u32)(input_value.digits[5] * 10 + input_value.digits[4])
    minutes:u32 = cast(u32)(input_value.digits[3] * 10 + input_value.digits[2])
    seconds:u32 = cast(u32)(input_value.digits[1] * 10 + input_value.digits[0])

    return cast(f32)(seconds + minutes * 60 + hours * 60 * 60)
}

flash_update :: proc(delta_time:f32, mult:f32 = 2) {
    if flash_value == 0 { return }
    flash_value -= delta_time * mult
    if flash_value < 0 { flash_value = 0}
    yellow: = karl2d.f32_color_from_color(karl2d.RL_YELLOW)
    white: = karl2d.f32_color_from_color(karl2d.WHITE)
    result:[3]f32
    result.rgb = white.rgb + (yellow.rgb - white.rgb) * flash_value
    background_color.r = cast(u8)(result.r * 255)
    background_color.g = cast(u8)(result.g * 255)
    background_color.b = cast(u8)(result.b * 255)
}