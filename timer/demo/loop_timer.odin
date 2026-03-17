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

loop_timer: Timer = {
    mode = .loop,
    callbacks = {timeout},
}

init :: proc() {
    ti.Start(&loop_timer, 120)
}
finit :: proc() {}

update :: proc() {
    ti.Update(&loop_timer, rl.GetFrameTime())
}

draw :: proc() {
    text:cstring = seconds_to_clock(loop_timer.remain)
    rl.DrawText(text, 10, 10, 20, rl.GRAY)
}

timeout :: proc( timer: ^Timer) {
    
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