package geometry2d

import math "core:math"

// Get intersection points where point intersects with point
intersects_point_point::proc(p1:vec2, p2:vec2)->(points:[1]vec2, point_count:int){
    if (contains_point_point(p1, p2)){
        points[0] = p1
        point_count = 1
        return
    }
    return
}

// Get intersection points where line segment intersects with point
intersects_line_point::proc(l:Line, p:vec2)->(points:[1]vec2, point_count:int){
    if (contains_line_point(l, p)){
        points[0] = p
        point_count = 1
        return
    }
    return
}


// Get intersection points where rectangle intersects with point
// TODO: Side line check felt weird
intersects_rectangle_point::proc(r:Rect, p:vec2)->(points:[1]vec2, point_count:int){
    if (contains_rectangle_point(r,p)){
        points[0] = p
        point_count = 1
        return
    }
    // if (contains_line_point(rect_top, p)){
    //     return p
    // }
    // if (contains_line_point(rect_right, p)){
    //     return p
    // }
    // if (contains_line_point(rect_bottom, p)){
    //     return p
    // }
    // if (contains_line_point(rect_left, p)){
    //     return p
    // }
    return
}

// Get intersection points where Circle intersects with point
intersects_circle_point::proc(c:Circle, p:vec2)->(points:[1]vec2, point_count:int){
    if (vec2_mag2(vec2_abs(p - c.xy)) - (c.z * c.z) <= epsilon){
        points[0] = p
        point_count = 1
        return
    }
    return 
}

// Get intersection points where Triangle intersects with point
intersects_triangle_point::proc(t:Triangle, p:vec2)->(points:[1]vec2, point_count:int){
    if overlaps_triangle_point(t, p){
        points[0] = p
        point_count = 1
        return
    }
    // if (contains_line_point(triangle_side(t, 0), p)){
    //     points[0] = p
    //     point_count = 1
    //     return
    // }
    // if (contains_line_point(triangle_side(t, 1), p)){
    //     points[0] = p
    //     point_count = 1
    //     return
    // }
    // if (contains_line_point(triangle_side(t, 2), p)){
    //     points[0] = p
    //     point_count = 1
    //     return
    // }
    return
}

// Get intersection points where point intersects with line segment
intersects_point_line::proc(p:vec2, l:Line)->(points:[1]vec2, point_count:int){
    return intersects_line_point(l, p)
}

// Get intersection points where line segment intersects with line segment
intersects_line_line::proc(l1:Line, l2:Line)->(points:[1]vec2, point_count:int){
    rd:f32 = vec2_cross(line_vector(l1), line_vector(l2))
    if (rd == 0){return}

    rd = 1 / rd
    rn:f32 = ((l2.z - l2.x) * (l1.y - l2.y) - (l2.w - l2.y) * (l1.x - l2.x)) * rd
    sn:f32 = ((l1.z - l1.x) * (l1.y - l2.y) - (l1.w - l1.y) * (l1.x - l2.x)) * rd

    if (rn < 0 || rn > 1 || sn < 0 || sn > 1){
        return
    }
    points[0] = l1.xy + rn * line_vector(l1)
    point_count = 1
    return
}

// Get intersection points where rectangle intersects with line segment
intersects_rectangle_line::proc(r:Rect, l:Line)->(points:[4]vec2, point_count:int){
    for i in 0..<4{
        _points, _point_count: = intersects_line_line(rect_side(r, u32(i)), l)
        if (_point_count > 0){
            points[point_count] = _points[0]
            point_count += 1
        }
    }
    if point_count > 1{
        point_count = filter_duplicate_points(points[0:point_count])
    }
    return
}

// Get intersection points where Triangle intersects with line segment
intersects_triangle_line::proc(t:Triangle, l:Line)->(points:[3]vec2, point_count:int){
    for i in 0..<3{
        _points, _point_count: = intersects_line_line(triangle_side(t, u32(i)), l)
        if (_point_count > 0){
            points[point_count] = _points[0]
            point_count += 1
        }
    }
    if point_count > 1{
        point_count = filter_duplicate_points(points[0:point_count])
    }
    // TODO: filter duplicates?
    return
}

