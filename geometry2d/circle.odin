package geometry2d

// x, y, radius
Circle:: [3]f32

circle_new::proc(pos:vec2, radius:f32)->Circle{
    return {pos.x, pos.y, radius}
}

// Get area of Circle
circle_area::proc(c:Circle)->f32{
    return pi_f32 * c.z * c.z
}

// Get circumference of Circle
circle_perimeter::proc(c:Circle)->f32{
    return tau_f32 * c.z
}

// Get circumference of Circle
circle_circumference::proc(c:Circle)->f32{
    return circle_perimeter(c)
}