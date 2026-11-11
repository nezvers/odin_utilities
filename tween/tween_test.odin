package tween

import "core:testing"

@(private="file")
near :: proc(a: f32, b: f32) -> bool {
    return abs(a - b) < 0.0001
}

@(test)
test_property_linear :: proc(t: ^testing.T) {
    value: f32 = 10
    tween: Tween = TweenMake()
    TweenProperty(&tween, &value, 20, 1)
    TweenPlay(&tween)

    TweenUpdate(&tween, 0.5)
    testing.expect(t, near(value, 15))
    finished: bool = TweenUpdate(&tween, 0.5)
    testing.expect(t, finished)
    testing.expect(t, value == 20)
    testing.expect(t, tween.state == .FINISHED)
}

@(test)
test_sequence_and_delay :: proc(t: ^testing.T) {
    a: f32
    b: f32
    tween: Tween = TweenMake()
    TweenProperty(&tween, &a, 1, 1)
    TweenProperty(&tween, &b, 1, 1, delay = 0.5)
    TweenPlay(&tween)

    TweenUpdate(&tween, 0.5)
    testing.expect(t, near(a, 0.5))
    testing.expect(t, b == 0)
    // 1.25 total: first done, second still in its 0.5 delay (0.25 elapsed)
    TweenUpdate(&tween, 0.75)
    testing.expect(t, a == 1)
    testing.expect(t, b == 0)
    // 1.75 total: second is 0.25 into its 1 second duration
    TweenUpdate(&tween, 0.5)
    testing.expect(t, near(b, 0.25))
}

@(test)
test_parallel :: proc(t: ^testing.T) {
    a: f32
    b: [2]f32
    tween: Tween = TweenMake()
    TweenProperty(&tween, &a, 10, 1)
    TweenProperty(&tween, &b, [2]f32{4, 8}, 2, parallel = true)
    TweenPlay(&tween)

    TweenUpdate(&tween, 1)
    testing.expect(t, a == 10)
    testing.expect(t, near(b.x, 2) && near(b.y, 4))
    testing.expect(t, tween.state == .PLAYING)
    TweenUpdate(&tween, 1)
    testing.expect(t, b == [2]f32{4, 8})
    testing.expect(t, tween.state == .FINISHED)
}

@(test)
test_relative_and_from :: proc(t: ^testing.T) {
    a: f32 = 5
    b: f32 = 5
    tween: Tween = TweenMake()
    TweenProperty(&tween, &a, 10, 1, relative = true)
    TweenProperty(&tween, &b, 20, 1, parallel = true, from = f32(0))
    TweenPlay(&tween)
    TweenUpdate(&tween, 1)
    testing.expect(t, a == 15)
    testing.expect(t, b == 20)
}

@(test)
test_integer_and_color :: proc(t: ^testing.T) {
    i: i32 = 0
    color: [4]u8 = {0, 0, 0, 255}
    tween: Tween = TweenMake()
    TweenProperty(&tween, &i, 10, 1)
    TweenProperty(&tween, &color, [4]u8{255, 100, 0, 255}, 1, parallel = true)
    TweenPlay(&tween)
    TweenUpdate(&tween, 0.5)
    testing.expect(t, i == 5)
    testing.expect(t, color.r == 128 || color.r == 127)
    TweenUpdate(&tween, 0.5)
    testing.expect(t, color == [4]u8{255, 100, 0, 255})
}

@(test)
test_overflow_carries :: proc(t: ^testing.T) {
    a: f32
    b: f32
    tween: Tween = TweenMake()
    TweenProperty(&tween, &a, 1, 1)
    TweenProperty(&tween, &b, 1, 1)
    TweenPlay(&tween)
    TweenUpdate(&tween, 1.5)
    testing.expect(t, a == 1)
    testing.expect(t, near(b, 0.5))
}

