package icons

// A stroked path as filled outlines. Icon sets like Lucide are lines of a width with round ends and corners; a font, a glyph atlas or a coverage rasterizer wants closed shapes
// to fill. StrokePath walks along both sides of a path at the distance of half the width and puts round joins and caps in between.
//
// Every contour it makes goes around its inside the same way (the inside is on the right of the direction), also where it crosses itself or another one: filled with the nonzero
// rule (and with a coverage that is clamped, like odin_utilities/font) the overlaps are simply covered. No shapes are merged, so nothing has to be intersected.
//
// The curves are quadratic: cubics are cut into quadratics first, a side of a curve is the curve moved along its normals (pieces that turn a lot are cut smaller before).
// Nothing is allocated: the outline and the working room are slices of the caller.

import "core:math"

// A piece of an outline: a quadratic curve, or a line (the control point is then the middle)
Segment :: struct {
    p0, p1, p2: Vec2,
    line: bool,
}

// Closed contours, one after the other in `segments`; `ends[i]` is where contour i ends (one past its last segment)
Outline :: struct {
    segments: []Segment,
    count: int,
    ends: []int,
    end_count: int,
    ok: bool,                   // false as soon as something did not fit
}

OutlineInit :: proc(outline: ^Outline, segments: []Segment, ends: []int) {
    outline^ = {segments = segments, ends = ends, ok = true}
}

STROKE_CUBIC_TOLERANCE :: f32(0.004)        // how far a quadratic may be from the cubic it replaces, in the units of the path (a 24 unit icon at 1000 pixels: a sixth of a pixel)
STROKE_TURN_COS :: f32(0.90)                // a piece of a curve turns by at most 26 degrees: the side of such a piece is a quadratic again, off by less than a thousandth of the width
STROKE_ARC_STEP :: f32(math.PI / 4)         // a round join or cap is made of quadratics of 45 degrees (their middle is 0.3 % of the radius outside of the circle: a hundredth of a pixel for a line of 6 pixels)

@(private)
outlineAdd :: proc(outline: ^Outline, segment: Segment) {
    if outline.count >= len(outline.segments) {
        outline.ok = false
        return
    }
    outline.segments[outline.count] = segment
    outline.count += 1
}

@(private)
outlineEnd :: proc(outline: ^Outline) {
    first: int = outline.ends[outline.end_count - 1] if outline.end_count > 0 else 0
    if outline.count == first { return }
    if outline.end_count >= len(outline.ends) {
        outline.ok = false
        return
    }
    outline.ends[outline.end_count] = outline.count
    outline.end_count += 1
}

@(private)
cross2 :: #force_inline proc(a: Vec2, b: Vec2) -> f32 { return a.x * b.y - a.y * b.x }
@(private)
dot2 :: #force_inline proc(a: Vec2, b: Vec2) -> f32 { return a.x * b.x + a.y * b.y }
@(private)
length2 :: #force_inline proc(a: Vec2) -> f32 { return math.sqrt(a.x * a.x + a.y * a.y) }
@(private)
unit2 :: proc(a: Vec2) -> Vec2 {
    length: f32 = length2(a)
    return a / length if length > 1e-12 else Vec2{1, 0}
}
// A quarter turn to the left of a direction: the normal a side is moved along
@(private)
left2 :: #force_inline proc(a: Vec2) -> Vec2 { return {-a.y, a.x} }
@(private)
rotate2 :: #force_inline proc(a: Vec2, angle: f32) -> Vec2 {
    c, s: f32 = math.cos(angle), math.sin(angle)
    return {a.x * c - a.y * s, a.x * s + a.y * c}
}

// The direction a piece starts and ends with (a control point on an end does not give one: the other points do)
@(private)
segmentStartTangent :: proc(segment: Segment) -> Vec2 {
    direction: Vec2 = segment.p1 - segment.p0
    if segment.line || length2(direction) < 1e-6 { direction = segment.p2 - segment.p0 }
    return unit2(direction)
}

@(private)
segmentEndTangent :: proc(segment: Segment) -> Vec2 {
    direction: Vec2 = segment.p2 - segment.p1
    if segment.line || length2(direction) < 1e-6 { direction = segment.p2 - segment.p0 }
    return unit2(direction)
}

// A piece of a path into the working room: nothing for a piece without a length, a curve that turns too much as two halves
@(private)
piecesAdd :: proc(pieces: []Segment, count: ^int, segment: Segment, depth: int = 0) -> bool {
    if length2(segment.p2 - segment.p0) < 1e-6 && (segment.line || length2(segment.p1 - segment.p0) < 1e-6) { return true }
    if !segment.line && depth < 6 && dot2(segmentStartTangent(segment), segmentEndTangent(segment)) < STROKE_TURN_COS {
        a: Vec2 = (segment.p0 + segment.p1) * 0.5
        b: Vec2 = (segment.p1 + segment.p2) * 0.5
        middle: Vec2 = (a + b) * 0.5
        return piecesAdd(pieces, count, {p0 = segment.p0, p1 = a, p2 = middle}, depth + 1) && piecesAdd(pieces, count, {p0 = middle, p1 = b, p2 = segment.p2}, depth + 1)
    }
    if count^ >= len(pieces) { return false }
    pieces[count^] = segment
    count^ += 1
    return true
}

