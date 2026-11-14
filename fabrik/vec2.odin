package fabrik

import math "core:math"
import "core:testing"

vec2::[2]f32

// Returns magnitude of vector
vec2_mag :: proc(a: vec2) -> f32{
    return math.sqrt(a.x * a.x + a.y * a.y)
}

// Returns magnitude squared of vector (useful for fast comparisons)
vec2_mag2 :: proc(a: vec2) -> f32{
    return a.x * a.x + a.y * a.y
}

// Returns normalised version of vector
vec2_norm :: proc(a: vec2) -> vec2{
    r:f32 = 1.0 / vec2_mag(a)
    return {a.x * r, a.y * r}
}

// Useful for on-screen joystick
vec2_constrain_distance::proc(value:vec2, anchor:vec2, radius:f32)->vec2{
    _offset:vec2 = {value.x - anchor.x, value.y - anchor.y}
    _distance:f32 = math.min(vec2_mag(_offset), radius)
    _dir:vec2 = vec2_norm(_offset)
    return {anchor.x + _dir.x * _distance, anchor.y + _dir.y * _distance}
}

// --- Tests ---

@(test)
test_fabrik_vec2 :: proc(t: ^testing.T) {
    testing.expect_value(t, vec2_mag({3, 4}), f32(5))
    testing.expect_value(t, vec2_mag2({3, 4}), f32(25))
    normal: vec2 = vec2_norm({0, 7})
    testing.expect_value(t, normal, vec2{0, 1})

    // a stick held inside its radius follows the pointer, outside it stays on the ring
    testing.expect_value(t, vec2_constrain_distance({1, 0}, {0, 0}, 5), vec2{1, 0})
    testing.expect_value(t, vec2_constrain_distance({10, 0}, {0, 0}, 5), vec2{5, 0})
    testing.expect_value(t, vec2_constrain_distance({13, 4}, {10, 0}, 5), vec2{13, 4})
}
