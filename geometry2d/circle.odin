package geometry2d

// x, y, radius
Circle:: [3]f32

CircleNew::proc(pos:vec2, radius:f32)->Circle{
    return {pos.x, pos.y, radius}
}

// Get area of Circle
CircleArea::proc(c:Circle)->f32{
    return pi_f32 * c.z * c.z
}

// Get circumference of Circle
CirclePerimeter::proc(c:Circle)->f32{
    return tau_f32 * c.z
}

// Get circumference of Circle
CircleCircumference::proc(c:Circle)->f32{
    return CirclePerimeter(c)
}