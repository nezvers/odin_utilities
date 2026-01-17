package geometry2d

import math "core:math"

// Get intersection points where point intersects with point
IntersectsPointPoint::proc(p1:vec2, p2:vec2)->(points:[1]vec2, point_count:int){
    if (ContainsPointPoint(p1, p2)){
        points[0] = p1
        point_count = 1
        return
    }
    return
}

// Get intersection points where line segment intersects with point
IntersectsLinePoint::proc(l:Line, p:vec2)->(points:[1]vec2, point_count:int){
    if (ContainsLinePoint(l, p)){
        points[0] = p
        point_count = 1
        return
    }
    return
}


// Get intersection points where rectangle intersects with point
// TODO: Side line check felt weird
IntersectsRectanglePoint::proc(r:Rect, p:vec2)->(points:[1]vec2, point_count:int){
    if (ContainsRectanglePoint(r,p)){
        points[0] = p
        point_count = 1
        return
    }
    // if (ContainsLinePoint(RectTop, p)){
    //     return p
    // }
    // if (ContainsLinePoint(RectRight, p)){
    //     return p
    // }
    // if (ContainsLinePoint(RectBottom, p)){
    //     return p
    // }
    // if (ContainsLinePoint(RectLeft, p)){
    //     return p
    // }
    return
}

// Get intersection points where Circle intersects with point
IntersectsCirclePoint::proc(c:Circle, p:vec2)->(points:[1]vec2, point_count:int){
    if (Vec2Mag2(Vec2Abs(p - c.xy)) - (c.z * c.z) <= epsilon){
        points[0] = p
        point_count = 1
        return
    }
    return 
}

// Get intersection points where Triangle intersects with point
IntersectsTrianglePoint::proc(t:Triangle, p:vec2)->(points:[1]vec2, point_count:int){
    if overlaps_triangle_point(t, p){
        points[0] = p
        point_count = 1
        return
    }
    // if (ContainsLinePoint(TriangleSide(t, 0), p)){
    //     points[0] = p
    //     point_count = 1
    //     return
    // }
    // if (ContainsLinePoint(TriangleSide(t, 1), p)){
    //     points[0] = p
    //     point_count = 1
    //     return
    // }
    // if (ContainsLinePoint(TriangleSide(t, 2), p)){
    //     points[0] = p
    //     point_count = 1
    //     return
    // }
    return
}

// Get intersection points where point intersects with line segment
IntersectsPointLine::proc(p:vec2, l:Line)->(points:[1]vec2, point_count:int){
    return IntersectsLinePoint(l, p)
}

// Get intersection points where line segment intersects with line segment
IntersectsLineLine::proc(l1:Line, l2:Line)->(points:[1]vec2, point_count:int){
    line_vec1 := LineVector(l1)
    line_vec2 := LineVector(l2)
    cross_product:f32 = Vec2Cross(line_vec1, line_vec2)
    if (cross_product == 0) { return } // Parallel or Colinear TODO: Return two points

    inv_cross_prod := 1 / cross_product
    
    //rn = (b1b2 x b1a1)
    r1 := (l2.z - l2.x)
    r2 := (l1.y - l2.y)
    r3 := (l2.w - l2.y)
    r4 := (l1.x - l2.x)
    rn:f32 = (r1 * r2 - r3 * r4) * inv_cross_prod
    //sn = (a1a2 x b1a1)
    s1 := (l1.z - l1.x)
    s2 := (l1.y - l2.y)
    s3 := (l1.w - l1.y)
    s4 := (l1.x - l2.x)
    sn:f32 = (s1 * s2 - s3 * s4) * inv_cross_prod

    if (rn < 0. || rn > 1. || sn < 0. || sn > 1.){
        return
    }
    points[0] = l1.xy + rn * line_vec1
    point_count = 1
    return
}

// Get intersection points where rectangle intersects with line segment
IntersectsRectangleLine::proc(r:Rect, l:Line)->(points:[4]vec2, point_count:int){
    for i in 0..<4{
        _points, _point_count: = IntersectsLineLine(RectSide(r, u32(i)), l)
        if (_point_count == 0){
            continue
        }
        points[point_count] = _points[0]
        point_count += 1
    }

    if point_count > 1{
        point_count = FilterDuplicatePoints(points[0:point_count])
    }
    return
}

