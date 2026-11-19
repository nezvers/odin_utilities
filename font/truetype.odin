package font

// The outlines of a TrueType font (the glyf table): points on and off the curve, already quadratic. A glyph is read straight into the curves of the caller: no list of points is built
// first (stb_truetype allocates one for every call), the three streams of a glyph (flags, x, y) are walked side by side instead.
//
// The steps and the rounding are the ones of stb_truetype v1.28 (see sfnt.odin for the credit), so the curves are the same to the last bit.

import "core:math"

// A composite glyph is made of glyphs that may be composites again: this deep, a font that goes on (or in a circle) is cut
TT_COMPOSITE_DEPTH :: 16

// Where the points of an outline go, in font units: the curves of the caller in em units, or (measure) only the box around the points.
@(private)
OutlineSink :: struct {
    out: []Curve,
    count: int,
    ok: bool,                   // false as soon as a curve did not fit
    scale: f32,                 // font units to em
    start: Vec2,                // the first point of the contour that is open, to close it
    pen: Vec2,
    // the placements of the composites the glyph is a part of, the outermost first
    matrices: [TT_COMPOSITE_DEPTH + 1][6]f32,
    depth: int,
    measure: bool,
    started: bool,
    low: [2]int,
    high: [2]int,
}

// A point of the glyph in em units. A part of a composite is moved by every composite above it, and cut to whole font units after each of them: that is what a list of 16 bit
// points gives, and the curves stay the ones stb_truetype made.
@(private)
sinkPoint :: proc "contextless" (sink: ^OutlineSink, x: int, y: int) -> Vec2 {
    px: int = int(i16(x))
    py: int = int(i16(y))
    for level := sink.depth - 1; level >= 0; level -= 1 {
        m: [6]f32 = sink.matrices[level]
        fx: f32 = f32(px)
        fy: f32 = f32(py)
        px = int(i16(i32(m[0] * fx + m[2] * fy + m[4])))
        py = int(i16(i32(m[1] * fx + m[3] * fy + m[5])))
    }
    return Vec2{f32(px), f32(py)} * sink.scale
}

@(private)
sinkTrack :: proc "contextless" (sink: ^OutlineSink, x: int, y: int) {
    if !sink.started {
        sink.low = {x, y}
        sink.high = {x, y}
        sink.started = true
        return
    }
    sink.low = {min(sink.low.x, x), min(sink.low.y, y)}
    sink.high = {max(sink.high.x, x), max(sink.high.y, y)}
}

@(private)
sinkAdd :: proc "contextless" (sink: ^OutlineSink, curve: Curve) {
    if sink.count >= len(sink.out) {
        sink.ok = false
        return
    }
    sink.out[sink.count] = curve
    sink.count += 1
}

// A contour that did not come back to its first point is closed with a line
@(private)
sinkClose :: proc "contextless" (sink: ^OutlineSink) {
    if sink.measure || sink.pen == sink.start { return }
    sinkAdd(sink, {sink.pen, (sink.pen + sink.start) * 0.5, sink.start})
}

@(private)
sinkMove :: proc "contextless" (sink: ^OutlineSink, x: int, y: int) {
    if sink.measure {
        sinkTrack(sink, x, y)
        return
    }
    sinkClose(sink)
    sink.start = sinkPoint(sink, x, y)
    sink.pen = sink.start
}

// A line is a curve with its control point in the middle
@(private)
sinkLine :: proc "contextless" (sink: ^OutlineSink, x: int, y: int) {
    if sink.measure {
        sinkTrack(sink, x, y)
        return
    }
    point: Vec2 = sinkPoint(sink, x, y)
    sinkAdd(sink, {sink.pen, (sink.pen + point) * 0.5, point})
    sink.pen = point
}

@(private)
sinkQuadratic :: proc "contextless" (sink: ^OutlineSink, x: int, y: int, cx: int, cy: int) {
    if sink.measure {
        sinkTrack(sink, x, y)
        return
    }
    point: Vec2 = sinkPoint(sink, x, y)
    sinkAdd(sink, {sink.pen, sinkPoint(sink, cx, cy), point})
    sink.pen = point
}

// The box of a cubic takes its control points too: it is what stb_truetype reports for a CFF glyph, a bit more than the curve when a control point sticks out
@(private)
sinkCubic :: proc "contextless" (sink: ^OutlineSink, x: int, y: int, cx: int, cy: int, cx1: int, cy1: int) {
    if sink.measure {
        sinkTrack(sink, x, y)
        sinkTrack(sink, cx, cy)
        sinkTrack(sink, cx1, cy1)
        return
    }
    point: Vec2 = sinkPoint(sink, x, y)
    if !cubicToQuadratics(sink.out, &sink.count, sink.pen, sinkPoint(sink, cx, cy), sinkPoint(sink, cx1, cy1), point, 0) { sink.ok = false }
    sink.pen = point
}

