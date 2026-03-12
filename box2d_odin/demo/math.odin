package demo

Lerp :: proc(a, b: f32, t:f32)->f32 {
    return a + (b - a) * t
}

Sign :: proc(a: $T)->T {
    return a > 0 ? 1 : a < 0 ? -1 : 0
}