// Get intersection points where Triangle intersects with line segment
IntersectsTriangleLine::proc(t:Triangle, l:Line)->(points:[3]vec2, point_count:int){
    for i in 0..<3{
        _points, _point_count: = IntersectsLineLine(TriangleSide(t, u32(i)), l)
        if (_point_count > 0){
            points[point_count] = _points[0]
            point_count += 1
        }
    }

    if point_count > 1{
        point_count = FilterDuplicatePoints(points[0:point_count])
    }
    return
}

// Get intersection points where Circle intersects with line segment
IntersectsCircleLine::proc(c:Circle, l:Line)->(points:[2]vec2, point_count:int){
    closest_point_to_segment:vec2 = ClosestLinePoint(l, c.xy)
    if !overlaps_circle_point(c, closest_point_to_segment){
        return
    }
    
    // Compute point closest to the Circle on the line
    d:vec2 = LineVector(l)
    u_line:f32 = Vec2Dot(d, c.xy - l.xy) / Vec2Mag2(d)
    closest_point_to_line:vec2 = l.xy + u_line * d
    dist_to_line:f32 = Vec2Mag2(c.xy - closest_point_to_line)

    if Abs(dist_to_line - c.z * c.z) < epsilon{
        point_count += 1
        points[0] = closest_point_to_line 
        return
    }

    // Circle intersects the line
    length:f32 = sqrt(c.z * c.z - dist_to_line)

    p1:vec2 = closest_point_to_line + Vec2Norm(LineVector(l)) * length
    p2:vec2 = closest_point_to_line - Vec2Norm(LineVector(l)) * length

    if Vec2Mag2(p1 - ClosestLinePoint(l, p1)) < epsilon * epsilon{
        points[point_count] = p1
        point_count += 1
    }
    if Vec2Mag2(p2 - ClosestLinePoint(l, p2)) < epsilon * epsilon{
        points[point_count] = p2
        point_count += 1
    }
    
    if point_count > 1{
        point_count = FilterDuplicatePoints(points[0:point_count])
    }
    return
}

// Get intersection points where point intersects with rectangle
IntersectsPointRectangle::proc(p:vec2, r:Rect)->(points:[1]vec2, point_count:int){
    return IntersectsRectanglePoint(r, p)
}

// Get intersection points where line intersects with rectangle
IntersectsLineRectangle::proc(l:Line, r:Rect)->(points:[4]vec2, point_count:int){
    return IntersectsRectangleLine(r, l)
}

// Get intersection points where rectangle intersects with rectangle
IntersectsRectangleRectangle::proc(r1:Rect, r2:Rect)->(points:[8]vec2, point_count:int){
    for i in 0..<4{
        _points, _point_count: = IntersectsRectangleLine(r1, RectSide(r2, u32(i) ))
        for j in 0..<_point_count{
            points[point_count + j] = _points[j]
        }
        point_count += _point_count
    }
    
    if point_count > 1{
        point_count = FilterDuplicatePoints(points[0:point_count])
    }
    return
}

// Get intersection points where circle intersects with rectangle
IntersectsCircleRectangle::proc(c:Circle, r:Rect)->(points:[8]vec2, point_count:int){
    for i in 0..<4{
        _points, _point_count: = IntersectsCircleLine(c, RectSide(r, u32(i) ))
        for j in 0..<_point_count{
            points[point_count + j] = _points[j]
        }
        point_count += _point_count
    }
    
    if point_count > 1{
        point_count = FilterDuplicatePoints(points[0:point_count])
    }
    return
}

// Get intersection points where triangle intersects with rectangle
IntersectsTriangleRectangle::proc(t:Triangle, r:Rect)->(points:[8]vec2, point_count:int){
    for i in 0..<4{
        _points, _point_count: = IntersectsTriangleLine(t, RectSide(r, u32(i) ))
        for j in 0..<_point_count{
            points[point_count + j] = _points[j]
        }
        point_count += _point_count
    }
    
    if point_count > 1{
        point_count = FilterDuplicatePoints(points[0:point_count])
    }
    return
}

// Get intersection points where point intersects with circle
IntersectsPointCircle:: proc (p:vec2, c:Circle)->(points:[1]vec2, point_count:int){
    return IntersectsCirclePoint(c, p)
}

// Get intersection points where line segment intersects with circle
IntersectsLineCircle:: proc (l:Line, c:Circle)->(points:[2]vec2, point_count:int){
    return IntersectsCircleLine(c, l)
}