// ---------------------------------------------------------------- glyf

// The bytes of a glyph in the glyf table: a header (the number of contours, the box) and the outline. Empty for a glyph without an outline.
@(private)
ttGlyphData :: proc "contextless" (font: ^Font, glyph: int) -> []u8 {
    if glyph < 0 || glyph >= font.glyph_count { return nil }
    start, end: int
    if font.loca_long {
        if glyph >= len(font.loca) / 4 - 1 { return nil }
        start = readU32(font.loca, glyph * 4)
        end = readU32(font.loca, glyph * 4 + 4)
    } else {
        if glyph >= len(font.loca) / 2 - 1 { return nil }
        start = readU16(font.loca, glyph * 2) * 2
        end = readU16(font.loca, glyph * 2 + 2) * 2
    }
    if end <= start || end > len(font.glyf) { return nil }
    return font.glyf[start:end]
}

// The points of a simple glyph: the flags, the x steps and the y steps are three runs of bytes one after the other, each read from its own place
@(private)
TtPoints :: struct {
    flags: []u8,
    xs: []u8,
    ys: []u8,
    flag: u8,
    repeat: u8,                 // how many more points have the same flag
    x: int,
    y: int,
}

@(private)
ttPointsFlag :: #force_inline proc "contextless" (points: ^TtPoints) {
    if points.repeat == 0 {
        points.flag = u8(readU8(points.flags, 0))
        points.flags = skipBytes(points.flags, 1)
        if points.flag & 8 != 0 {
            points.repeat = u8(readU8(points.flags, 0))
            points.flags = skipBytes(points.flags, 1)
        }
    } else {
        points.repeat -= 1
    }
}

// The next point and whether it is on the curve
@(private)
ttPointsNext :: proc "contextless" (points: ^TtPoints) -> (x: int, y: int, on: bool) {
    ttPointsFlag(points)
    flag: u8 = points.flag
    if flag & 2 != 0 {
        step: int = readU8(points.xs, 0)
        points.xs = skipBytes(points.xs, 1)
        points.x += step if flag & 16 != 0 else -step
    } else if flag & 16 == 0 {
        points.x += readI16(points.xs, 0)
        points.xs = skipBytes(points.xs, 2)
    }
    if flag & 4 != 0 {
        step: int = readU8(points.ys, 0)
        points.ys = skipBytes(points.ys, 1)
        points.y += step if flag & 32 != 0 else -step
    } else if flag & 32 == 0 {
        points.y += readI16(points.ys, 0)
        points.ys = skipBytes(points.ys, 2)
    }
    return int(i16(points.x)), int(i16(points.y)), flag & 1 != 0
}

// Where the three runs start: the flags say how long they are themselves and how many bytes every x step takes
@(private)
ttPointsInit :: proc "contextless" (data: []u8, point_count: int) -> (points: TtPoints) {
    walk: TtPoints = {flags = data}
    x_bytes: int
    for _ in 0 ..< point_count {
        ttPointsFlag(&walk)
        if walk.flag & 2 != 0 {
            x_bytes += 1
        } else if walk.flag & 16 == 0 {
            x_bytes += 2
        }
    }
    points.flags = data
    points.xs = walk.flags
    points.ys = skipBytes(walk.flags, x_bytes)
    return
}

// The end of a contour: back to its first point, through the control points that are still open
@(private)
ttCloseContour :: proc "contextless" (sink: ^OutlineSink, was_off: bool, start_off: bool, sx: int, sy: int, scx: int, scy: int, cx: int, cy: int) {
    if start_off {
        if was_off { sinkQuadratic(sink, (cx + scx) >> 1, (cy + scy) >> 1, cx, cy) }
        sinkQuadratic(sink, sx, sy, scx, scy)
    } else if was_off {
        sinkQuadratic(sink, sx, sy, cx, cy)
    } else {
        sinkLine(sink, sx, sy)
    }
}

