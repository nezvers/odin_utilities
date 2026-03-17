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
    timer.remain = 0
}

Update :: proc(timer: ^Timer, delta_time: f32) {
    if !timer.active { return }
    if delta_time == 0 { return }

    timer.remain -= delta_time
    if timer.remain > 0 { return}

    count:int = cast(int)((timer.wait - timer.remain) / timer.wait)
    timer.remain += timer.wait * cast(f32)count

    if timer.mode == .single {
        count = 1
        timer.active = false
    } else {
        timer.remain = timer.wait + timer.remain
    }

    for i:int = 0; i < count; i += 1 {
        for callback in timer.callbacks {
            callback(timer)
        }
    }
}