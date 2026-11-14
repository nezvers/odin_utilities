package cool_math

import "core:math"
import "core:testing"

get_impulse_time :: proc(gravity:f32, time:f32)-> f32 {
    return gravity * time * 0.5
}

get_impulse_height :: proc(gravity:f32, height:f32)-> f32 {
    return math.sqrt(2 * gravity * height)
}

get_gravity_time :: proc(impulse:f32, time:f32)-> f32 {
    return 2.0 * impulse / time
}

get_height :: proc(impulse:f32, gravity:f32)-> f32 {
    return (0.5 * impulse * impulse) / gravity
}

get_time :: proc(impulse:f32, gravity:f32)-> f32 {
    return (impulse * 2) / gravity
}

// --- Tests ---

@(private="file")
near :: proc(a, b: f32, epsilon: f32 = 1e-5) -> bool {
    return abs(a - b) <= epsilon
}

@(test)
test_platformer_formulas_are_consistent :: proc(t: ^testing.T) {
    gravity, height: f32 = 20, 3
    impulse: f32 = get_impulse_height(gravity, height)
    testing.expect(t, near(impulse, math.sqrt(f32(120))))
    testing.expect(t, near(get_height(impulse, gravity), height, 1e-4), "the height of that impulse is the height it came from")

    rise_time: f32 = get_time(impulse, gravity)                      // up and down
    testing.expect(t, near(rise_time, 2 * impulse / gravity))
    testing.expect(t, near(get_gravity_time(impulse, rise_time), gravity, 1e-4), "gravity from the impulse and the time")
    testing.expect(t, near(get_impulse_time(gravity, rise_time), impulse, 1e-4), "impulse from the gravity and the time")
}