// A cubic as quadratics: one when it is close enough, else halves (de Casteljau)
@(private)
piecesAddCubic :: proc(pieces: []Segment, count: ^int, p0: Vec2, c1: Vec2, c2: Vec2, p3: Vec2, depth: int = 0) -> bool {
    // the distance between a cubic and the quadratic with the control point (3 c1 - p0 + 3 c2 - p3) / 4 is at most sqrt(3) / 36 of this vector
    third: Vec2 = p3 - 3 * c2 + 3 * c1 - p0
    if length2(third) * 0.04811252 <= STROKE_CUBIC_TOLERANCE || depth >= 5 {
        return piecesAdd(pieces, count, {p0 = p0, p1 = (3 * c1 - p0 + 3 * c2 - p3) * 0.25, p2 = p3})
    }
    p01: Vec2 = (p0 + c1) * 0.5
    p12: Vec2 = (c1 + c2) * 0.5
    p23: Vec2 = (c2 + p3) * 0.5
    p012: Vec2 = (p01 + p12) * 0.5
    p123: Vec2 = (p12 + p23) * 0.5
    middle: Vec2 = (p012 + p123) * 0.5
    return piecesAddCubic(pieces, count, p0, p01, p012, middle, depth + 1) && piecesAddCubic(pieces, count, middle, p123, p23, p3, depth + 1)
}

// An arc around `center` from `from` (a point on the circle) over `turn` radians, as quadratics
@(private)
outlineArc :: proc(outline: ^Outline, center: Vec2, from: Vec2, turn: f32) {
    pieces: int = max(1, int(math.ceil(abs(turn) / STROKE_ARC_STEP - 1e-4)))
    step: f32 = turn / f32(pieces)
    // the control point of a piece is where the tangents of its ends meet: on the bisector, further out than the circle
    reach: f32 = 1 / math.cos(step / 2)
    arm: Vec2 = from - center
    at: Vec2 = from
    for piece in 0 ..< pieces {
        control: Vec2 = center + rotate2(arm, step * (f32(piece) + 0.5)) * reach
        next: Vec2 = center + rotate2(arm, step * f32(piece + 1))
        outlineAdd(outline, {p0 = at, p1 = control, p2 = next})
        at = next
    }
}

// One contour: the left side of every piece of `pieces` in turn, at `radius`, and from the end of the last one to the start of the first. Between two pieces the side goes
// around the corner with an arc where the corner points to this side, and straight across where it points away (the inside of a corner is covered by the two pieces anyway).
// A piece that starts where the one before turned around (the far end of an open path) gets the half circle of a round cap by the same rule.
@(private)
outlineSide :: proc(outline: ^Outline, pieces: []Segment, radius: f32) {
    count: int = len(pieces)
    if count == 0 { return }
    last: Segment = pieces[count - 1]
    at: Vec2 = last.p2 + left2(segmentEndTangent(last)) * radius
    before: Vec2 = segmentEndTangent(last)
    for piece in pieces {
        start_tangent: Vec2 = segmentStartTangent(piece)
        end_tangent: Vec2 = segmentEndTangent(piece)
        start: Vec2 = piece.p0 + left2(start_tangent) * radius
        end: Vec2 = piece.p2 + left2(end_tangent) * radius

        // the corner before this piece
        turn_cross: f32 = cross2(before, start_tangent)
        turn_dot: f32 = dot2(before, start_tangent)
        if turn_dot < -0.9999 {
            // back the way it came: around the end, through the direction it had
            outlineArc(outline, piece.p0, at, -math.PI)
        } else if turn_cross < -1e-4 {
            outlineArc(outline, piece.p0, at, math.atan2(turn_cross, turn_dot))
        } else if length2(start - at) > 1e-5 {
            outlineAdd(outline, {p0 = at, p1 = (at + start) * 0.5, p2 = start, line = true})
        } else {
            start = at                              // a smooth joint: the side goes on exactly where it was, without a gap of a rounding
        }

        // the piece itself, moved to the side: the control point is where the tangents of the moved ends meet
        if piece.line {
            outlineAdd(outline, {p0 = start, p1 = (start + end) * 0.5, p2 = end, line = true})
        } else {
            control: Vec2 = (start + end) * 0.5
            bend: f32 = cross2(start_tangent, end_tangent)
            if abs(bend) > 1e-5 {
                along: f32 = cross2(end - start, end_tangent) / bend
                back: f32 = -cross2(end - start, start_tangent) / bend
                // behind an end: the curve is tighter than the side is far (the side has a cusp there), a straight piece is what is left
                if along > 0 && back > 0 { control = start + start_tangent * along }
            }
            outlineAdd(outline, {p0 = start, p1 = control, p2 = end})
        }
        at = end
        before = end_tangent
    }
    outlineEnd(outline)
}

