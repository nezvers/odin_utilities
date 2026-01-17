package geometry2d

import math "core:math"

// project a circle, onto a circle, via a ray (i.e. how far along the ray can the circle travel until it contacts the other circle?)
ProjectCircleCircle::proc(c1:Circle, c2:Circle, r:Ray)->(end_position:vec2, travel:f32){
    // Inspired by https://math.stackexchange.com/a/929240
    // desmos - https://www.desmos.com/calculator/0kadyeba6y

    A: = Vec2Mag2(r.zw)
    B: = 2.0 * (Vec2Dot(r.xy, r.zw) - Vec2Dot(c2.xy, r.zw))
    C: = Vec2Mag2(c2.xy) + Vec2Mag2(r.xy) - (2.0 * c2.x * r.x) - (2.0 * c2.y * r.y) - ((c1.z + c2.z) * (c1.z + c2.z))
    D: = B * B - 4.0 * A * C

    if D < 0.0{
        travel = 1.0
        end_position = r.xy + r.zw * travel
        return // null
    } else {
        sD: = sqrt(D)
        s1: = (-B + sD) / (2.0 * A)
        s2: = (-B - sD) / (2.0 * A)

        if s1 < 0 && s2 < 0{
            travel = 1.0
            end_position = r.xy + r.zw * travel
            return // null
        }
        if s1 < 0 {
            travel = s2
            end_position = r.xy + r.zw * travel
            return
        }
        if s2 < 0 {
            travel = s1
            end_position = r.xy + r.zw * travel
            return
        }
        travel = math.min(s1, s2)
        end_position = r.xy + r.zw * travel
        return
    }
}

// project a circle, onto a point, via a ray (i.e. how far along the ray can the circle travel until it contacts the point?)
ProjectCirclePoint::proc(c:Circle, p:vec2, r:Ray)->(end_position:vec2, travel:f32){
    return ProjectCircleCircle(c, {p.x, p.y, 0.0}, r)
}

// project a circle, onto a line segment, via a ray
ProjectCircleLine::proc(c:Circle, l:Line, r:Ray)->(end_position:vec2, travel:f32){
    // Treat line segment as capsule with radius that of the circle
    // and treat the circle as a point

    // First do we hit ends of line segment, inflated to be circles
    hits_circle_start, point_count1: = IntersectsRayCircle(r, CircleNew(l.xy, c.r))
    hits_circle_end, point_count2: = IntersectsRayCircle(r, CircleNew(l.zw, c.r))
    
    // Now create two line segments in parallel to the original, that join
    // up the end circles to form the sides of the capsule
    displace:vec2 = Vec2Perp(Vec2Norm(LineVector(l))) * c.r
    hits_side1, point_count3: = IntersectsRayLine(r, LineNew(l.xy + displace, l.zw + displace))
    hits_side2, point_count4: = IntersectsRayLine(r, LineNew(l.xy - displace, l.zw - displace))

    // Bring the multitude of points to one place
    intersection_buffer:[6]vec2
    intersection_count:int = 0
    AppendPoints(intersection_buffer[:], &intersection_count, hits_circle_start[0:point_count1])
    AppendPoints(intersection_buffer[:], &intersection_count, hits_circle_end[0:point_count2])
    AppendPoints(intersection_buffer[:], &intersection_count, hits_side1[0:point_count3])
    AppendPoints(intersection_buffer[:], &intersection_count, hits_side2[0:point_count4])

    if intersection_count == 0 {
        travel = 1.0
        end_position = r.xy + r.zw * travel
        return
    }

    end_position = GetClosestPoint(intersection_buffer[:intersection_count], r.xy)
    travel = Vec2Mag(r.xy - end_position) / Vec2Mag(r.zw)
    assert(travel <= 1.0) // I assume intersection points are along Ray trajectory
    return
}
