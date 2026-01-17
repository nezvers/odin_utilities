package geometry2d

// Check if point overlaps with point (analogous to contains())
overlaps_point_point::proc(p1:vec2, p2:vec2)->bool{
    return contains_point_point(p1, p2)
}

// Checks if line segment overlaps with point
overlaps_line_point::proc(l:Line, p:vec2)->bool{
    return contains_line_point(l, p)
}

// Checks if rectangle overlaps with point
overlaps_rectangle_point::proc(r:Rect, p:vec2)->bool{
    return contains_rectangle_point(r, p)
}

// Checks if Circle overlaps with point
overlaps_circle_point::proc(c:Circle, p:vec2)->bool{
    return contains_circle_point(c, p)
}

// Checks if Triangle overlaps with point
overlaps_triangle_point::proc(t:Triangle, p:vec2)->bool{
    return contains_triangle_point(t, p)
}

// Checks if point overlaps with line
overlaps_point_line::proc(p:vec2, l:Line)->bool{
    return contains_line_point(l, p)
}

// Checks if line overlaps with line
overlaps_line_line::proc(l1:Line, l2:Line)->bool{
    D:f32 = (l2.w - l2.y) * (l1.z - l1.x) - (l2.z - l2.x) * (l1.w - l1.y)
    uA:f32 = ((l2.z - l2.x) * (l1.y - l2.y) - (l2.w - l2.y) * (l1.x - l2.x)) / D
    uB:f32 = ((l1.z - l1.x) * (l1.y - l2.y) - (l1.w - l1.y) * (l1.x - l2.x)) / D
    return uA >= 0 && uA <= 1 && uB >= 0 && uB <= 1
}

// Checks if rectangle overlaps with line
overlaps_rectangle_line::proc(r:Rect, l:Line)->bool{
    return contains_rectangle_line(r, l) || overlaps_line_line(RectTop(r), l) || overlaps_line_line(RectRight(r), l) || overlaps_line_line(RectBottom(r), l) || overlaps_line_line(RectLeft(r), l)
}

// Checks if Circle overlaps with line
overlaps_circle_line::proc(c:Circle, l:Line)->bool{
    p:vec2 = closest_line_point(l, c.xy)
    return Vec2Mag2(c.xy - p) <= (c.z * c.z)
}

// Check if Triangle overlaps line segment
overlaps_triangle_line::proc(t:Triangle, l:Line)->bool{
    return overlaps_triangle_point(t, l.xy) || overlaps_line_line(TriangleSide(t, 0), l) || overlaps_line_line(TriangleSide(t, 1), l) || overlaps_line_line(TriangleSide(t, 2), l)
}

// Checks if point overlaps with rectangle
overlaps_point_rectangle::proc(p:vec2, r:Rect)->bool{
    return overlaps_rectangle_point(r, p)
}

// Checks if line overlaps with rectangle
overlaps_line_rectangle::proc(l:Line, r:Rect)->bool{
    return overlaps_rectangle_line(r, l)
}

// Checks if rectangle overlaps with rectangle
overlaps_rectangle_rectangle::proc(r1:Rect, r2:Rect)->bool{
    return contains_rectangle_rectangle(r2, r1)
}


// Check if Circle overlaps rectangle
overlaps_circle_rectangle::proc(c:Circle, r:Rect)->bool{
    overlap:f32 = Vec2Mag2(vec2{clamp(c.x, r.x, r.x + r.z), clamp(c.y, r.y, r.y + r.w)} - c.xy)
    if isnan(overlap){overlap = 0}
    return (overlap - (c.z * c.z)) < 0
}

// Check if Triangle overlaps rectangle
overlaps_triangle_rectangle::proc(t:Triangle, r:Rect)->bool{
    return overlaps_triangle_line(t, RectTop(r)) || overlaps_triangle_line(t, RectRight(r)) || overlaps_triangle_line(t, RectBottom(r)) || overlaps_triangle_line(t, RectLeft(r)) || contains_rectangle_point(r, t[0])
}

// Check if point overlaps circle
overlaps_point_circle::proc(p:vec2, c:Circle)->bool{
    return overlaps_circle_point(c, p)
}

// Check if line segment overlaps circle
overlaps_line_circle::proc(l:Line, c:Circle)->bool{
    return overlaps_circle_line(c, l)
}

// Check if rectangle overlaps circle
overlaps_rectangle_circle::proc(r:Rect, c:Circle)->bool{
    return overlaps_circle_rectangle(c, r)
}

// Check if circle overlaps circle
overlaps_circle_circle::proc(c1:Circle, c2:Circle)->bool{
    return Vec2Mag2(c1.xy - c2.xy) <= (c1.z + c2.z) * (c1.z + c2.z)
}

// Check if triangle overlaps circle
overlaps_triangle_circle::proc(t:Triangle, c:Circle)->bool{
    return contains_triangle_point(t, c.xy) || Vec2Mag2(c.xy - closest_triangle_point(t, c.xy)) <= c.z * c.z
}

// Check if point overlaps triangle
overlaps_point_triangle::proc(p:vec2, t:Triangle)->bool{
    return overlaps_triangle_point(t, p)
}

// Check if line segment overlaps triangle
overlaps_line_triangle::proc(l:Line, t:Triangle)->bool{
    return overlaps_triangle_line(t, l)
}

// Check if rectangle overlaps triangle
overlaps_rectangle_triangle::proc(r:Rect, t:Triangle)->bool{
    return overlaps_triangle_rectangle(t, r)
}

// Check if circle overlaps triangle
overlaps_circle_triangle::proc(c:Circle, t:Triangle)->bool{
    return overlaps_triangle_circle(t, c)
}

// Check if triangle overlaps triangle
overlaps_triangle_triangle::proc(t1:Triangle, t2:Triangle)->bool{
    return overlaps_triangle_line(t1, TriangleSide(t2, 0)) || overlaps_triangle_line(t1, TriangleSide(t2, 1)) || overlaps_triangle_line(t1, TriangleSide(t2, 2)) || overlaps_triangle_point(t2, t1[0])
}