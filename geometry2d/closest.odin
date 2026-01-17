package geometry2d

// Returns closest point on point to any shape (aka p1) :P
ClosestPointPoint::proc(p1:vec2, p2:vec2)->vec2{
    return p1
}

// Returns closest point on line to point
ClosestLinePoint::proc(l:Line, p:vec2)->vec2{
    vector:vec2 = LineVector(l)
    dot:f32 = Vec2Dot(vector, p - l.xy)
    mag:f32 = Vec2Mag2(vector)
    Clamp:f32 = Clamp(dot / mag, 0.0, 1.0)
    return l.xy + Clamp * vector
}

// Returns closest point on Circle to point
ClosestCirclePoint::proc(c:Circle, p:vec2)->vec2{
    return c.xy + Vec2Norm(p - c.xy) * c.z
}

// Returns closest point on rectangle to point
ClosestRectanglePoint::proc(r:Rect, p:vec2)->vec2{
    // Note: this algorithm can be reused for polygon
    c1:vec2 = ClosestLinePoint(RectTop(r), p)
    c2:vec2 = ClosestLinePoint(RectRight(r), p)
    c3:vec2 = ClosestLinePoint(RectBottom(r), p)
    c4:vec2 = ClosestLinePoint(RectLeft(r), p)

    d1:f32 = Vec2Mag2(c1 - p)
    d2:f32 = Vec2Mag2(c2 - p)
    d3:f32 = Vec2Mag2(c3 - p)
    d4:f32 = Vec2Mag2(c4 - p)

    cmin:vec2 = c1
    dmin:f32 = d1

    if (d2 < dmin){
        dmin = d2
        cmin = c2
    }
    if (d3 < dmin){
        dmin = d3
        cmin = c3
    }
    if (d4 < dmin){
        dmin = d4
        cmin = c4
    }
    return cmin
}

// Returns closest point on Triangle to point
ClosestTrianglePoint::proc(t:Triangle, p:vec2)->vec2{
    l:Line = LineNew(t[0], t[1])
    p0:vec2 = ClosestLinePoint(l, p)
    d0:f32 = Vec2Mag2(p0 - p)

    l.zw = t[2]
    p1:vec2 = ClosestLinePoint(l, p)
    d1:f32 = Vec2Mag2(p1 - p)

    l.xy = t[1]
    p2:vec2 = ClosestLinePoint(l, p)
    d2:f32 = Vec2Mag2(p2 - p)

    if ((d0 <= d1) && (d0 <= d2)){
        return p0
    }

    if ((d1 <= d0) && (d1 <= d2)){
        return p1
    }

    return p2
}

// TODO:
// Returns closest point on ray to point
ClosestRayPoint::proc(r:Ray, p:vec2)->vec2{
    assert(false, "Not implemented")
    return{}
}


// Returns closest point on Circle to line
ClosestCircleLine::proc(c:Circle, l:Line)->vec2{
    p:vec2 = ClosestLinePoint(l, c.xy)
    return c.xy + Vec2Norm(p - c.xy) * c.z
}

// TODO:
// Returns closest point on line to line
ClosestLineLine::proc(l1:Line, l2:Line)->vec2{
    assert(false, "Not implemented")
    return{}
}

// TODO:
// Returns closest point on rectangle to line
ClosestRectangleLine::proc(r:Rect, l:Line)->vec2{
    assert(false, "Not implemented")
    return{}
}

// TODO:
// Returns closest point on rectangle to line
ClosestTriangleLine::proc(t:Triangle, l:Line)->vec2{
    assert(false, "Not implemented")
    return{}
}

// Returns closest point on Circle to Circle
ClosestCircleCircle::proc(c1:Circle, c2:Circle)->vec2{
    return ClosestCirclePoint(c1, c2.xy)
}

// Returns closest point on line to Circle
ClosestLineCircle::proc(l:Line, c:Circle)->vec2{
    p:vec2 = ClosestCircleLine(c, l)
    return ClosestLinePoint(l, p)
}

// TODO:
// Returns closest point on rectangle to Circle
ClosestRectangleCircle::proc(r:Rect, c:Circle)->vec2{
    assert(false, "Not implemented")
    return {}
}

// TODO:
// Returns closest point on Triangle to Circle
ClosestTriangleCircle::proc(t:Triangle, c:Circle)->vec2{
    assert(false, "Not implemented")
    return {}
}

// TODO:
// Returns closest point on line to Circle
ClosestLineTriangle::proc(l:Line, t:Triangle)->vec2{
    assert(false, "Not implemented")
    return {}
}

// TODO:
// Returns closest point on Rect to Circle
ClosestRectangleTriangle::proc(r:Rect, t:Triangle)->vec2{
    assert(false, "Not implemented")
    return {}
}

// TODO:
// Returns closest point on Circle to Circle
ClosestCircleTriangle::proc(c:Circle, t:Triangle)->vec2{
    assert(false, "Not implemented")
    return {}
}

// TODO:
// Returns closest point on Triangle to Circle
ClosestTriangleTriangle::proc(t1:Triangle, t2:Triangle)->vec2{
    assert(false, "Not implemented")
    return {}
}