@(test)
test_loops :: proc(t: ^testing.T) {
    a: f32
    loops_done: int
    tween: Tween = TweenMake()
    TweenProperty(&tween, &a, 1, 1)
    tween.user_data = &loops_done
    tween.on_loop = proc(tween: ^Tween) {
        (cast(^int)tween.user_data)^ += 1
    }
    TweenSetLoops(&tween, 3)
    TweenPlay(&tween)

    for _ in 0..<5 {
        TweenUpdate(&tween, 1)
    }
    testing.expect(t, loops_done == 2)
    testing.expect(t, tween.state == .FINISHED)

    // infinite does not finish and does not hang on zero length
    TweenSetLoops(&tween, 0)
    TweenReset(&tween)
    TweenPlay(&tween)
    for _ in 0..<10 {
        TweenUpdate(&tween, 1)
    }
    testing.expect(t, tween.state == .PLAYING)
}

@(test)
test_callback_and_method :: proc(t: ^testing.T) {
    calls: int
    tween: Tween = TweenMake()
    tween.user_data = &calls
    TweenInterval(&tween, 1)
    TweenCallback(&tween, proc(tween: ^Tween) { (cast(^int)tween.user_data)^ += 1 })
    TweenMethod(&tween, proc(tween: ^Tween, t: f32) { (cast(^int)tween.user_data)^ += 10 }, 1)
    TweenPlay(&tween)
    // Interval ends, callback fires once, method starts and is called with 0
    TweenUpdate(&tween, 1)
    testing.expect(t, calls == 11)
    TweenUpdate(&tween, 0.5)
    testing.expect(t, calls == 21)
    TweenUpdate(&tween, 0.5)
    testing.expect(t, calls == 31)
    testing.expect(t, tween.state == .FINISHED)
}

@(test)
test_pause_stop_speed :: proc(t: ^testing.T) {
    a: f32
    tween: Tween = TweenMake()
    TweenProperty(&tween, &a, 1, 1)
    TweenUpdate(&tween, 0.5)
    testing.expect(t, a == 0)

    TweenPlay(&tween)
    tween.speed_scale = 2
    TweenUpdate(&tween, 0.25)
    testing.expect(t, near(a, 0.5))
    TweenPause(&tween)
    TweenUpdate(&tween, 1)
    testing.expect(t, near(a, 0.5))
    TweenStop(&tween)
    testing.expect(t, tween.state == .STOPPED && tween.t == 0)
}

@(test)
test_step_capacity :: proc(t: ^testing.T) {
    tween: Tween = TweenMake()
    for _ in 0..<TWEEN_STEPS_MAX {
        testing.expect(t, TweenInterval(&tween, 1) != nil)
    }
    testing.expect(t, TweenInterval(&tween, 1) == nil)
}

@(test)
test_system_pool :: proc(t: ^testing.T) {
    system: TweenSystem(4)
    a: f32
    tween, ok := SystemNew(&system)
    testing.expect(t, ok)
    handle: Handle = tween.handle
    TweenProperty(tween, &a, 1, 1)
    TweenPlay(tween)

    SystemUpdate(&system, 0.5)
    testing.expect(t, near(a, 0.5))
    testing.expect(t, SystemLen(&system) == 1)
    _, found := SystemGet(&system, handle)
    testing.expect(t, found)

    SystemUpdate(&system, 0.5)
    testing.expect(t, a == 1)
    testing.expect(t, SystemLen(&system) == 0)
    _, found = SystemGet(&system, handle)
    testing.expect(t, !found)

    // capacity is N - 1
    for _ in 0..<3 {
        _, ok = SystemNew(&system)
        testing.expect(t, ok)
    }
    _, ok = SystemNew(&system)
    testing.expect(t, !ok)

    SystemClear(&system)
    testing.expect(t, SystemLen(&system) == 0)
}

@(test)
test_system_kill_and_keep :: proc(t: ^testing.T) {
    system: TweenSystem(4)
    a: f32
    killed, _ := SystemNew(&system)
    TweenProperty(killed, &a, 1, 1)
    TweenPlay(killed)
    killed_handle: Handle = killed.handle
    testing.expect(t, SystemKill(&system, killed_handle))
    SystemUpdate(&system, 1)
    testing.expect(t, a == 0)

    kept, _ := SystemNew(&system)
    kept.keep = true
    TweenProperty(kept, &a, 1, 1)
    TweenPlay(kept)
    SystemUpdate(&system, 1)
    testing.expect(t, SystemLen(&system) == 1)
    testing.expect(t, kept.state == .FINISHED)
}
