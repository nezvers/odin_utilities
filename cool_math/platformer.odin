package cool_math

import "core:math"

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