package geometry2d

import math "core:math"

// project a circle, onto a circle, via a ray (i.e. how far along the ray can the circle travel until it contacts the other circle?)
project_circle_circle::proc(c1:Circle, c2:Circle, r:Ray)->(end_position:vec2, travel:f32){
    // Inspired by https://math.stackexchange.com/a/929240

    A: = Vec2Mag2(r.zw)
    B: = 2.0 * (Vec2Dot(r.xy, r.zw) - Vec2Dot(c2.xy, r.zw))
    C: = Vec2Mag2(c2.xy) + Vec2Mag2(r.xy) - (2.0 * c2.x * r.x) - (2.0 * c2.y * r.y) - ((c1.z + c2.z) * (c1.z + c2.z))
    D: = B * B - 4.0 * A * C

    if D < 0.0{
        return // null
    } else {
        sD: = sqrt(D)
        s1: = (-B + sD) / (2.0 * A)
        s2: = (-B - sD) / (2.0 * A)

        if s1 < 0 && s2 < 0{
            return // null
        }
        if s1 < 0{
            travel = s2
            end_position = r.xy + r.zw * travel
            return
        }
        if s2 < 0{
            travel = s1
            end_position = r.xy + r.zw * travel
            return
        }
        travel = math.min(s1, s2)
        end_position = r.xy + r.zw * travel
        return
    }

    return
}

// project a circle, onto a point, via a ray (i.e. how far along the ray can the circle travel until it contacts the point?)
project_circle_point::proc(c:Circle, p:vec2, r:Ray)->(end_position:vec2, travel:f32){
    return project_circle_circle(c, {p.x, p.y, 0.0}, r)
}

// project a circle, onto a line segment, via a ray
project_circle_line::proc(c:Circle, l:Line, r:Ray)->(end_position:vec2, travel:f32){
    // Treat line segment as capsule with radius that of the circle
    // and treat the circle as a point

    // First do we hit ends of line segment, inflated to be circles
    
    
    return
}