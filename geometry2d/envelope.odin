package geometry2d

import math "core:math"
import "core:testing"

// Return circle that fully encapsulates a point
EnvelopeCirclePoint::proc(p:vec2)->Circle{
    return {p.x, p.y, 0.0}
}

// Return circle that fully encapsulates a line
EnvelopeCircleLine::proc(l:Line)->Circle{
    p: = LinePointMult(l, 0.5)
    return {p.x, p.y, Vec2Mag(LineVector(l)) * 0.5}
}

// Return circle that fully encapsulates a rectangle
EnvelopeCircleRectangle::proc(r:Rect)->Circle{
    l:Line = {r.x, r.y, r.x + r.z, r.y + r.w}
    return EnvelopeCircleLine(l)
}

// Return circle that fully encapsulates a circle
EnvelopeCircleCircle::proc(c:Circle)->Circle{
    return c
}

// Return circle that fully encapsulates a triangle
EnvelopeCircleTriangle::proc(t:Triangle)->Circle{
    circumcenter:vec2
    D:f64 = f64(2 * (t[0].x * (t[1].y - t[2].y) + t[1].x * (t[2].y - t[0].y) + t[2].x * (t[0].y - t[1].y)))
    circumcenter.x = f32(f64( \
        (t[0].x * t[0].x + t[0].y * t[0].y) * (t[1].y - t[2].y) + \
        (t[1].x * t[1].x + t[1].y * t[1].y) * (t[2].y - t[0].y) + \
        (t[2].x * t[2].x + t[2].y * t[2].y) * (t[0].y - t[1].y) ) / D)
    circumcenter.y = f32(f64( \
        (t[0].x * t[0].x + t[0].y * t[0].y) * (t[2].x - t[1].x) + \
        (t[1].x * t[1].x + t[1].y * t[1].y) * (t[0].x - t[2].x) + \
        (t[2].x * t[2].x + t[2].y * t[2].y) * (t[1].x - t[0].x) ) / D)
    
    r:f64 = 0
    for _ in 0..< 3 {
        h:f64 = math.hypot_f64(f64(circumcenter.x - t[0].x), f64(circumcenter.y - t[0].y))
        if h > r {
            r = h
        }
    }
    return {circumcenter.x, circumcenter.y, f32(r)}
}

// --- Tests ---

@(test)
test_envelope_circles :: proc(t: ^testing.T) {
    testing.expect_value(t, EnvelopeCirclePoint({2, 3}), Circle{2, 3, 0})
    testing.expect_value(t, EnvelopeCircleLine(LineNew({0, 0}, {6, 8})), Circle{3, 4, 5})
    testing.expect_value(t, EnvelopeCircleRectangle(Rect{0, 0, 6, 8}), Circle{3, 4, 5})
    testing.expect_value(t, EnvelopeCircleCircle(Circle{1, 2, 3}), Circle{1, 2, 3})

    // a right triangle: the hypotenuse is the diameter
    around: Circle = EnvelopeCircleTriangle(Triangle{{0, 0}, {6, 0}, {0, 8}})
    testing.expect(t, abs(around.x - 3) < 1e-3 && abs(around.y - 4) < 1e-3 && abs(around.z - 5) < 1e-3)
}
