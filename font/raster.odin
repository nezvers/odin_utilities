package font

import "core:math"

// Exact coverage of a pixel by an outline, on the CPU: the reference for the GPU methods and a way to bake a glyph into a bitmap. The idea is the one of the Scanline Sweeper (Rook & Possum, 2026): the
// coverage of a window is the sum, over the curves, of the signed area that each curve sweeps to the right inside of the window (up is positive); no winding numbers, so there is no ray
// that can hit a curve at a glancing angle. Written here from the description of the paper: a curve is cut where it crosses the window, the part left of the window is a rectangle, the part
// inside is a trapezoid sum, the part right of it counts nothing.

// The parameter where one coordinate of a monotonic curve is `target` (clamped to the ends when the target is outside of what the curve covers)
@(private)
monotonicRoot :: proc(c0: f32, c1: f32, c2: f32, target: f32) -> f32 {
    low: f32 = min(c0, c2)
    high: f32 = max(c0, c2)
    if target <= low { return 0 if c0 <= c2 else 1 }
    if target >= high { return 1 if c0 <= c2 else 0 }
    a: f32 = c0 - 2 * c1 + c2
    b: f32 = 2 * (c1 - c0)
    c: f32 = c0 - target
    if abs(a) < 1e-7 { return clamp(-c / b, 0, 1) }
    discriminant: f32 = max(b * b - 4 * a * c, 0)
    root: f32 = math.sqrt(discriminant)
    t1: f32 = (-b + root) / (2 * a)
    t2: f32 = (-b - root) / (2 * a)
    // one of them is in [0, 1] (the curve is monotonic): the one that is, or the nearer
    in_range :: proc(t: f32) -> bool { return t >= -1e-4 && t <= 1 + 1e-4 }
    if in_range(t1) { return clamp(t1, 0, 1) }
    if in_range(t2) { return clamp(t2, 0, 1) }
    return clamp(t1 if abs(t1 - 0.5) < abs(t2 - 0.5) else t2, 0, 1)
}

SWEEP_STEPS :: 3        // the trapezoids a piece inside of the window is cut into (a monotonic piece is nearly straight: one is nearly enough)

// The signed area that a monotonic curve sweeps to the right inside of the window [low, high] (positive when the curve goes up)
CurveSweepArea :: proc(curve: Curve, low: Vec2, high: Vec2) -> f32 {
    y_first: f32 = curve.p0.y
    y_last: f32 = curve.p2.y
    if y_first == y_last { return 0 }
    if max(y_first, y_last) <= low.y || min(y_first, y_last) >= high.y { return 0 }
    width: f32 = high.x - low.x
    up: bool = y_last > y_first

    // the part of the curve between the two scanlines
    t_low: f32 = monotonicRoot(curve.p0.y, curve.p1.y, curve.p2.y, low.y)
    t_high: f32 = monotonicRoot(curve.p0.y, curve.p1.y, curve.p2.y, high.y)
    start: f32 = t_low if up else t_high
    end: f32 = t_high if up else t_low
    if end <= start { return 0 }

    // where in that part the curve enters and leaves the columns of the window
    marks: [4]f32 = {
        start,
        clamp(monotonicRoot(curve.p0.x, curve.p1.x, curve.p2.x, low.x), start, end),
        clamp(monotonicRoot(curve.p0.x, curve.p1.x, curve.p2.x, high.x), start, end),
        end,
    }
    if marks[1] > marks[2] { marks[1], marks[2] = marks[2], marks[1] }
    area: f32
    for i in 0 ..< 3 {
        t0, t1: f32 = marks[i], marks[i + 1]
        if t1 <= t0 { continue }
        a: Vec2 = CurveAt(curve, t0)
        b: Vec2 = CurveAt(curve, t1)
        middle: Vec2 = CurveAt(curve, (t0 + t1) * 0.5)
        if middle.x <= low.x {
            area += (b.y - a.y) * width                                // left of the window: the whole width of the window is to its right
        } else if middle.x >= high.x {
            continue                                                   // right of the window: nothing is swept
        } else {
            // inside: the width between the curve and the right edge, summed in trapezoids along the curve
            previous: Vec2 = a
            for step in 1 ..= SWEEP_STEPS {
                current: Vec2 = CurveAt(curve, t0 + (t1 - t0) * f32(step) / SWEEP_STEPS) if step < SWEEP_STEPS else b
                area += ((high.x - previous.x) + (high.x - current.x)) * 0.5 * (current.y - previous.y)
                previous = current
            }
        }
    }
    return area
}

// The part of the window [low, high] (em units) that the outline covers, 0 to 1. The curves have to be monotonic (CurvesMonotonic); the contours may be in any direction, and overlaps are clamped.
CurvesCoverage :: proc(curves: []Curve, low: Vec2, high: Vec2) -> f32 {
    total: f32
    for curve in curves { total += CurveSweepArea(curve, low, high) }
    window: f32 = (high.x - low.x) * (high.y - low.y)
    if window <= 0 { return 0 }
    return clamp(abs(total) / window, 0, 1)
}

// Draws an outline into a bitmap of one byte per pixel (0 to 255). The em origin is at `origin` in pixels (y goes down on the bitmap, up in the outline), one em is `pixels_per_em` pixels.
CurvesRasterize :: proc(curves: []Curve, pixels_per_em: f32, origin: Vec2, bitmap: []u8, width: int, height: int) {
    assert(len(bitmap) >= width * height)
    step: f32 = 1 / pixels_per_em
    for row in 0 ..< height {
        for column in 0 ..< width {
            low: Vec2 = {(f32(column) - origin.x) * step, (origin.y - f32(row + 1)) * step}
            high: Vec2 = {(f32(column + 1) - origin.x) * step, (origin.y - f32(row)) * step}
            bitmap[row * width + column] = u8(CurvesCoverage(curves, low, high) * 255 + 0.5)
        }
    }
}
