package geometry2d


// Checks if point contains point
ContainsPointPoint::proc(p:vec2, p2:vec2)->bool{
    return Vec2Mag2(p - p2) < epsilon
}

// Checks if line contains point
ContainsLinePoint::proc(l:Line, p:vec2)->bool{
    d:f32 = (p.x - l.x) * (l.w - l.y) - (p.y - l.y) * (l.z - l.x)
    if (Abs(d) < epsilon){
        vector:vec2 = LineVector(l)
        dot:f32 = Vec2Dot(vector, p - l.xy)
        mag2:f32 = Vec2Mag2(vector)
        u:f32 = dot / mag2
        return (u >= 0.0) && (u <= 1.0)
    }
    return false
}

// Checks if rectangle contains point
ContainsRectanglePoint::proc(r:Rect, p:vec2)->bool{
    return !(p.x < r.x || p.y < r.y || p.x > (r.x + r.z) || p.y > (r.y + r.w))
}

// Checks if Circle contains point
ContainsCirclePoint::proc(c:Circle, p:vec2)->bool{
    return Vec2Mag2(c.xy - p) <= (c.z * c.z)
}

// Checks if Triangle contains a point
ContainsTrianglePoint::proc(t:Triangle, p:vec2)->bool{
    // http://jsfiddle.net/PerroAZUL/zdaY8/1/
    a:f32 = 0.5 * (-t[1].y * t[2].x + t[0].y * (-t[1].x + t[2].x) + t[0].x * (t[1].y - t[2].y) + t[1].x * t[2].y)
    a_sign:f32 = f32(Signf(a))
    s:f32 = (t[0].y * t[2].x - t[0].x * t[2].y + (t[2].y - t[0].y) * p.x + (t[0].x - t[2].x) * p.y) * a_sign
    v:f32 = (t[0].x * t[1].y - t[0].y * t[1].x + (t[0].y - t[1].y) * p.x + (t[1].x - t[0].x) * p.y) * a_sign
    return s >= 0 && v >= 0 && (s + v) <= 2 * a * a_sign
}

// Checks if raycast contains point
ContainsRayPoint::proc(r:Ray, p:vec2)->bool{
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
ContainsPointLine::proc(p:vec2, l:Line)->bool{
    return false
}

// Checks if line contains line
ContainsLineLine::proc(l1:Line, l2:Line)->bool{
    return OverlapsLinePoint(l1, l2.xy) && OverlapsLinePoint(l1, l2.zw)
}

// Checks if line contains line
ContainsRectangleLine::proc(r:Rect, l:Line)->bool{
    return ContainsRectanglePoint(r, l.xy) && ContainsRectanglePoint(r, l.zw)
}

// Checks if Circle contains line
ContainsCircleLine::proc(c:Circle, l:Line)->bool{
    return ContainsCirclePoint(c, l.xy) && ContainsCirclePoint(c, l.zw)
}

// Checks if Triangle contains line
ContainsTriangleLine::proc(t:Triangle, l:Line)->bool{
    return ContainsTrianglePoint(t, l.xy) && ContainsTrianglePoint(t, l.zw)
}



// Checks if point contains rectangle
// TODO: maybe if all vertices are one point
ContainsPointRectangle::proc(p:vec2, r:Rect)->bool{
    return false
}

// Checks if line contains rectangle
ContainsLineRectangle::proc(l:Line, r:Rect)->bool{
    return false
}

// Checks if rectangle contains rectangle
// r1 >= r2
ContainsRectangleRectangle::proc(r1:Rect, r2:Rect)->bool{
    return r1.x <= r2.x && r1.x + r1.z >= r2.x + r2.z && r1.y <= r2.y && r1.y + r1.w >= r2.y + r2.w
}

// Checks if Circle contains rectangle
ContainsCircleRectangle::proc(c:Circle, r:Rect)->bool{
    return ContainsCirclePoint(c, r.xy) && ContainsCirclePoint(c, r.xy + r.zw) && ContainsCirclePoint(c, {r.x + r.z, r.y}) && ContainsCirclePoint(c, {r.x, r.y + r.w})
}

// Checks if Triangle contains rectangle
ContainsTriangleRectangle::proc(t:Triangle, r:Rect)->bool{
    return ContainsTrianglePoint(t, r.xy) && ContainsTrianglePoint(t, r.xy + r.zw) && ContainsTrianglePoint(t, {r.x + r.z, r.y}) && ContainsTrianglePoint(t, {r.x, r.y + r.w})
}

// Check if point contains circle
ContainsPointCircle::proc(p:vec2, c:Circle)->bool{
    return false
}

// Check if line segment contains circle
ContainsLineCircle::proc(l:Line, c:Circle)->bool{
    return false
}

// Check if rectangle contains circle
ContainsRectangleCircle::proc(r:Rect, c:Circle)->bool{
    return r.x + c.z <= c.x     \
    && c.x <= r.x + r.z - c.z   \
    && r.y + c.z <= c.y         \
    && c.y <= r.y + r.w - c.z
}

// Check if circle contains circle
ContainsCircleCircle::proc(c1:Circle, c2:Circle)->bool{
    distance: = c2.xy - c1.xy
    return (sqrt(distance.x * distance.x + distance.y * distance.y) + c2.z) <= c1.z
}

// Check if triangle contains circle
ContainsTriangleCircle::proc(t:Triangle, c:Circle)->bool{
    if !ContainsTrianglePoint(t, c.xy){
        return false
    }
    closest_p:vec2 = ClosestTrianglePoint(t, c.xy)
    mag_p:f32 = Vec2Mag(c.xy - closest_p)
    return mag_p <= c.z * c.z
}

// Check if point contains triangle
ContainsPointTriangle::proc(p:vec2, t:Triangle)->bool{
    return false
}

// Check if line segment contains triangle
ContainsLineTriangle::proc(l:Line, t:Triangle)->bool{
    return false
}

// Check if rectangle contains triangle
ContainsRectangleTriangle::proc(r:Rect, t:Triangle)->bool{
    return ContainsRectangleLine(r, TriangleSide(t, 0)) && ContainsRectangleLine(r, TriangleSide(t, 1)) && ContainsRectangleLine(r, TriangleSide(t, 2))
}

// Check if circle contains triangle
ContainsCircleTriangle::proc(c:Circle, t:Triangle)->bool{
    return ContainsCircleLine(c, TriangleSide(t, 0)) && ContainsCircleLine(c, TriangleSide(t, 1)) && ContainsCircleLine(c, TriangleSide(t, 2))
}

// Check if triangle contains triangle
ContainsTriangleTriangle::proc(t1:Triangle, t2:Triangle)->bool{
    return ContainsTriangleLine(t1, TriangleSide(t2, 0)) && ContainsTriangleLine(t1, TriangleSide(t2, 1)) && ContainsTriangleLine(t1, TriangleSide(t2, 2))
}