// A full circle (a path of no length with round caps is a dot)
@(private)
outlineDot :: proc(outline: ^Outline, center: Vec2, radius: f32) {
    outlineArc(outline, center, center + {radius, 0}, -2 * math.PI)
    outlineEnd(outline)
}

// One subpath of the working room (pieces[:count], the second half of the room is free) into the outline
@(private)
strokeSubpath :: proc(outline: ^Outline, room: []Segment, count: int, closed: bool, radius: f32, first: Vec2, any: bool) {
    if count == 0 {
        if any { outlineDot(outline, first, radius) }
        return
    }
    if 2 * count > len(room) {
        outline.ok = false
        return
    }
    // the same pieces the other way: their left side is the right side of the path
    for i in 0 ..< count {
        piece: Segment = room[count - 1 - i]
        room[count + i] = {p0 = piece.p2, p1 = piece.p1, p2 = piece.p0, line = piece.line}
    }
    if closed {
        outlineSide(outline, room[:count], radius)
        outlineSide(outline, room[count:2 * count], radius)
    } else {
        // there and back in one contour: the turn at each end is a round cap
        outlineSide(outline, room[:2 * count], radius)
    }
}

// The outline of `path` drawn with a line of `width`, round joins and round caps, added to `outline`. `room` is working memory: twice the pieces the longest subpath has after
// its curves were cut (64 per curve is plenty). When something does not fit, `outline.ok` is false.
StrokePath :: proc(path: []PathSegment, width: f32, room: []Segment, outline: ^Outline) {
    radius: f32 = width / 2
    count: int
    pen, start: Vec2
    any: bool                   // the subpath has a point
    half: []Segment = room[:len(room) / 2]
    for segment in path {
        fits: bool = true
        switch segment.kind {
        case .MOVE:
            strokeSubpath(outline, room, count, false, radius, start, any)
            count = 0
            pen, start, any = segment.p[0], segment.p[0], true
        case .LINE:
            fits = piecesAdd(half, &count, {p0 = pen, p1 = (pen + segment.p[0]) * 0.5, p2 = segment.p[0], line = true})
            pen, any = segment.p[0], true
        case .QUADRATIC:
            fits = piecesAdd(half, &count, {p0 = pen, p1 = segment.p[0], p2 = segment.p[1]})
            pen, any = segment.p[1], true
        case .CUBIC:
            fits = piecesAddCubic(half, &count, pen, segment.p[0], segment.p[1], segment.p[2])
            pen, any = segment.p[2], true
        case .CLOSE:
            if any {
                fits = piecesAdd(half, &count, {p0 = pen, p1 = (pen + start) * 0.5, p2 = start, line = true})
                strokeSubpath(outline, room, count, count > 0, radius, start, any)
            }
            count = 0
            pen, any = start, false
        }
        if !fits { outline.ok = false }
    }
    strokeSubpath(outline, room, count, false, radius, start, any)
}

// The inside of `path` (every subpath closed), added to `outline` with the direction the strokes have, so that a filled shape and its stroke add up
FillPath :: proc(path: []PathSegment, room: []Segment, outline: ^Outline) {
    count: int
    pen, start: Vec2
    flush :: proc(outline: ^Outline, room: []Segment, count: ^int, pen: Vec2, start: Vec2) {
        if count^ == 0 { return }
        if !piecesAdd(room, count, {p0 = pen, p1 = (pen + start) * 0.5, p2 = start, line = true}) { outline.ok = false }
        // twice the area the contour goes around, by its points: negative when the inside is on the right
        area: f32
        for piece in room[:count^] {
            area += cross2(piece.p0, piece.p1) + cross2(piece.p1, piece.p2)
        }
        if area <= 0 {
            for piece in room[:count^] { outlineAdd(outline, piece) }
        } else {
            for i := count^ - 1; i >= 0; i -= 1 {
                piece: Segment = room[i]
                outlineAdd(outline, {p0 = piece.p2, p1 = piece.p1, p2 = piece.p0, line = piece.line})
            }
        }
        outlineEnd(outline)
        count^ = 0
    }
    for segment in path {
        fits: bool = true
        switch segment.kind {
        case .MOVE:
            flush(outline, room, &count, pen, start)
            pen, start = segment.p[0], segment.p[0]
        case .LINE:
            fits = piecesAdd(room, &count, {p0 = pen, p1 = (pen + segment.p[0]) * 0.5, p2 = segment.p[0], line = true})
            pen = segment.p[0]
        case .QUADRATIC:
            fits = piecesAdd(room, &count, {p0 = pen, p1 = segment.p[0], p2 = segment.p[1]})
            pen = segment.p[1]
        case .CUBIC:
            fits = piecesAddCubic(room, &count, pen, segment.p[0], segment.p[1], segment.p[2])
            pen = segment.p[2]
        case .CLOSE:
            flush(outline, room, &count, pen, start)
            pen = start
        }
        if !fits { outline.ok = false }
    }
    flush(outline, room, &count, pen, start)
}