// Get intersection points where Circle intersects with line segment
intersects_circle_line::proc(c:Circle, l:Line)->(points:[2]vec2, point_count:int){
    closest_point_to_segment:vec2 = closest_line_point(l, c.xy)
    if !overlaps_circle_point(c, closest_point_to_segment){
        return
    }
    
    // Compute point closest to the Circle on the line
    d:vec2 = line_vector(l)
    u_line:f32 = vec2_dot(d, c.xy - l.xy) / vec2_mag2(d)
    closest_point_to_line:vec2 = l.xy + u_line * d
    dist_to_line:f32 = vec2_mag2(c.xy - closest_point_to_line)

    if abs(dist_to_line - c.z * c.z) < epsilon{
        point_count += 1
        points[0] = closest_point_to_line 
        return
    }

    // Circle intersects the line
    length:f32 = sqrt(c.z * c.z - dist_to_line)

    p1:vec2 = closest_point_to_line + vec2_norm(line_vector(l)) * length
    p2:vec2 = closest_point_to_line - vec2_norm(line_vector(l)) * length

    if vec2_mag2(p1 - closest_line_point(l, p1)) < epsilon * epsilon{
        points[point_count] = p1
        point_count += 1
    }
    if vec2_mag2(p2 - closest_line_point(l, p2)) < epsilon * epsilon{
        points[point_count] = p2
        point_count += 1
    }
    
    if point_count > 1{
        point_count = filter_duplicate_points(points[0:point_count])
    }
    // TODO: filter duplicates?
    return
}

// Get intersection points where point intersects with rectangle
intersects_point_rectangle::proc(p:vec2, r:Rect)->(points:[1]vec2, point_count:int){
    return intersects_rectangle_point(r, p)
}

// Get intersection points where line intersects with rectangle
intersects_line_rectangle::proc(l:Line, r:Rect)->(points:[4]vec2, point_count:int){
    return intersects_rectangle_line(r, l)
}

// Get intersection points where rectangle intersects with rectangle
intersects_rectangle_rectangle::proc(r1:Rect, r2:Rect)->(points:[8]vec2, point_count:int){
    for i in 0..<4{
        _points, _point_count: = intersects_rectangle_line(r1, rect_side(r2, u32(i) ))
        for j in 0..<_point_count{
            points[point_count + j] = _points[j]
        }
        point_count += _point_count
    }
    // TODO: filter duplicates?
    return
}

// Get intersection points where circle intersects with rectangle
intersects_circle_rectangle::proc(c:Circle, r:Rect)->(points:[8]vec2, point_count:int){
    for i in 0..<4{
        _points, _point_count: = intersects_circle_line(c, rect_side(r, u32(i) ))
        for j in 0..<_point_count{
            points[point_count + j] = _points[j]
        }
        point_count += _point_count
    }
    // TODO: filter duplicates?
    return
}

// Get intersection points where triangle intersects with rectangle
intersects_triangle_rectangle::proc(t:Triangle, r:Rect)->(points:[8]vec2, point_count:int){
    for i in 0..<4{
        _points, _point_count: = intersects_triangle_line(t, rect_side(r, u32(i) ))
        for j in 0..<_point_count{
            points[point_count + j] = _points[j]
        }
        point_count += _point_count
    }
    // TODO: filter duplicates?
    return
}

// Get intersection points where point intersects with circle
intersects_point_circle:: proc (p:vec2, c:Circle)->(points:[1]vec2, point_count:int){
    return intersects_circle_point(c, p)
}

// Get intersection points where line segment intersects with circle
intersects_line_circle:: proc (l:Line, c:Circle)->(points:[2]vec2, point_count:int){
    return intersects_circle_line(c, l)
}

// Get intersection points where rectangle intersects with circle
intersects_rectangle_circle::proc(r:Rect, c:Circle)->(points:[8]vec2, point_count:int){
    return intersects_circle_rectangle(c, r)
}

// Get intersection points where circle intersects with circle
intersects_circle_circle::proc(c1:Circle, c2:Circle)->(points:[2]vec2, point_count:int){
    if c1.xy == c2.xy{return}

    between: = c2.xy - c1.xy
    dist2:f32 = vec2_mag(between)
    radius_sum:f32 = c1.z + c2.z

    // circles are too far apart to be touching.
    if dist2 > radius_sum * radius_sum {return}

    // one circle is inside of the other, they can't be intersecting.
    if (contains_circle_circle(c1, c2) || contains_circle_circle(c2, c1)) {return}

    between_norm: = vec2_norm(between)
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
    half_cord: = vec2_perp(between_norm) * sqrt(c1.z * c1.z - dist_cc * dist_cc)

    points[0] = chord_center + half_cord
    points[1] = chord_center - half_cord
    point_count = 2
    return
}

// Get intersection points where triangle intersects with circle
intersects_triangle_circle::proc(t:Triangle, c:Circle)->(points:[6]vec2, point_count:int){
    for i in 0..<3{
        _points, _point_count: = intersects_circle_line(c, triangle_side(t, u32(i) ))
        for j in 0..<_point_count{
            points[point_count + j] = _points[j]
        }
        point_count += _point_count
    }
    // TODO: filter duplicates?
    return
}

// Get intersection points where point intersects with triangle
intersects_point_triangle::proc(p:vec2, t:Triangle)->(points:[1]vec2, point_count:int){
    return intersects_triangle_point(t, p)
}

// Get intersection points where line segment intersects with triangle
intersects_line_triangle::proc(l:Line, t:Triangle)->(points:[3]vec2, point_count:int){
    return intersects_triangle_line(t, l)
}

