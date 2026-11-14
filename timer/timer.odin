package timer
import "core:testing"

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

// --- Tests ---

@(private="file")
count_call :: proc(timer: ^Timer) {
    counter: ^int = cast(^int)timer.data
    counter^ += 1
}

@(test)
test_timer_single_shot :: proc(t: ^testing.T) {
    calls: int
    timer: Timer = {wait = 1, data = &calls, callbacks = []proc(timer: ^Timer){count_call}}
    Start(&timer)
    testing.expect_value(t, timer.remain, f32(1))

    Update(&timer, 0.4)
    testing.expect_value(t, calls, 0)
    testing.expect(t, abs(timer.remain - 0.6) < 1e-5)

    Update(&timer, 0.7)
    testing.expect_value(t, calls, 1)
    testing.expect_value(t, timer.active, false)
    testing.expect_value(t, timer.remain, f32(0))

    Update(&timer, 5)                                                              // finished: stays quiet
    testing.expect_value(t, calls, 1)
}

@(test)
test_timer_loop_keeps_the_overshoot :: proc(t: ^testing.T) {
    calls: int
    timer: Timer = {wait = 1, mode = .loop, data = &calls, callbacks = []proc(timer: ^Timer){count_call}}
    Start(&timer)

    Update(&timer, 1.5)
    testing.expect_value(t, calls, 1)
    testing.expect(t, abs(timer.remain - 0.5) < 1e-5, "half a second of the next lap is already used")
    testing.expect_value(t, timer.active, true)

    Update(&timer, 0.5)                                                            // lands exactly on the end
    testing.expect_value(t, calls, 2)
    testing.expect(t, abs(timer.remain - 1) < 1e-5)

    Update(&timer, 3.25)                                                           // several laps in one frame: one call, phase is kept
    testing.expect_value(t, calls, 3)
    testing.expect(t, abs(timer.remain - 0.75) < 1e-4)
}

@(test)
test_timer_start_reset_inactive :: proc(t: ^testing.T) {
    calls: int
    timer: Timer = {wait = 2, data = &calls, callbacks = []proc(timer: ^Timer){count_call}}

    Update(&timer, 10)                                                             // not started
    testing.expect_value(t, calls, 0)

    Start(&timer, 3)                                                               // a new wait replaces the old
    testing.expect_value(t, timer.wait, f32(3))
    Update(&timer, 1)
    Reset(&timer)
    testing.expect_value(t, timer.remain, f32(3))

    Start(&timer)                                                                  // no argument keeps the wait
    testing.expect_value(t, timer.wait, f32(3))

    Update(&timer, 0)                                                              // no time, no change
    testing.expect_value(t, timer.remain, f32(3))
}

@(test)
test_seconds_to_clock :: proc(t: ^testing.T) {
    seconds, minutes, hours, ms := seconds_to_clock(3725.5)
    testing.expect_value(t, seconds, i32(5))
    testing.expect_value(t, minutes, i32(2))
    testing.expect_value(t, hours, i32(1))
    testing.expect_value(t, ms, i32(500))

    seconds, minutes, hours, ms = seconds_to_clock(59.25)
    testing.expect_value(t, seconds, i32(59))
    testing.expect_value(t, minutes, i32(0))
    testing.expect_value(t, ms, i32(250))
}
