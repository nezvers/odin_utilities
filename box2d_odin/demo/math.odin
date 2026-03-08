package demo

lerp :: proc(a, b: f32, t:f32)->f32 {
    return a + (b - a) * t
}