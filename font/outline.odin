package font

// The outline of a glyph as quadratic Bezier curves in em units. TrueType already is; the cubic curves of OpenType (CFF) are cut into quadratics, a line is a quadratic with its control point in
// the middle. The caller gives the room for the curves (`out`), nothing grows. stb_truetype allocates the outline it reads for the length of one call.

import "core:c"
import "core:math"
import stbtt "vendor:stb/truetype"

Curve :: struct {
    p0, p1, p2: Vec2,
}

CUBIC_TOLERANCE :: f32(0.0004)          // em units: how far a quadratic may be from the cubic it replaces (a fifth of a pixel at 500 pixels per em)
CUBIC_MAX_DEPTH :: 4

// The curves of a glyph, the contours one after the other and each contour closed. `ok` is false when `out` is too small (what fits is in `count`). A glyph without an outline has 0 curves.
FontGlyphCurves :: proc(font: ^Font, glyph: int, out: []Curve) -> (count: int, ok: bool) {
    vertices: [^]stbtt.vertex
    vertex_count: c.int = stbtt.GetGlyphShape(&font.info, c.int(glyph), &vertices)
    if vertex_count <= 0 { return 0, true }
    defer stbtt.FreeShape(&font.info, vertices)

    scale: f32 = 1 / font.units_per_em
    start: Vec2
    pen: Vec2
    add :: proc(out: []Curve, count: ^int, curve: Curve) -> bool {
        if count^ >= len(out) { return false }
        out[count^] = curve
        count^ += 1
        return true
    }
    close :: proc(out: []Curve, count: ^int, pen: Vec2, start: Vec2) -> bool {
        if pen == start { return true }
        return add(out, count, {pen, (pen + start) * 0.5, start})
    }
    ok = true
    for i in 0 ..< int(vertex_count) {
        v: stbtt.vertex = vertices[i]
        point: Vec2 = {f32(v.x), f32(v.y)} * scale
        #partial switch stbtt.vmove(v.type) {
        case .vmove:
            ok = close(out, &count, pen, start) && ok
            start, pen = point, point
        case .vline:
            ok = add(out, &count, {pen, (pen + point) * 0.5, point}) && ok
            pen = point
        case .vcurve:
            ok = add(out, &count, {pen, Vec2{f32(v.cx), f32(v.cy)} * scale, point}) && ok
            pen = point
        case .vcubic:
            ok = cubicToQuadratics(out, &count, pen, Vec2{f32(v.cx), f32(v.cy)} * scale, Vec2{f32(v.cx1), f32(v.cy1)} * scale, point, 0) && ok
            pen = point
        }
    }
    ok = close(out, &count, pen, start) && ok
    return
}

// A cubic as quadratics: one quadratic when it is close enough, else halves (de Casteljau)
@(private)
cubicToQuadratics :: proc(out: []Curve, count: ^int, p0: Vec2, c1: Vec2, c2: Vec2, p3: Vec2, depth: int) -> bool {
    // the distance between a cubic and the quadratic with the control point (3 c1 - p0 + 3 c2 - p3) / 4 is at most sqrt(3) / 36 of this vector
    third: Vec2 = p3 - 3 * c2 + 3 * c1 - p0
    error: f32 = math.sqrt(third.x * third.x + third.y * third.y) * 0.04811252
    if error <= CUBIC_TOLERANCE || depth >= CUBIC_MAX_DEPTH {
        if count^ >= len(out) { return false }
        out[count^] = {p0, (3 * c1 - p0 + 3 * c2 - p3) * 0.25, p3}
        count^ += 1
        return true
    }
    p01: Vec2 = (p0 + c1) * 0.5
    p12: Vec2 = (c1 + c2) * 0.5
    p23: Vec2 = (c2 + p3) * 0.5
    p012: Vec2 = (p01 + p12) * 0.5
    p123: Vec2 = (p12 + p23) * 0.5
    middle: Vec2 = (p012 + p123) * 0.5
    first: bool = cubicToQuadratics(out, count, p0, p01, p012, middle, depth + 1)
    second: bool = cubicToQuadratics(out, count, middle, p123, p23, p3, depth + 1)
    return first && second
}

CurveAt :: proc(curve: Curve, t: f32) -> Vec2 {
    a: Vec2 = curve.p0 + (curve.p1 - curve.p0) * t
    b: Vec2 = curve.p1 + (curve.p2 - curve.p1) * t
    return a + (b - a) * t
}

// The part of a curve between two parameters, as a curve of its own
CurveSlice :: proc(curve: Curve, t0: f32, t1: f32) -> Curve {
    // the control point of the piece is where the tangents at both ends meet: the curve at the middle of the span pulled out by the ends
    start: Vec2 = CurveAt(curve, t0)
    end: Vec2 = CurveAt(curve, t1)
    first_tangent: Vec2 = (curve.p1 - curve.p0) * (1 - t0) + (curve.p2 - curve.p1) * t0
    return {start, start + first_tangent * (t1 - t0), end}
}

// The parameter where a curve has no more slope along an axis (0: x, 1: y), in (0, 1), or -1 when it does not turn
@(private)
curveTurn :: proc(curve: Curve, axis: int) -> f32 {
    a: f32 = curve.p0[axis] - 2 * curve.p1[axis] + curve.p2[axis]
    if abs(a) < 1e-9 { return -1 }
    t: f32 = (curve.p0[axis] - curve.p1[axis]) / a
    return t if t > 1e-5 && t < 1 - 1e-5 else -1
}

// Cuts every curve where it turns, so that each piece goes one way along x and one way along y (the two angles of a bow, a curve that comes back). A piece has at most one crossing with a
// horizontal or a vertical line, and its box is spanned by its end points. Horizontal pieces are not dropped here (the Slug method uses them). `out` gets up to three pieces per curve.
CurvesMonotonic :: proc(curves: []Curve, out: []Curve) -> (count: int, ok: bool) {
    for curve in curves {
        cuts: [4]f32
        cut_count: int = 0
        cuts[0] = 0
        cut_count = 1
        tx: f32 = curveTurn(curve, 0)
        ty: f32 = curveTurn(curve, 1)
        if tx > 0 && ty > 0 {
            cuts[1], cuts[2] = min(tx, ty), max(tx, ty)
            cut_count = 3
            if abs(tx - ty) < 1e-5 { cut_count = 2 }
        } else if tx > 0 {
            cuts[1] = tx
            cut_count = 2
        } else if ty > 0 {
            cuts[1] = ty
            cut_count = 2
        }
        cuts[cut_count] = 1
        for i in 0 ..< cut_count {
            if count >= len(out) { return count, false }
            piece: Curve = curve if cut_count == 1 else CurveSlice(curve, cuts[i], cuts[i + 1])
            out[count] = piece
            count += 1
        }
    }
    return count, true
}
