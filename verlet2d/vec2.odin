package constrains

import math "core:math"

vec2::[2]f32

// Returns magnitude of vector
vec2_mag :: proc(a: vec2) -> f32{
    return math.sqrt(a.x * a.x + a.y * a.y)
}

// Returns magnitude squared of vector (useful for fast comparisons)
vec2_mag2 :: proc(a: vec2) -> f32{
    return a.x * a.x + a.y + a.y
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