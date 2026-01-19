package geometry2d

import math "core:math"

// Projects Shape A along a ray, until and if it contacts shape B. If it never contacts
// then nothing is returned. If it does contact the closest position Shape A can be to
// Shape B is returned without the shapes overlapping
ProjectResult::struct {
    point:vec2,
    hit:bool,
    // travel:f32,
}

// project a circle, onto a circle, via a ray (i.e. how far along the ray can the circle travel until it contacts the other circle?)
ProjectCircleCircle::proc(c1:Circle, c2:Circle, r:Ray)->(result:ProjectResult) {
    // Inspired by https://math.stackexchange.com/a/929240
    // desmos - https://www.desmos.com/calculator/0kadyeba6y

    ray_mag2: = Vec2Mag2(r.zw)
    B: = 2.0 * (Vec2Dot(r.xy, r.zw) - Vec2Dot(c2.xy, r.zw))
    C: = Vec2Mag2(c2.xy) + Vec2Mag2(r.xy) - (2.0 * c2.x * r.x) - (2.0 * c2.y * r.y) - ((c1.z + c2.z) * (c1.z + c2.z))
    D: = B * B - 4.0 * ray_mag2 * C

    if D < 0.0 {
        // TODO: test travel
        return // null
    } else {
        sD: = sqrt(D)
        s1: = (-B + sD) / (2.0 * ray_mag2)
        s2: = (-B - sD) / (2.0 * ray_mag2)

        if s1 < 0 && s2 < 0 {
            // TODO: test travel
            return // null
        }
        if s1 < 0 {
            // result.travel = s2
            result.point = r.xy + r.zw * s2
            result.hit = true
            return
        }
        if s2 < 0 {
            // result.travel = s1
            result.point = r.xy + r.zw * s1
            result.hit = true
            return
        }
        // result.travel = math.min(s1, s2)
        travel: = math.min(s1, s2)
        result.point = r.xy + r.zw * travel
        result.hit = true
        return
    }
}

// project a circle, onto a point, via a ray (i.e. how far along the ray can the circle travel until it contacts the point?)
ProjectCirclePoint::proc(c:Circle, p:vec2, r:Ray)->(result:ProjectResult){
    return ProjectCircleCircle(c, {p.x, p.y, 0.0}, r)
}

// project a circle, onto a line segment, via a ray
ProjectCircleLine::proc(c:Circle, l:Line, r:Ray)->(result:ProjectResult){
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
        // result.travel = 1.0
        // result.point = r.xy + r.zw * result.travel
        return
    }

    result.point = GetClosestPoint(intersection_buffer[:intersection_count], r.xy)
    // result.travel = Vec2Mag(r.xy - result.point) / Vec2Mag(r.zw)
    result.hit = true
    // assert(result.travel <= 1.0) // I assume intersection points are along Ray trajectory
    return
}

ProjectCircleRectangle::proc(c:Circle, rect:Rect, r:Ray)->(result:ProjectResult){
    top_result: = ProjectCircleLine(c, RectTop(rect), r)
    bottom_result: = ProjectCircleLine(c, RectBottom(rect), r)
    left_result: = ProjectCircleLine(c, RectLeft(rect), r)
    right_result: = ProjectCircleLine(c, RectRight(rect), r)

    intersection_buffer:[6]vec2
    intersection_count:int = 0
    if top_result.hit {
        AppendPoints(intersection_buffer[:], &intersection_count, {top_result.point})
    }
    if bottom_result.hit {
        AppendPoints(intersection_buffer[:], &intersection_count, {bottom_result.point})
    }
    if left_result.hit {
        AppendPoints(intersection_buffer[:], &intersection_count, {left_result.point})
    }
    if right_result.hit {
        AppendPoints(intersection_buffer[:], &intersection_count, {right_result.point})
    }

    if intersection_count == 0 {
        // result.travel = 1.0
        // result.point = r.xy + r.zw * result.travel
        return
    }

    result.point = GetClosestPoint(intersection_buffer[:intersection_count], r.xy)
    // result.travel = Vec2Mag(r.xy - result.point) / Vec2Mag(r.zw)
    result.hit = true
    // assert(result.travel <= 1.0) // I assume intersection points are along Ray trajectory
    return
}

ProjectCircleTriangle::proc(c:Circle, t:Triangle, r:Ray)->(result:ProjectResult){
    side_result1: = ProjectCircleLine(c, TriangleSide(t, 0), r)
    side_result2: = ProjectCircleLine(c, TriangleSide(t, 0), r)
    side_result3: = ProjectCircleLine(c, TriangleSide(t, 0), r)

    intersection_buffer:[6]vec2
    intersection_count:int = 0
    if side_result1.hit {
        AppendPoints(intersection_buffer[:], &intersection_count, {side_result1.point})
    }
    if side_result2.hit {
        AppendPoints(intersection_buffer[:], &intersection_count, {side_result2.point})
    }
    if side_result3.hit {
        AppendPoints(intersection_buffer[:], &intersection_count, {side_result3.point})
    }
    
    if intersection_count == 0 {
        // result.travel = 1.0
        // result.point = r.xy + r.zw * result.travel
        return
    }

    result.point = GetClosestPoint(intersection_buffer[:intersection_count], r.xy)
    // result.travel = Vec2Mag(r.xy - result.point) / Vec2Mag(r.zw)
    result.hit = true
    // assert(result.travel <= 1.0) // I assume intersection points are along Ray trajectory
    return
}