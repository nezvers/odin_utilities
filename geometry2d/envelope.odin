package geometry2d

import math "core:math"

// Return circle that fully encapsulates a point
envelope_circle_point::proc(p:vec2)->Circle{
    return {p.x, p.y, 0.0}
}

// Return circle that fully encapsulates a line
envelope_circle_line::proc(l:Line)->Circle{
    p: = line_point_mult(l, 0.5)
    return {p.x, p.y, vec2_mag(line_vector(l)) * 0.5}
}

// Return circle that fully encapsulates a rectangle
envelope_circle_rectangle::proc(r:Rect)->Circle{
    l:Line = {r.x, r.y, r.x + r.z, r.y + r.w}
    return envelope_circle_line(l)
}

// Return circle that fully encapsulates a circle
envelope_circle_circle::proc(c:Circle)->Circle{
    return c
}

// Return circle that fully encapsulates a triangle
envelope_circle_triangle::proc(t:Triangle)->Circle{
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