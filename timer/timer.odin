package timer

Timer :: struct {
    remain: f32,
    wait: f32,
    active: bool,
    mode: Mode,
    data: rawptr,
    callbacks: []proc(data: ^Timer),
}

Mode :: enum {
    single,
    loop,
}

Start :: proc(timer: ^Timer, wait: f32 = 0) {
    timer.active = true
    if wait != 0 {
        timer.wait = wait
    }
    timer.remain = timer.wait
}

Reset :: proc(timer: ^Timer) {
    timer.remain = timer.wait
}

Update :: proc(timer: ^Timer, delta_time: f32) {
    if !timer.active { return }
    if delta_time == 0 { return }

    timer.remain -= delta_time
    if timer.remain > 0 { return}

    diff:f32 = (timer.wait - timer.remain)
    count:int = cast(int)(diff / timer.wait)
    timer.remain = timer.wait - (diff - (timer.wait * cast(f32)count))

    if timer.mode == .single {
        timer.active = false
        timer.remain = 0
    }

    for callback in timer.callbacks {
        callback(timer)
    }
}

seconds_to_clock :: proc(sec:f32)->(seconds:i32, minutes:i32, hours:i32, ms:i32) {
    seconds = cast(i32)sec
    minutes = seconds / 60
    hours = minutes / 60
    fract:f32 = sec - cast(f32)seconds
    ms = cast(i32)(fract * 1000)
    seconds %= 60
    minutes %= 60
    return
}