#+private file
package demo

import "core:fmt"
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
    loop_timer.wait = input_to_seconds()

    ti.Start(&loop_timer)
    measure_clock = rl.MeasureText("00:00:00.000", HEIGHT_CLOCK)
}
finit :: proc() {}

update :: proc() {
    ti.Update(&loop_timer, rl.GetFrameTime())
    update_keyboard_input()
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
    is_valid:bool = input_is_valid()
    input_y:i32 = center_y - HEIGHT_CLOCK
    input_right:i32 = center_x + measure_clock / 2
    OFF_INPUT :: 75
    number_x:i32 = input_right
    for i:int = 0; i < len(input_value.digits); i += 1 {
        color:rl.Color = rl.LIGHTGRAY
        number_x -= OFF_INPUT
        if cast(u8)i < input_value.count {
            if is_valid {
                color = rl.GRAY
            } else {
                color = rl.RED
            }
        }
        rl.DrawText(numbers[input_value.digits[i]], number_x, input_y, HEIGHT_CLOCK / 2, color)

        if i != 1 && i != 3 { continue }
        number_x -= OFF_INPUT / 2
        rl.DrawText(":", number_x, input_y, HEIGHT_CLOCK / 2, color)
    }
}

timeout :: proc( timer: ^Timer) {
    // TODO: play a sound & flash a screen
    fmt.printfln("Timeout: ")
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
    if rl.IsKeyPressed(rl.KeyboardKey.BACKSPACE) || rl.IsKeyPressed(rl.KeyboardKey.DELETE) {
        input_pop()
    }
    if rl.IsKeyPressed(rl.KeyboardKey.ZERO) || rl.IsKeyPressed(rl.KeyboardKey.KP_0) {
        input_push(0)
    }
    if rl.IsKeyPressed(rl.KeyboardKey.ONE) || rl.IsKeyPressed(rl.KeyboardKey.KP_1) {
        input_push(1)
    }
    if rl.IsKeyPressed(rl.KeyboardKey.TWO) || rl.IsKeyPressed(rl.KeyboardKey.KP_2) {
        input_push(2)
    }
    if rl.IsKeyPressed(rl.KeyboardKey.THREE) || rl.IsKeyPressed(rl.KeyboardKey.KP_3) {
        input_push(3)
    }
    if rl.IsKeyPressed(rl.KeyboardKey.FOUR) || rl.IsKeyPressed(rl.KeyboardKey.KP_4) {
        input_push(4)
    }
    if rl.IsKeyPressed(rl.KeyboardKey.FIVE) || rl.IsKeyPressed(rl.KeyboardKey.KP_5) {
        input_push(5)
    }
    if rl.IsKeyPressed(rl.KeyboardKey.SIX) || rl.IsKeyPressed(rl.KeyboardKey.KP_6) {
        input_push(6)
    }
    if rl.IsKeyPressed(rl.KeyboardKey.SEVEN) || rl.IsKeyPressed(rl.KeyboardKey.KP_7) {
        input_push(7)
    }
    if rl.IsKeyPressed(rl.KeyboardKey.EIGHT) || rl.IsKeyPressed(rl.KeyboardKey.KP_8) {
        input_push(8)
    }
    if rl.IsKeyPressed(rl.KeyboardKey.NINE) || rl.IsKeyPressed(rl.KeyboardKey.KP_9) {
        input_push(9)
    }
    if rl.IsKeyPressed(rl.KeyboardKey.ENTER) && input_is_valid() {
        loop_timer.wait = input_to_seconds()
        loop_timer.active = false
        ti.Reset(&loop_timer)
    }
    if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
        if loop_timer.mode == .loop {
            loop_timer.active = !loop_timer.active
        } else if loop_timer.mode == .single {
            if loop_timer.remain > 0 {
                loop_timer.active = !loop_timer.active
            } else {
                ti.Start(&loop_timer)
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