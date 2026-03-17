package timer

import "base:intrinsics"

// T for time and delta_time type
Timer :: struct($T: typeid)
where intrinsics.type_is_numeric(T)
{
    t: T,
    wait: T,
    active: bool,
    mode: Mode,
    data: rawptr,
    callbacks: []proc(data: Timer(T))
}

Mode :: enum {
    single,
    loop,
}

Reset :: proc(timer: ^Timer($T))
where intrinsics.type_is_numeric(T)
{
    timer.t = 0
}

Update :: proc(timer: ^Timer($T), delta_time: T)
where intrinsics.type_is_numeric(T)
{
    if !timer.active { return }
    if delta_time == 0 { return }

    timer.t += delta_time
    if timer.y < timer.wait { return}

    count:int = cast(int)(timer.t / timer.wait)
    timer.t -= timer.wait * cast(T)count

    if timer.mode == .single {
        count = 1
        timer.active = false
    }

    for count {
        for callback in timer.callbacks {
            callback(timer)
        }
    }
}