// Get intersection points where rectangle intersects with circle
IntersectsRectangleCircle::proc(r:Rect, c:Circle)->(points:[8]vec2, point_count:int){
    return IntersectsCircleRectangle(c, r)
}

// Get intersection points where circle intersects with circle
IntersectsCircleCircle::proc(c1:Circle, c2:Circle)->(points:[2]vec2, point_count:int){
    if c1.xy == c2.xy{return}

    between: = c2.xy - c1.xy
    dist2:f32 = Vec2Mag(between)
    radius_sum:f32 = c1.z + c2.z

    // circles are too far apart to be touching.
    if dist2 > radius_sum * radius_sum {return}

    // one circle is inside of the other, they can't be intersecting.
    if (ContainsCircleCircle(c1, c2) || ContainsCircleCircle(c2, c1)) {return}

    between_norm: = Vec2Norm(between)
    // circles are touching at exactly 1 point
    if (dist2 == radius_sum) {
        points[0] = c1.xy + between_norm * c1.z
        point_count = 1
        return
    }

    // otherwise they're touching at 2 points.
    dist: = sqrt(dist2)
    dist_cc: = (dist2 + c1.z * c1.z - c2.z * c2.z)/(2 * dist)
    chord_center: = c1.xy + between_norm * dist_cc
    half_cord: = Vec2Perp(between_norm) * sqrt(c1.z * c1.z - dist_cc * dist_cc)

    points[0] = chord_center + half_cord
    points[1] = chord_center - half_cord
    point_count = 2
    return
}

// Get intersection points where triangle intersects with circle
IntersectsTriangleCircle::proc(t:Triangle, c:Circle)->(points:[6]vec2, point_count:int){
    for i in 0..<3{
        _points, _point_count: = IntersectsCircleLine(c, TriangleSide(t, u32(i) ))
        for j in 0..<_point_count{
            points[point_count + j] = _points[j]
        }
        point_count += _point_count
    }
    
    if point_count > 1{
        point_count = FilterDuplicatePoints(points[0:point_count])
    }
    return
}

// Get intersection points where point intersects with triangle
IntersectsPointTriangle::proc(p:vec2, t:Triangle)->(points:[1]vec2, point_count:int){
    return IntersectsTrianglePoint(t, p)
}

// Get intersection points where line segment intersects with triangle
IntersectsLineTriangle::proc(l:Line, t:Triangle)->(points:[3]vec2, point_count:int){
    return IntersectsTriangleLine(t, l)
}

// Get intersection points where rectangle intersects with triangle
IntersectsRectangleTriangle::proc(r:Rect, t:Triangle)->(points:[8]vec2, point_count:int){
    return IntersectsTriangleRectangle(t, r)
}

// Get intersection points where circle intersects with triangle
IntersectsCircleTriangle::proc(c:Circle, t:Triangle)->(points:[6]vec2, point_count:int){
    return IntersectsTriangleCircle(t, c)
}

// Get intersection points where triangle intersects with triangle
IntersectsTriangleTriangle::proc(t1:Triangle, t2:Triangle)->(points:[6]vec2, point_count:int){
    for i in 0..<3{
        _points, _point_count: = IntersectsTriangleLine(t1, TriangleSide(t2, u32(i) ))
        for j in 0..<_point_count{
            points[point_count + j] = _points[j]
        }
        point_count += _point_count
    }
    
    if point_count > 1{
        point_count = FilterDuplicatePoints(points[0:point_count])
    }
    return
}

// RAYS =================================================================================================================

// return intersection point (if it exists) of a ray and a ray
IntersectsRayRay::proc(r1:Ray, r2:Ray)->(points:[1]vec2, point_count:int){
    origin_diff: = r2.xy - r1.xy
    cp1: = Vec2Cross(r1.zw, r2.zw)
    cp2: = Vec2Cross(origin_diff, r2.zw)

    if cp1 == 0{
        if cp2 == 0{
            point_count = 1
            points[0] = r1.xy
            return
        }
        // no touch
        return
    }

    cp3: = Vec2Cross(origin_diff, r1.zw)
    t1: = cp2 / cp1 // distance along q1 to intersection
    t2: = cp3 / cp1 // distance along q2 to intersection

    if t1 >= 0 && t2 >= 0{
        // Intersection, both rays positive
        point_count = 1
        points[0] = r1.xy + r1.zw * t1
        return
    }
    // Intersection, but behind a rays origin, so not really an intersection in context
    return
}

