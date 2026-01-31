package geometry2d

import "core:math"

vec2 :: [2]f32


Vec2Sign::proc(p:vec2)->vec2{
    return {f32(Signf(p.x)), f32(Signf(p.y))}
}
Vec2Abs::proc(p:vec2)->vec2{
    return {Abs(p.x), Abs(p.y)}
}

// Returns rectangular area of vector
Vec2Area :: proc(a: vec2) -> f32{
    return a.x * a.y
}

// Returns magnitude of vector
Vec2Mag :: proc(a: vec2) -> f32{
    return sqrt(a.x * a.x + a.y * a.y)
}

// Returns magnitude squared of vector (useful for fast comparisons)
Vec2Mag2 :: proc(a: vec2) -> f32{
    return a.x * a.x + a.y * a.y
}

// Returns normalised version of vector
Vec2Norm :: proc(a: vec2) -> vec2{
    r:f32 = 1.0 / Vec2Mag(a)
    return {a.x * r, a.y * r}
}

// Returns vector at 90 degrees to this one
Vec2Perp :: proc(v: vec2) -> vec2{
    return {-v.y, v.x}
}

// Rounds both components down
Vec2Floor :: proc(v: vec2) -> vec2{
    return {math.floor_f32(v.x), math.floor_f32(v.y)}
}

// Rounds both components up
Vec2Ceil :: proc(v: vec2) -> vec2{
    return {math.ceil_f32(v.x), math.ceil_f32(v.y)}
}

// Returns 'element-wise' max of a vector and another vector
Vec2Max :: proc(a: vec2, b: vec2) -> vec2{
    return {math.max(a.x, b.x), math.max(a.y, b.y)}
}

// Returns 'element-wise' min of a vector and another vector
Vec2Min :: proc(a: vec2, b: vec2) -> vec2{
    return {math.min(a.x, b.x), math.min(a.y, b.y)}
}

// Calculates scalar dot product between a vector and another vector
Vec2Dot :: proc(a: vec2, b: vec2) -> f32{
    return a.x * b.x + a.y * b.y
}

// Calculates 'scalar' cross product between a vector and another vector (useful for winding orders)
Vec2Cross :: proc(a: vec2, b: vec2) -> f32{
    return a.x * b.y - a.y * b.x
}

// Treat as polar coordinate (R, Theta), return cartesian equivalent (X, Y)
Vec2Cartisian :: proc(a: vec2) -> vec2{
    return {math.cos_f32(a.y) * a.x, math.sin_f32(a.y) * a.x}
}

// Treat as cartesian coordinate (X, Y), return polar equivalent (R, Theta)
Vec2Polar :: proc(a: vec2) -> vec2{
    return {Vec2Mag(a), math.atan2_f32(a.y, a.x)}
}

// Clamp the components of vector in between the 'element-wise' minimum and maximum of 2 other vectors
Vec2Clamp :: proc(a: vec2, v_min: vec2, v_max: vec2) -> vec2{
    max:vec2 = Vec2Min(a, v_max)
    return Vec2Max(max, v_min)
}

// Linearly interpolate between vector, and another vector, given normalised parameter 't'
Vec2Lerp :: proc(from: vec2, to: vec2, t:f32) -> vec2{
    return from + vec2{to.x - from.x, to.y - from.y} * vec2{t, t}
}

// Compare if vector is numerically equal to another
Vec2Equal :: proc(a: vec2, b: vec2) -> bool{
    return a.x == b.x && a.y == b.y
}

// Assuming vector is an incident, given a normal, return the reflection
Vec2Reflect :: proc(a: vec2, normal: vec2) -> vec2{
    return (a - {2.0, 2.0}) * (Vec2Dot(a, normal) * normal)
}

//TODO: check out Godot's bounce function

//TODO: check out Godot's slide function

