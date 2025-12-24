package geometry2d

// Return circle that fully encapsulates a point
envelope_circle_point::proc(p:vec2)->Circle{
    return {p.x, p.y, 0.0}
}

// Return circle that fully encapsulates a line
envelope_circle_line::proc(l:Line)->Circle{
    p: = line_point_mult(l, 0.5)
    return {p.x, p.y, vec2_mag(line_vector(l)) * 0.5}
}

// Return circle that fully encapsulates a rectangle
envelope_circle_rectangle::proc(r:Rect)->Circle{
    l:Line = {r.x, r.y, r.z, r.w}
    return envelope_circle_line(l)
}

// Return circle that fully encapsulates a circle
envelope_circle_circle::proc(c:Circle)->Circle{
    return c
}

// Return circle that fully encapsulates a triangle
envelope_circle_triangle::proc(t:Triangle)->Circle{
    // TODO: 
    return {}
}