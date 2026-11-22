#+build !js
package wait_for

// Waiting in real time for something that happens on another clock: a server that starts, a peer that answers, a thread that decodes. A test that polls N times and gives up has an allowance of N turns,
// which is as many real seconds as the turns take on the computer that wrote it; a slower device needs more time for the same thing and the other party (a process that is not ours) does not slow down
// with our turns. So the allowance is a time, and one number says how much slower a device is: the environment variable `ODIN_SLOW` (a device that needs three times the time: `ODIN_SLOW=3`).
//
//     deadline: wait_for.Deadline = wait_for.DeadlineStart(20)             // 20 seconds on a quiet computer, 60 with ODIN_SLOW=3
//     for !wait_for.DeadlineExpired(&deadline) {
//         UpdateBoth()
//         if connected() { break }
//         time.sleep(time.Millisecond)
//     }
//
// or `wait_for.Until(20, poll)` where `poll` does a turn of the work and says whether it happened. Nothing here allocates; the variable is read once per program.

import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"

SLOW_ENV :: "ODIN_SLOW"
SCALE_MAX :: 100

// The scale of a text: a number of 1 or more (1: not slower), at most SCALE_MAX; anything else is 1. Pure, so that it can be tested; `Scale` reads the environment with it.
ScaleFrom :: proc(text: string) -> f64 {
    value, ok := strconv.parse_f64(strings.trim_space(text))
    if !ok || value != value || value < 1 { return 1 }
    return min(value, SCALE_MAX)
}

@(private)
scale_value: f64
@(private)
scale_once: sync.Once

// How many times slower than a quiet development computer this device is (`ODIN_SLOW`, 1 when it is not set). Read once.
Scale :: proc() -> f64 {
    sync.once_do(&scale_once, proc() {
        text: string = os.get_env(SLOW_ENV, context.temp_allocator)
        scale_value = ScaleFrom(text)
    })
    return scale_value
}

Deadline :: struct {
    start: time.Tick,
    limit: time.Duration,       // already multiplied by the scale
}

// A deadline `seconds` of real time from now on a quiet computer: `seconds * Scale()` here.
DeadlineStart :: proc(seconds: f64) -> Deadline {
    return {start = time.tick_now(), limit = time.Duration(seconds * Scale() * f64(time.Second))}
}

DeadlineExpired :: proc(deadline: ^Deadline) -> bool {
    return time.tick_since(deadline.start) >= deadline.limit
}

// Seconds since the deadline was started
DeadlineElapsed :: proc(deadline: ^Deadline) -> f64 {
    return time.duration_seconds(time.tick_since(deadline.start))
}

// The time that the deadline allows, in seconds (with the scale)
DeadlineLimit :: proc(deadline: ^Deadline) -> f64 {
    return time.duration_seconds(deadline.limit)
}

// Calls `poll` until it says that what is waited for has happened, or `seconds` (with the scale) have passed, with `pause` between the turns. `poll` always runs at least once, also with no time
// left. True when it happened.
Until :: proc(seconds: f64, poll: proc(user: rawptr) -> bool, user: rawptr = nil, pause: time.Duration = time.Millisecond) -> bool {
    deadline: Deadline = DeadlineStart(seconds)
    for {
        if poll(user) { return true }
        if DeadlineExpired(&deadline) { return false }
        time.sleep(pause)
    }
}
