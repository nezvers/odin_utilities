package geometry2d

// Returns closest point on point to any shape (aka p1) :P
closest_point_point::proc(p1:vec2, p2:vec2)->vec2{
    return p1
}

// Returns closest point on line to point
closest_line_point::proc(l:Line, p:vec2)->vec2{
    vector:vec2 = LineVector(l)
    dot:f32 = Vec2Dot(vector, p - l.xy)
    mag:f32 = Vec2Mag2(vector)
    Clamp:f32 = Clamp(dot / mag, 0.0, 1.0)
    return l.xy + Clamp * vector
}

// Returns closest point on Circle to point
closest_circle_point::proc(c:Circle, p:vec2)->vec2{
    return c.xy + Vec2Norm(p - c.xy) * c.z
}

// Returns closest point on rectangle to point
closest_rectangle_point::proc(r:Rect, p:vec2)->vec2{
    // Note: this algorithm can be reused for polygon
    c1:vec2 = closest_line_point(RectTop(r), p)
    c2:vec2 = closest_line_point(RectRight(r), p)
    c3:vec2 = closest_line_point(RectBottom(r), p)
    c4:vec2 = closest_line_point(RectLeft(r), p)

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
closest_triangle_point::proc(t:Triangle, p:vec2)->vec2{
    l:Line = LineNew(t[0], t[1])
    p0:vec2 = closest_line_point(l, p)
    d0:f32 = Vec2Mag2(p0 - p)

    l.zw = t[2]
    p1:vec2 = closest_line_point(l, p)
    d1:f32 = Vec2Mag2(p1 - p)

    l.xy = t[1]
    p2:vec2 = closest_line_point(l, p)
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
closest_ray_point::proc(r:Ray, p:vec2)->vec2{
    assert(false, "Not implemented")
    return{}
}


// Returns closest point on Circle to line
closest_circle_line::proc(c:Circle, l:Line)->vec2{
    p:vec2 = closest_line_point(l, c.xy)
    return c.xy + Vec2Norm(p - c.xy) * c.z
}

// TODO:
// Returns closest point on line to line
closest_line_line::proc(l1:Line, l2:Line)->vec2{
    assert(false, "Not implemented")
    return{}
}

// TODO:
// Returns closest point on rectangle to line
closest_rectangle_line::proc(r:Rect, l:Line)->vec2{
    assert(false, "Not implemented")
    return{}
}

// TODO:
// Returns closest point on rectangle to line
closest_triangle_line::proc(t:Triangle, l:Line)->vec2{
    assert(false, "Not implemented")
    return{}
}

// Returns closest point on Circle to Circle
closest_circle_circle::proc(c1:Circle, c2:Circle)->vec2{
    return closest_circle_point(c1, c2.xy)
}

// Returns closest point on line to Circle
closest_line_circle::proc(l:Line, c:Circle)->vec2{
    p:vec2 = closest_circle_line(c, l)
    return closest_line_point(l, p)
}

// TODO:
// Returns closest point on rectangle to Circle
closest_rectangle_circle::proc(r:Rect, c:Circle)->vec2{
    assert(false, "Not implemented")
    return {}
}

// TODO:
// Returns closest point on Triangle to Circle
closest_triangle_circle::proc(t:Triangle, c:Circle)->vec2{
    assert(false, "Not implemented")
    return {}
}

// TODO:
// Returns closest point on line to Circle
closest_line_triangle::proc(l:Line, t:Triangle)->vec2{
    assert(false, "Not implemented")
    return {}
}

// TODO:
// Returns closest point on Rect to Circle
closest_rectangle_triangle::proc(r:Rect, t:Triangle)->vec2{
    assert(false, "Not implemented")
    return {}
}

// TODO:
// Returns closest point on Circle to Circle
closest_circle_triangle::proc(c:Circle, t:Triangle)->vec2{
    assert(false, "Not implemented")
    return {}
}

// TODO:
// Returns closest point on Triangle to Circle
closest_triangle_triangle::proc(t1:Triangle, t2:Triangle)->vec2{
    assert(false, "Not implemented")
    return {}
}


