package geometry2d
import "core:testing"

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

// --- Tests ---

@(test)
test_circle_helpers :: proc(t: ^testing.T) {
    c: Circle = CircleNew({1, 2}, 3)
    testing.expect_value(t, c, Circle{1, 2, 3})
    testing.expect(t, abs(CircleArea(c) - 9 * pi_f32) < 1e-4)
    testing.expect(t, abs(CirclePerimeter(c) - 6 * pi_f32) < 1e-4)
    testing.expect_value(t, CircleCircumference(c), CirclePerimeter(c))
}
