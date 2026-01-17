package geometry2d

// Check if point overlaps with point (analogous to contains())
OverlapsPointPoint::proc(p1:vec2, p2:vec2)->bool{
    return ContainsPointPoint(p1, p2)
}

// Checks if line segment overlaps with point
OverlapsLinePoint::proc(l:Line, p:vec2)->bool{
    return ContainsLinePoint(l, p)
}

// Checks if rectangle overlaps with point
OverlapsRectanglePoint::proc(r:Rect, p:vec2)->bool{
    return ContainsRectanglePoint(r, p)
}

// Checks if Circle overlaps with point
OverlapsCirclePoint::proc(c:Circle, p:vec2)->bool{
    return ContainsCirclePoint(c, p)
}

// Checks if Triangle overlaps with point
OverlapsTrianglePoint::proc(t:Triangle, p:vec2)->bool{
    return ContainsTrianglePoint(t, p)
}

// Checks if point overlaps with line
OverlapsPointLine::proc(p:vec2, l:Line)->bool{
    return ContainsLinePoint(l, p)
}

// Checks if line overlaps with line
OverlapsLineLine::proc(l1:Line, l2:Line)->bool{
    D:f32 = (l2.w - l2.y) * (l1.z - l1.x) - (l2.z - l2.x) * (l1.w - l1.y)
    uA:f32 = ((l2.z - l2.x) * (l1.y - l2.y) - (l2.w - l2.y) * (l1.x - l2.x)) / D
    uB:f32 = ((l1.z - l1.x) * (l1.y - l2.y) - (l1.w - l1.y) * (l1.x - l2.x)) / D
    return uA >= 0 && uA <= 1 && uB >= 0 && uB <= 1
}

// Checks if rectangle overlaps with line
OverlapsRectangleLine::proc(r:Rect, l:Line)->bool{
    return ContainsRectangleLine(r, l) || OverlapsLineLine(RectTop(r), l) || OverlapsLineLine(RectRight(r), l) || OverlapsLineLine(RectBottom(r), l) || OverlapsLineLine(RectLeft(r), l)
}

// Checks if Circle overlaps with line
OverlapsCircleLine::proc(c:Circle, l:Line)->bool{
    p:vec2 = ClosestLinePoint(l, c.xy)
    return Vec2Mag2(c.xy - p) <= (c.z * c.z)
}

// Check if Triangle overlaps line segment
OverlapsTriangleLine::proc(t:Triangle, l:Line)->bool{
    return OverlapsTrianglePoint(t, l.xy) || OverlapsLineLine(TriangleSide(t, 0), l) || OverlapsLineLine(TriangleSide(t, 1), l) || OverlapsLineLine(TriangleSide(t, 2), l)
}

// Checks if point overlaps with rectangle
OverlapsPointRectangle::proc(p:vec2, r:Rect)->bool{
    return OverlapsRectanglePoint(r, p)
}

// Checks if line overlaps with rectangle
OverlapsLineRectangle::proc(l:Line, r:Rect)->bool{
    return OverlapsRectangleLine(r, l)
}

// Checks if rectangle overlaps with rectangle
OverlapsRectangleRectangle::proc(r1:Rect, r2:Rect)->bool{
    return ContainsRectangleRectangle(r2, r1)
}


// Check if Circle overlaps rectangle
OverlapsCircleRectangle::proc(c:Circle, r:Rect)->bool{
    overlap:f32 = Vec2Mag2(vec2{Clamp(c.x, r.x, r.x + r.z), Clamp(c.y, r.y, r.y + r.w)} - c.xy)
    if isnan(overlap){overlap = 0}
    return (overlap - (c.z * c.z)) < 0
}

// Check if Triangle overlaps rectangle
OverlapsTriangleRectangle::proc(t:Triangle, r:Rect)->bool{
    return OverlapsTriangleLine(t, RectTop(r)) || OverlapsTriangleLine(t, RectRight(r)) || OverlapsTriangleLine(t, RectBottom(r)) || OverlapsTriangleLine(t, RectLeft(r)) || ContainsRectanglePoint(r, t[0])
}

// Check if point overlaps circle
OverlapsPointCircle::proc(p:vec2, c:Circle)->bool{
    return OverlapsCirclePoint(c, p)
}

// Check if line segment overlaps circle
OverlapsLineCircle::proc(l:Line, c:Circle)->bool{
    return OverlapsCircleLine(c, l)
}

// Check if rectangle overlaps circle
OverlapsRectangleCircle::proc(r:Rect, c:Circle)->bool{
    return OverlapsCircleRectangle(c, r)
}

// Check if circle overlaps circle
OverlapsCircleCircle::proc(c1:Circle, c2:Circle)->bool{
    return Vec2Mag2(c1.xy - c2.xy) <= (c1.z + c2.z) * (c1.z + c2.z)
}

// Check if triangle overlaps circle
OverlapsTriangleCircle::proc(t:Triangle, c:Circle)->bool{
    return ContainsTrianglePoint(t, c.xy) || Vec2Mag2(c.xy - ClosestTrianglePoint(t, c.xy)) <= c.z * c.z
}

// Check if point overlaps triangle
OverlapsPointTriangle::proc(p:vec2, t:Triangle)->bool{
    return OverlapsTrianglePoint(t, p)
}

// Check if line segment overlaps triangle
OverlapsLineTriangle::proc(l:Line, t:Triangle)->bool{
    return OverlapsTriangleLine(t, l)
}

// Check if rectangle overlaps triangle
OverlapsRectangleTriangle::proc(r:Rect, t:Triangle)->bool{
    return OverlapsTriangleRectangle(t, r)
}

// Check if circle overlaps triangle
OverlapsCircleTriangle::proc(c:Circle, t:Triangle)->bool{
    return OverlapsTriangleCircle(t, c)
}

// Check if triangle overlaps triangle
OverlapsTriangleTriangle::proc(t1:Triangle, t2:Triangle)->bool{
    return OverlapsTriangleLine(t1, TriangleSide(t2, 0)) || OverlapsTriangleLine(t1, TriangleSide(t2, 1)) || OverlapsTriangleLine(t1, TriangleSide(t2, 2)) || OverlapsTrianglePoint(t2, t1[0])
}