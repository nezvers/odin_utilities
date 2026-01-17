package geometry2d


// Checks if point contains point
contains_point_point::proc(p:vec2, p2:vec2)->bool{
    return Vec2Mag2(p - p2) < epsilon
}

// Checks if line contains point
contains_line_point::proc(l:Line, p:vec2)->bool{
    d:f32 = (p.x - l.x) * (l.w - l.y) - (p.y - l.y) * (l.z - l.x)
    if (abs(d) < epsilon){
        vector:vec2 = LineVector(l)
        dot:f32 = Vec2Dot(vector, p - l.xy)
        mag2:f32 = Vec2Mag2(vector)
        u:f32 = dot / mag2
        return (u >= 0.0) && (u <= 1.0)
    }
    return false
}

// Checks if rectangle contains point
contains_rectangle_point::proc(r:Rect, p:vec2)->bool{
    return !(p.x < r.x || p.y < r.y || p.x > (r.x + r.z) || p.y > (r.y + r.w))
}

// Checks if Circle contains point
contains_circle_point::proc(c:Circle, p:vec2)->bool{
    return Vec2Mag2(c.xy - p) <= (c.z * c.z)
}

// Checks if Triangle contains a point
contains_triangle_point::proc(t:Triangle, p:vec2)->bool{
    // http://jsfiddle.net/PerroAZUL/zdaY8/1/
    a:f32 = 0.5 * (-t[1].y * t[2].x + t[0].y * (-t[1].x + t[2].x) + t[0].x * (t[1].y - t[2].y) + t[1].x * t[2].y)
    a_sign:f32 = f32(signf(a))
    s:f32 = (t[0].y * t[2].x - t[0].x * t[2].y + (t[2].y - t[0].y) * p.x + (t[0].x - t[2].x) * p.y) * a_sign
    v:f32 = (t[0].x * t[1].y - t[0].y * t[1].x + (t[0].y - t[1].y) * p.x + (t[1].x - t[0].x) * p.y) * a_sign
    return s >= 0 && v >= 0 && (s + v) <= 2 * a * a_sign
}

// Checks if raycast contains point
contains_ray_point::proc(r:Ray, p:vec2)->bool{
    op:vec2 = p - r.xy
    dot:f32 = Vec2Dot(op, r.zw)
    if (dot < 0){
        return false
    }
    projection:vec2 = {r.z * dot, r.w * dot}

    d:vec2 = projection - op
    dist2:f32 = d.x * d.x + d.y * d.y
    // TODO: Test if required
    //distance:f32 = sqrt(dist2)
    return dist2 < epsilon
}

// Checks if point contains line
// It can't!
contains_point_line::proc(p:vec2, l:Line)->bool{
    return false
}

// Checks if line contains line
contains_line_line::proc(l1:Line, l2:Line)->bool{
    return overlaps_line_point(l1, l2.xy) && overlaps_line_point(l1, l2.zw)
}

// Checks if line contains line
contains_rectangle_line::proc(r:Rect, l:Line)->bool{
    return contains_rectangle_point(r, l.xy) && contains_rectangle_point(r, l.zw)
}

// Checks if Circle contains line
contains_circle_line::proc(c:Circle, l:Line)->bool{
    return contains_circle_point(c, l.xy) && contains_circle_point(c, l.zw)
}

// Checks if Triangle contains line
contains_triangle_line::proc(t:Triangle, l:Line)->bool{
    return contains_triangle_point(t, l.xy) && contains_triangle_point(t, l.zw)
}



// Checks if point contains rectangle
// TODO: maybe if all vertices are one point
contains_point_rectangle::proc(p:vec2, r:Rect)->bool{
    return false
}

// Checks if line contains rectangle
contains_line_rectangle::proc(l:Line, r:Rect)->bool{
    return false
}

// Checks if rectangle contains rectangle
// r1 >= r2
contains_rectangle_rectangle::proc(r1:Rect, r2:Rect)->bool{
    return r1.x <= r2.x && r1.x + r1.z >= r2.x + r2.z && r1.y <= r2.y && r1.y + r1.w >= r2.y + r2.w
}

// Checks if Circle contains rectangle
contains_circle_rectangle::proc(c:Circle, r:Rect)->bool{
    return contains_circle_point(c, r.xy) && contains_circle_point(c, r.xy + r.zw) && contains_circle_point(c, {r.x + r.z, r.y}) && contains_circle_point(c, {r.x, r.y + r.w})
}

// Checks if Triangle contains rectangle
contains_triangle_rectangle::proc(t:Triangle, r:Rect)->bool{
    return contains_triangle_point(t, r.xy) && contains_triangle_point(t, r.xy + r.zw) && contains_triangle_point(t, {r.x + r.z, r.y}) && contains_triangle_point(t, {r.x, r.y + r.w})
}

// Check if point contains circle
contains_point_circle::proc(p:vec2, c:Circle)->bool{
    return false
}

// Check if line segment contains circle
contains_line_circle::proc(l:Line, c:Circle)->bool{
    return false
}

// Check if rectangle contains circle
contains_rectangle_circle::proc(r:Rect, c:Circle)->bool{
    return r.x + c.z <= c.x     \
    && c.x <= r.x + r.z - c.z   \
    && r.y + c.z <= c.y         \
    && c.y <= r.y + r.w - c.z
}

// Check if circle contains circle
contains_circle_circle::proc(c1:Circle, c2:Circle)->bool{
    distance: = c2.xy - c1.xy
    return (sqrt(distance.x * distance.x + distance.y * distance.y) + c2.z) <= c1.z
}

// Check if triangle contains circle
contains_triangle_circle::proc(t:Triangle, c:Circle)->bool{
    if !contains_triangle_point(t, c.xy){
        return false
    }
    closest_p:vec2 = closest_triangle_point(t, c.xy)
    mag_p:f32 = Vec2Mag(c.xy - closest_p)
    return mag_p <= c.z * c.z
}

// Check if point contains triangle
contains_point_triangle::proc(p:vec2, t:Triangle)->bool{
    return false
}

// Check if line segment contains triangle
contains_line_triangle::proc(l:Line, t:Triangle)->bool{
    return false
}

// Check if rectangle contains triangle
contains_rectangle_triangle::proc(r:Rect, t:Triangle)->bool{
    return contains_rectangle_line(r, triangle_side(t, 0)) && contains_rectangle_line(r, triangle_side(t, 1)) && contains_rectangle_line(r, triangle_side(t, 2))
}

// Check if circle contains triangle
contains_circle_triangle::proc(c:Circle, t:Triangle)->bool{
    return contains_circle_line(c, triangle_side(t, 0)) && contains_circle_line(c, triangle_side(t, 1)) && contains_circle_line(c, triangle_side(t, 2))
}

// Check if triangle contains triangle
contains_triangle_triangle::proc(t1:Triangle, t2:Triangle)->bool{
    return contains_triangle_line(t1, triangle_side(t2, 0)) && contains_triangle_line(t1, triangle_side(t2, 1)) && contains_triangle_line(t1, triangle_side(t2, 2))
}