// return intersection point (if it exists) of a ray and a point
IntersectsRayPoint::proc(r:Ray, p:vec2)->(points:[1]vec2, point_count:int){
    l:Line = {r.x, r.y, r.x + r.z, r.y + r.w}
    
    if LineSide(l, p) == 0{
        points[0] = p
        point_count = 1
        return
    }
    return
}


IntersectsPointRay::proc(p:vec2, r:Ray)->(points:[1]vec2, point_count:int){
    points, point_count = IntersectsRayPoint(r, p)
    return
}

// return intersection point (if it exists) of a ray and a line segment
IntersectsRayLine::proc(r:Ray, l:Line)->(points:[1]vec2, point_count:int){
    line_direction: = LineVector(l)
    origin_diff: = l.xy - r.xy
    cp1: = Vec2Cross(r.zw, line_direction)
    cp2: = Vec2Cross(origin_diff, line_direction)

    if cp1 == 0{
        if cp2 == 0{
            point_count = 1
            points[0] = r.xy
            return
        }
        // no touch
        return
    }

    cp3: = Vec2Cross(origin_diff, r.zw)
    t1: = cp2 / cp1 // distance along q1 to intersection
    t2: = cp3 / cp1 // distance along q2 to intersection

    if t1 >= 0 && t2 >= 0 && t2 <= 1 {
        // Intersection, both rays positive
        point_count = 1
        points[0] = r.xy + r.zw * t1
        return
    }
    // Intersection, but behind a rays origin, so not really an intersection in context
    // TODO: filter duplicates?
    return
}
IntersectsLineRay::proc(l:Line, r:Ray)->(points:[1]vec2, point_count:int){
    points, point_count = IntersectsRayLine(r, l)
    return
}

// Get intersection points where a ray intersects a circle
IntersectsRayCircle::proc(r:Ray, c:Circle)->(points:[2]vec2, point_count:int){
    A: = Vec2Mag2(r.zw)
    B: = 2.0 * (Vec2Dot(r.xy, r.zw) - Vec2Dot(c.xy, r.zw))
    C: = Vec2Mag2(c.xy) + Vec2Mag2(r.xy) - (2.0 * c.x * r.x) - (2.0 * c.y * r.y) - (c.z  * c.z)
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
            points[0] = r.xy + r.zw * s2
            point_count = 1
            return
        }
        if s2 < 0{
            points[0] = r.xy + r.zw * s1
            point_count = 1
            return
        }
        min_s: = math.min(s1, s2)
        max_s: = math.max(s1, s2)

        points[0] = r.xy + r.zw * min_s
        points[1] = r.xy + r.zw * max_s
        point_count = 2
        return
    }
    return
}
IntersectsCircleRay::proc(c:Circle, r:Ray)->(points:[2]vec2, point_count:int){
    points, point_count = IntersectsRayCircle(r, c)
    return
}

// Get intersection points where a ray intersects a rectangle
IntersectsRayRectangle::proc(r:Ray, rect:Rect)->(points:[2]vec2, point_count:int){
    for i in 0..<4{
        _points, _point_count: = IntersectsRayLine(r, RectSide(rect, u32(i)), )
        if _point_count > 0{
            assert(point_count < 2)
            points[point_count] = _points[0]
            point_count += 1
        }
    }
    
    if point_count > 1{
        point_count = FilterDuplicatePoints(points[0:point_count])
    }
    return
}
IntersectsRectangleRay::proc(rect:Rect, r:Ray)->(points:[2]vec2, point_count:int){
    points, point_count = IntersectsRayRectangle(r, rect)
    return
}

// Get intersection points where a ray intersects a triangle
IntersectsRayTriangle::proc(r:Ray, t:Triangle)->(points:[2]vec2, point_count:int){
    for i in 0..<3{
        _points, _point_count: = IntersectsRayLine(r, TriangleSide(t, u32(i)), )
        if _point_count > 0{
            assert(point_count < 2, "Too many intersection points")
            points[point_count] = _points[0]
            point_count += 1
        }
    }
    
    if point_count > 1{
        point_count = FilterDuplicatePoints(points[0:point_count])
    }
    return
}


IntersectsTriangleRay::proc(t:Triangle, r:Ray)->(points:[2]vec2, point_count:int){
    points, point_count = IntersectsRayTriangle(r, t)
    return
}