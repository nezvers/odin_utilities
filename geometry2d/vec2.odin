package geometry2d

import "core:math"

vec2 :: [2]f32


vec2_sign::proc(p:vec2)->vec2{
    return {f32(signf(p.x)), f32(signf(p.y))}
}
vec2_abs::proc(p:vec2)->vec2{
    return {abs(p.x), abs(p.y)}
}

// Returns rectangular area of vector
vec2_area :: proc(a: vec2) -> f32{
    return a.x * a.y
}

// Returns magnitude of vector
vec2_mag :: proc(a: vec2) -> f32{
    return sqrt(a.x * a.x + a.y * a.y)
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

// Returns vector at 90 degrees to this one
vec2_perp :: proc(v: vec2) -> vec2{
    return {-v.y, v.x}
}

// Rounds both components down
vec2_floor :: proc(v: vec2) -> vec2{
    return {math.floor_f32(v.x), math.floor_f32(v.y)}
}

// Rounds both components up
vec2_ceil :: proc(v: vec2) -> vec2{
    return {math.ceil_f32(v.x), math.ceil_f32(v.y)}
}

// Returns 'element-wise' max of a vector and another vector
vec2_max :: proc(a: vec2, b: vec2) -> vec2{
    return {math.max(a.x, b.x), math.max(a.y, b.y)}
}

// Returns 'element-wise' min of a vector and another vector
vec2_min :: proc(a: vec2, b: vec2) -> vec2{
    return {math.min(a.x, b.x), math.min(a.y, b.y)}
}

// Calculates scalar dot product between a vector and another vector
vec2_dot :: proc(a: vec2, b: vec2) -> f32{
    return a.x * b.x + a.y * b.y
}

// Calculates 'scalar' cross product between a vector and another vector (useful for winding orders)
vec2_cross :: proc(a: vec2, b: vec2) -> f32{
    return a.x * b.y + a.y * b.x
}

// Treat as polar coordinate (R, Theta), return cartesian equivalent (X, Y)
vec2_cartisian :: proc(a: vec2) -> vec2{
    return {math.cos_f32(a.y) * a.x, math.sin_f32(a.y) * a.x}
}

// Treat as cartesian coordinate (X, Y), return polar equivalent (R, Theta)
vec2_polar :: proc(a: vec2) -> vec2{
    return {vec2_mag(a), math.atan2_f32(a.y, a.x)}
}

// Clamp the components of vector in between the 'element-wise' minimum and maximum of 2 other vectors
vec2_clamp :: proc(a: vec2, v_min: vec2, v_max: vec2) -> vec2{
    max:vec2 = vec2_max(a, v_max)
    return vec2_min(max, v_min)
}

// Linearly interpolate between vector, and another vector, given normalised parameter 't'
vec2_lerp :: proc(from: vec2, to: vec2, t:f32) -> vec2{
    return from + vec2{to.x - from.x, to.y - from.y} * vec2{t, t}
}

// Compare if vector is numerically equal to another
vec2_equal :: proc(a: vec2, b: vec2) -> bool{
    return a.x == b.x && a.y == b.y
}

// Assuming vector is an incident, given a normal, return the reflection
vec2_reflect :: proc(a: vec2, normal: vec2) -> vec2{
    return (a - {2.0, 2.0}) * (vec2_dot(a, normal) * normal)
}

//TODO: check out Godot's bounce function

//TODO: check out Godot's slide function