// The outline of a glyph into the sink. False for an outline that is broken (the sink is then as it was).
@(private)
ttGlyphOutline :: proc "contextless" (font: ^Font, glyph: int, sink: ^OutlineSink, depth: int) -> bool {
    if depth > TT_COMPOSITE_DEPTH { return true }
    data: []u8 = ttGlyphData(font, glyph)
    if len(data) == 0 { return true }
    contour_count: int = readI16(data, 0)
    if contour_count > 0 {
        saved_count: int = sink.count
        ends: []u8 = skipBytes(data, 10)
        instructions: int = readU16(data, 10 + contour_count * 2)
        point_count: int = 1 + readU16(ends, contour_count * 2 - 2)
        points: TtPoints = ttPointsInit(skipBytes(data, 10 + contour_count * 2 + 2 + instructions), point_count)

        contour: int
        next_move: int
        was_off, start_off: bool
        cx, cy, sx, sy, scx, scy: int
        for i := 0; i < point_count; i += 1 {
            x, y, on := ttPointsNext(&points)
            if next_move == i {
                if contour >= contour_count {
                    sink.count = saved_count            // more points than the contours have: not a glyph
                    return false
                }
                if i != 0 { ttCloseContour(sink, was_off, start_off, sx, sy, scx, scy, cx, cy) }
                // a contour may start between two points of the curve: the start is then the middle to the next control point, or the next point itself
                start_off = !on && i < readU16(ends, contour * 2)
                if start_off {
                    scx, scy = x, y
                    ahead: TtPoints = points
                    next_x, next_y, next_on := ttPointsNext(&ahead)
                    if !next_on {
                        sx, sy = (x + next_x) >> 1, (y + next_y) >> 1
                    } else {
                        sx, sy = next_x, next_y
                        points = ahead
                        i += 1
                    }
                } else {
                    sx, sy = x, y
                }
                sinkMove(sink, sx, sy)
                was_off = false
                next_move = 1 + readU16(ends, contour * 2)
                contour += 1
            } else if !on {
                // two control points in a row have a point of the curve in their middle
                if was_off { sinkQuadratic(sink, (cx + x) >> 1, (cy + y) >> 1, cx, cy) }
                cx, cy = x, y
                was_off = true
            } else {
                if was_off {
                    sinkQuadratic(sink, x, y, cx, cy)
                } else {
                    sinkLine(sink, x, y)
                }
                was_off = false
            }
        }
        ttCloseContour(sink, was_off, start_off, sx, sy, scx, scy, cx, cy)
    } else if contour_count < 0 {
        // a composite: other glyphs, each with a placement
        parts: []u8 = skipBytes(data, 10)
        for more := true; more; {
            m: [6]f32 = {1, 0, 0, 1, 0, 0}
            flags: int = readU16(parts, 0)
            part: int = readU16(parts, 2)
            parts = skipBytes(parts, 4)
            if flags & 2 != 0 {
                if flags & 1 != 0 {
                    m[4] = f32(readI16(parts, 0))
                    m[5] = f32(readI16(parts, 2))
                    parts = skipBytes(parts, 4)
                } else {
                    m[4] = f32(i8(readU8(parts, 0)))
                    m[5] = f32(i8(readU8(parts, 1)))
                    parts = skipBytes(parts, 2)
                }
            } else {
                parts = skipBytes(parts, 4 if flags & 1 != 0 else 2)        // placed by matching points: not done, the part stays where it is
            }
            if flags & (1 << 3) != 0 {
                m[0] = f32(readI16(parts, 0)) / 16384
                m[3] = m[0]
                parts = skipBytes(parts, 2)
            } else if flags & (1 << 6) != 0 {
                m[0] = f32(readI16(parts, 0)) / 16384
                m[3] = f32(readI16(parts, 2)) / 16384
                parts = skipBytes(parts, 4)
            } else if flags & (1 << 7) != 0 {
                m[0] = f32(readI16(parts, 0)) / 16384
                m[1] = f32(readI16(parts, 2)) / 16384
                m[2] = f32(readI16(parts, 4)) / 16384
                m[3] = f32(readI16(parts, 6)) / 16384
                parts = skipBytes(parts, 8)
            }
            // the scale of the part also scales its offset only when the font asks for it (the Apple way), not by default
            if flags & (1 << 11) != 0 && flags & (1 << 12) == 0 {
                m[4] *= math.sqrt(m[0] * m[0] + m[1] * m[1])
                m[5] *= math.sqrt(m[2] * m[2] + m[3] * m[3])
            }
            // the placement of this composite is the innermost for its part: the last in the list, the first a point goes through
            if sink.depth < len(sink.matrices) {
                sink.matrices[sink.depth] = m
                sink.depth += 1
                ttGlyphOutline(font, part, sink, depth + 1)
                sink.depth -= 1
            }
            more = flags & (1 << 5) != 0
        }
    }
    return true
}
