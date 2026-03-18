#+private file
package demo

import rl "vendor:raylib"
import ti ".."
Timer :: ti.Timer

@(private="package")
state_loop_timer: State = {
    init,
    finit,
    update,
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
measure_clock:i32
numbers: []cstring = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}

init :: proc() {
    // Start input
    input_value.count = 3
    input_value.digits[2] = 2
    input_value.digits[1] = 0
    input_value.digits[0] = 0

    ti.Start(&loop_timer, 120)
    measure_clock = rl.MeasureText("00:00:00.000", HEIGHT_CLOCK)
}
finit :: proc() {}

update :: proc() {
    ti.Update(&loop_timer, rl.GetFrameTime())

    if rl.IsKeyPressed(rl.KeyboardKey.BACKSPACE) || rl.IsKeyPressed(rl.KeyboardKey.DELETE) {
        input_pop()
    }
}

draw :: proc() {
    center_x:i32 = cast(i32)(screen_size.x / 2)
    center_y:i32 = cast(i32)(screen_size.y / 2)
    // Clock
    text_clock:cstring = seconds_to_clock(loop_timer.remain)
    rl.DrawText(
        text_clock, 
        center_x - measure_clock / 2, 
        center_y - HEIGHT_CLOCK / 2, 
        HEIGHT_CLOCK, rl.GRAY)
    
    // Input
    input_y:i32 = center_y - HEIGHT_CLOCK
    input_right:i32 = center_x + measure_clock / 2
    OFF_INPUT :: 75
    number_x:i32 = input_right
    for i:int = 0; i < len(input_value.digits); i += 1 {
        color:rl.Color = rl.LIGHTGRAY
        number_x -= OFF_INPUT
        if cast(u8)i < input_value.count {
            color = rl.GRAY
        }
        rl.DrawText(numbers[input_value.digits[i]], number_x, input_y, HEIGHT_CLOCK / 2, color)

        if i != 1 && i != 3 { continue }
        number_x -= OFF_INPUT / 2
        rl.DrawText(":", number_x, input_y, HEIGHT_CLOCK / 2, color)
    }
}

timeout :: proc( timer: ^Timer) {
    // TODO: play a sound & flash a screen
}

seconds_to_clock :: proc(sec:f32)->cstring {
    seconds:i32 = cast(i32)sec
    minutes:i32 = seconds / 60
    hours:i32 = minutes / 60
    fract:f32 = sec - cast(f32)seconds
    ms:i32 = cast(i32)(fract * 1000)
    seconds %= 60
    minutes %= 60
    return rl.TextFormat("%02d:%02d:%02d.%03d", hours, minutes, seconds, ms)
}

input_pop :: proc() {
    if input_value.count == 0 { return }
    input_value.count -= 1

    for i:int=0; i < len(input_value.digits) - 1; i += 1 {
        input_value.digits[i] = input_value.digits[i + 1]
    }
    input_value.digits[len(input_value.digits) - 1] = 0
}