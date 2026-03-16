package timer

Timer :: struct($T: typeid) {
    t: T,
    wait: T,
    data: rawptr,
    callbacks: []proc(data: rawptr)
}

Reset :: proc(timer: ^Timer) {
    timer.t = 0
}

Update :: proc(timer: ^Timer($T), delta_time: T) {
    timer.t += delta_time
    if timer.y < timer.wait { return}

    count:int = cast(int)(timer.t / timer.wait)
    timer.t -= timer.wait * cast(T)count

    for count {
        for callb in timer.callbacks {
            callb(timer.data)
        }
    }
}