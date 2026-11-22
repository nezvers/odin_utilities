#+build !js
package wait_for

import "core:testing"
import "core:time"

@(test)
test_the_scale_is_a_number_of_one_or_more :: proc(t: ^testing.T) {
    testing.expect_value(t, ScaleFrom(""), 1)
    testing.expect_value(t, ScaleFrom("1"), 1)
    testing.expect_value(t, ScaleFrom("3"), 3)
    testing.expect_value(t, ScaleFrom(" 2.5 "), 2.5)
    testing.expect_value(t, ScaleFrom("0.5"), 1)              // a faster computer does not get shorter limits than the ones that were set
    testing.expect_value(t, ScaleFrom("0"), 1)
    testing.expect_value(t, ScaleFrom("-4"), 1)
    testing.expect_value(t, ScaleFrom("abc"), 1)
    testing.expect_value(t, ScaleFrom("nan"), 1)
    testing.expect_value(t, ScaleFrom("1000000"), SCALE_MAX)  // a typo does not make a test wait for a day
    testing.expect(t, Scale() >= 1 && Scale() <= SCALE_MAX, "the scale of this run")
}

@(test)
test_a_deadline_is_a_time_and_follows_the_scale :: proc(t: ^testing.T) {
    deadline: Deadline = DeadlineStart(0.05)
    testing.expect(t, !DeadlineExpired(&deadline), "not yet")
    testing.expect(t, abs(DeadlineLimit(&deadline) - 0.05 * Scale()) < 0.001, "the limit is the seconds times the scale")
    time.sleep(time.Duration(0.06 * Scale() * f64(time.Second)))
    testing.expect(t, DeadlineExpired(&deadline), "after its time")
    testing.expect(t, DeadlineElapsed(&deadline) >= 0.05 * Scale(), "the elapsed time")
    zero: Deadline = DeadlineStart(0)
    testing.expect(t, DeadlineExpired(&zero), "no time at all is expired at once")
}

@(private = "file")
Counter :: struct {
    turns: int,
    until: int,
}

@(test)
test_until_stops_when_it_happens_and_when_the_time_is_over :: proc(t: ^testing.T) {
    counter: Counter = {until = 5}
    happened: bool = Until(5, proc(user: rawptr) -> bool {
        c: ^Counter = cast(^Counter)user
        c.turns += 1
        return c.turns >= c.until
    }, &counter)
    testing.expect(t, happened)
    testing.expect_value(t, counter.turns, 5)

    // what never happens: false after the time, with many turns on the way
    never: Counter = {until = 1 << 30}
    start: time.Tick = time.tick_now()
    happened = Until(0.05, proc(user: rawptr) -> bool {
        c: ^Counter = cast(^Counter)user
        c.turns += 1
        return false
    }, &never)
    testing.expect(t, !happened)
    testing.expect(t, never.turns > 3, "it kept trying")
    testing.expect(t, time.duration_seconds(time.tick_since(start)) >= 0.05 * Scale(), "and waited the time that it was given")

    // with no time at all the poll still runs once
    once: Counter = {until = 1}
    testing.expect(t, Until(0, proc(user: rawptr) -> bool {
        c: ^Counter = cast(^Counter)user
        c.turns += 1
        return true
    }, &once))
    testing.expect_value(t, once.turns, 1)
}