// Get intersection points where rectangle intersects with triangle
intersects_rectangle_triangle::proc(r:Rect, t:Triangle)->(points:[8]vec2, point_count:int){
    return intersects_triangle_rectangle(t, r)
}

// Get intersection points where circle intersects with triangle
intersects_circle_triangle::proc(c:Circle, t:Triangle)->(points:[6]vec2, point_count:int){
    return intersects_triangle_circle(t, c)
}

// Get intersection points where triangle intersects with triangle
intersects_triangle_triangle::proc(t1:Triangle, t2:Triangle)->(points:[6]vec2, point_count:int){
    for i in 0..<3{
        _points, _point_count: = intersects_triangle_line(t1, triangle_side(t2, u32(i) ))
        for j in 0..<_point_count{
            points[point_count + j] = _points[j]
        }
        point_count += _point_count
    }
    // TODO: filter duplicates?
    return
}

// RAYS =================================================================================================================

// return intersection point (if it exists) of a ray and a ray
intersects_ray_ray::proc(r1:Ray, r2:Ray)->(points:[1]vec2, point_count:int){
    origin_diff: = r2.xy - r1.xy
    cp1: = vec2_cross(r1.zw, r2.zw)
    cp2: = vec2_cross(origin_diff, r2.zw)

    if cp1 == 0{
        if cp2 == 0{
            point_count = 1
            points[0] = r1.xy
            return
        }
        // no touch
        return
    }

    cp3: = vec2_cross(origin_diff, r1.zw)
    t1: = cp2 / cp1 // distance along q1 to intersection
    t2: = cp3 / cp1 // distance along q2 to intersection

    if t1 >= 0 && t2 >= 0{
        // Intersection, both rays positive
        point_count = 1
        points[0] = r1.xy + r1.zw * t1
        return
    }
    // Intersection, but behind a rays origin, so not really an intersection in context
    // TODO: filter duplicates?
    return
}

// return intersection point (if it exists) of a ray and a point
intersection_ray_point::proc(r:Ray, p:vec2)->(points:[1]vec2, point_count:int){
    l:Line = {r.x, r.y, r.x + r.z, r.y + r.w}
    
    if line_side(l, p) == 0{
        points[0] = p
        point_count = 1
        return
    }
    // TODO: filter duplicates?
    return
}

// return intersection point (if it exists) of a ray and a line segment
intersects_ray_line::proc(r:Ray, l:Line)->(points:[1]vec2, point_count:int){
    line_direction: = line_vector(l)
    origin_diff: = l.xy - r.xy
    cp1: = vec2_cross(r.zw, line_direction)
    cp2: = vec2_cross(origin_diff, line_direction)

    if cp1 == 0{
        if cp2 == 0{
            point_count = 1
            points[0] = r.xy
            return
        }
        // no touch
        return
    }

    cp3: = vec2_cross(origin_diff, r.zw)
    t1: = cp2 / cp1 // distance along q1 to intersection
    t2: = cp3 / cp1 // distance along q2 to intersection

    if t1 >= 0 && t2 >= 0{
        // Intersection, both rays positive
        point_count = 1
        points[0] = r.xy + r.zw * t1
        return
    }
    // Intersection, but behind a rays origin, so not really an intersection in context
    // TODO: filter duplicates?
    return
}

// Get intersection points where a ray intersects a circle
intersects_ray_circle::proc(r:Ray, c:Circle)->(points:[2]vec2, point_count:int){
    A: = vec2_mag2(r.zw)
    B: = 2.0 * (vec2_dot(r.xy, r.zw) - vec2_dot(c.xy, r.zw))
    C: = vec2_mag2(c.xy) + vec2_mag2(r.xy) - (2.0 * c.x * r.x) - (2.0 * c.y * r.y) - (c.z  * c.z)
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

// Get intersection points where a ray intersects a rectangle
intersects_ray_rectangle::proc(r:Ray, rect:Rect)->(points:[2]vec2, point_count:int){
    for i in 0..<4{
        _points, _point_count: = intersects_ray_line(r, rect_side(rect, u32(i)), )
        if _point_count > 0{
            assert(point_count < 2, "Too many intersection points")
            points[point_count] = _points[0]
            point_count += 1
        }
    }
    
    // TODO: filter duplicates?
    return
}

// Get intersection points where a ray intersects a triangle
intersects_ray_triangle::proc(r:Ray, t:Triangle)->(points:[2]vec2, point_count:int){
    for i in 0..<3{
        _points, _point_count: = intersects_ray_line(r, triangle_side(t, u32(i)), )
        if _point_count > 0{
            assert(point_count < 2, "Too many intersection points")
            points[point_count] = _points[0]
            point_count += 1
        }
    }
    
    // TODO: filter duplicates?
    return
}