package ui

// The shape of a cable, apart from how it is drawn. A route is a few cubic Bezier segments (one more than the zip ties the cable passes through); the
// style can give its own way of making one for a connected cable and another for a cable that is being dragged (a straight line, a right angled path, a
// spring...), and with it the two things that make many cables cheap and clickable:
//   bounds    a rectangle around the route: the draw loop skips every cable whose rectangle is outside of the view, and the hit test skips every cable
//             whose rectangle does not hold the pointer (a broad phase: the exact test runs on a handful of cables, not on all of them);
//   distance  a signed distance function (here: the distance to the nearest point of the cable, 0 on it): the exact hit test, and the formula a shader needs to draw
//             a cable with a width, an outline or a glow in one pass over the rectangle. It is plain arithmetic on one segment at a time, the pieces are
//             `CableSegmentDistance` and `CableSegmentPoint`.
// The defaults here work for any route made of Bezier segments (also one that the style made itself); a style with another shape gives its own bounds and
// distance, or only a rectangle.

import "core:math"

CABLE_MAX_SEGMENTS :: GRAPH_LINK_TIES + 1
CABLE_PIECES :: 16                  // a segment is measured as this many straight pieces (hit test, crossings, drawing without a curve call)

// A cubic Bezier segment: where it starts, the two control points, where it ends.
CableSegment :: struct {
    p: [4]Vec2,
}

CableRoute :: struct {
    segments: [CABLE_MAX_SEGMENTS]CableSegment,
    count: int,
}

// A point of a zip tie that a cable passes through, and the way it goes through (along the tie's direction, from the output to the input).
CableWaypoint :: struct {
    point: Vec2,
    direction: Vec2,            // unit vector
}

// What a style needs to make the route of one cable. The coordinates are the ones the caller works in (canvas, or the screen).
CableRouteInput :: struct {
    from: Vec2,                 // the pin of the output (or where the drag started)
    to: Vec2,                   // the pin of the input (or the pointer while it is dragged)
    from_direction: Vec2,       // the way the cable leaves the output and arrives at the input: {1, 0} by default (towards +x)
    to_direction: Vec2,
    waypoints: [GRAPH_LINK_TIES]CableWaypoint,   // the zip ties, in the order from the output to the input
    waypoint_count: int,
    dragging: bool,
    link: LinkHandle,           // for the style that routes by what the cable carries (nothing for a cable that is being dragged)
    from_port: PortHandle,
    to_port: PortHandle,        // nothing while the cable is dragged and not over a pin
    user: rawptr,               // the `user` of the GraphStyle
}

// Writes the route of a cable. A nil proc in the style is CableRouteDefault (a horizontal S, through the waypoints).
CableRouteProc :: proc(input: ^CableRouteInput, route: ^CableRoute)

// A rectangle that holds the whole cable, `margin` on every side more (the half of its width and what the pointer may be away from it).
CableBoundsProc :: proc(route: ^CableRoute, margin: f32) -> Rect

// How far a point is from the cable (0 or less: on it). Only asked when the point is in the bounds.
CableDistanceProc :: proc(route: ^CableRoute, point: Vec2) -> f32

// ------------------------------------------------------------------------------------------------------------------------
// The default route

CABLE_MIN_HANDLE :: 30              // the control points of a segment are at least this far from its ends
CABLE_HANDLE :: 0.4                 // and this part of its length

// A cubic Bezier that leaves `a` going `a_direction` and arrives at `b` going `b_direction`.
CableSegmentMake :: proc(a: Vec2, a_direction: Vec2, b: Vec2, b_direction: Vec2) -> CableSegment {
    delta: Vec2 = b - a
    length: f32 = math.sqrt(delta.x * delta.x + delta.y * delta.y)
    handle: f32 = max(length * CABLE_HANDLE, CABLE_MIN_HANDLE)
    return {p = {a, a + a_direction * handle, b - b_direction * handle, b}}
}

// The route of a cable between two pins, a horizontal S, through the zip ties it passes: a segment from the output to the first tie, one between every
// two ties and one from the last tie to the input, each leaving and arriving in the direction of the tie (so a ribbon of cables runs side by side through it).
CableRouteDefault :: proc(input: ^CableRouteInput, route: ^CableRoute) {
    from_direction: Vec2 = input.from_direction if input.from_direction != {} else Vec2{1, 0}
    to_direction: Vec2 = input.to_direction if input.to_direction != {} else Vec2{1, 0}
    route.count = 0
    point: Vec2 = input.from
    direction: Vec2 = from_direction
    for i in 0 ..< input.waypoint_count {
        waypoint: CableWaypoint = input.waypoints[i]
        route.segments[route.count] = CableSegmentMake(point, direction, waypoint.point, waypoint.direction)
        route.count += 1
        point, direction = waypoint.point, waypoint.direction
    }
    route.segments[route.count] = CableSegmentMake(point, direction, input.to, to_direction)
    route.count += 1
}

// A straight line (a route a style may choose for a cable that is dragged): through the waypoints too, with no curve.
CableRouteStraight :: proc(input: ^CableRouteInput, route: ^CableRoute) {
    route.count = 0
    point: Vec2 = input.from
    for i in 0 ..< input.waypoint_count {
        waypoint: Vec2 = input.waypoints[i].point
        route.segments[route.count] = lineSegment(point, waypoint)
        route.count += 1
        point = waypoint
    }
    route.segments[route.count] = lineSegment(point, input.to)
    route.count += 1
}

// A line as a Bezier (control points on the third and the two thirds)
@(private)
lineSegment :: proc(a: Vec2, b: Vec2) -> CableSegment {
    return {p = {a, a + (b - a) * (1.0 / 3), a + (b - a) * (2.0 / 3), b}}
}

// ------------------------------------------------------------------------------------------------------------------------
// Bounds, distance, crossings

// A point of a segment, t from 0 to 1.
CableSegmentPoint :: proc(segment: ^CableSegment, t: f32) -> Vec2 {
    u: f32 = 1 - t
    return segment.p[0] * (u * u * u) + segment.p[1] * (3 * u * u * t) + segment.p[2] * (3 * u * t * t) + segment.p[3] * (t * t * t)
}

// The direction of a segment at t (a unit vector, along the cable from the output to the input).
CableSegmentDirection :: proc(segment: ^CableSegment, t: f32) -> Vec2 {
    u: f32 = 1 - t
    derivative: Vec2 = (segment.p[1] - segment.p[0]) * (3 * u * u) + (segment.p[2] - segment.p[1]) * (6 * u * t) + (segment.p[3] - segment.p[2]) * (3 * t * t)
    length: f32 = math.sqrt(derivative.x * derivative.x + derivative.y * derivative.y)
    if length < 1e-6 { return {1, 0} }
    return derivative / length
}

// The rectangle of the control points (a Bezier stays inside of their hull), `margin` more on every side.
CableBoundsDefault :: proc(route: ^CableRoute, margin: f32) -> Rect {
    low: Vec2 = {INFINITE, INFINITE}
    high: Vec2 = {-INFINITE, -INFINITE}
    for i in 0 ..< route.count {
        for point in route.segments[i].p {
            low = {min(low.x, point.x), min(low.y, point.y)}
            high = {max(high.x, point.x), max(high.y, point.y)}
        }
    }
    return {low.x - margin, low.y - margin, high.x - low.x + 2 * margin, high.y - low.y + 2 * margin}
}

// The distance from a point to a straight piece.
CablePieceDistance :: proc(point: Vec2, a: Vec2, b: Vec2) -> f32 {
    edge: Vec2 = b - a
    length_squared: f32 = edge.x * edge.x + edge.y * edge.y
    t: f32 = 0
    if length_squared > 1e-12 {
        t = clamp(((point.x - a.x) * edge.x + (point.y - a.y) * edge.y) / length_squared, 0, 1)
    }
    closest: Vec2 = a + edge * t
    delta: Vec2 = point - closest
    return math.sqrt(delta.x * delta.x + delta.y * delta.y)
}

// The distance from a point to one segment: the nearest of CABLE_PIECES straight pieces (the same arithmetic in a shader draws the cable with a width).
CableSegmentDistance :: proc(segment: ^CableSegment, point: Vec2) -> f32 {
    best: f32 = INFINITE
    previous: Vec2 = segment.p[0]
    for i in 1 ..= CABLE_PIECES {
        current: Vec2 = CableSegmentPoint(segment, f32(i) / CABLE_PIECES)
        best = min(best, CablePieceDistance(point, previous, current))
        previous = current
    }
    return best
}

// The distance from a point to the whole route.
CableDistanceDefault :: proc(route: ^CableRoute, point: Vec2) -> f32 {
    best: f32 = INFINITE
    for i in 0 ..< route.count {
        best = min(best, CableSegmentDistance(&route.segments[i], point))
    }
    return best
}

// The route as straight pieces into `points` (the start of the first, then the end of every piece): `CABLE_PIECES` per segment, as many as there is room for.
CableFlatten :: proc(route: ^CableRoute, points: []Vec2) -> []Vec2 {
    count: int
    if route.count > 0 && len(points) > 0 {
        points[0] = route.segments[0].p[0]
        count = 1
    }
    for s in 0 ..< route.count {
        for i in 1 ..= CABLE_PIECES {
            if count >= len(points) { return points[:count] }
            points[count] = CableSegmentPoint(&route.segments[s], f32(i) / CABLE_PIECES)
            count += 1
        }
    }
    return points[:count]
}

// Where two straight pieces cross: `t` along the first (0 at `p`, 1 at `q`), when they do.
SegmentCross :: proc(p: Vec2, q: Vec2, r: Vec2, s: Vec2) -> (t: f32, crossed: bool) {
    u: Vec2 = q - p
    v: Vec2 = s - r
    w: Vec2 = r - p
    denominator: f32 = u.x * v.y - u.y * v.x
    if abs(denominator) < 1e-9 { return 0, false }
    t = (w.x * v.y - w.y * v.x) / denominator
    j: f32 = (w.x * u.y - w.y * u.x) / denominator
    return t, t >= 0 && t <= 1 && j >= 0 && j <= 1
}

// The first place (nearest to `a`) where the route crosses the piece from `a` to `b`: `t` along the piece, the point, and the direction of the cable there.
CableCrossing :: proc(route: ^CableRoute, a: Vec2, b: Vec2) -> (t: f32, point: Vec2, direction: Vec2, crossed: bool) {
    best: f32 = INFINITE
    for s in 0 ..< route.count {
        segment: ^CableSegment = &route.segments[s]
        previous: Vec2 = segment.p[0]
        for i in 1 ..= CABLE_PIECES {
            current: Vec2 = CableSegmentPoint(segment, f32(i) / CABLE_PIECES)
            if hit, ok := SegmentCross(a, b, previous, current); ok && hit < best {
                best = hit
                point = a + (b - a) * hit
                direction = CableSegmentDirection(segment, (f32(i) - 0.5) / CABLE_PIECES)
                crossed = true
            }
            previous = current
        }
    }
    return best if crossed else 0, point, direction, crossed
}

// ------------------------------------------------------------------------------------------------------------------------
// The geometry of a zip tie

// The directions of a tie: along the cables, and across them (the lanes are side by side along `normal`).
TieAxes :: proc(angle: f32) -> (tangent: Vec2, normal: Vec2) {
    return {math.cos(angle), math.sin(angle)}, {-math.sin(angle), math.cos(angle)}
}

// Half the length of the strap of a tie that holds `members` links with a lane `spacing` apart (a little more than the lanes, so the outer cables are inside).
TieHalfLength :: proc(tie: ^Tie, spacing: f32) -> f32 {
    return (f32(max(tie.member_count - 1, 0)) * spacing * 0.5 + spacing * 0.6) * tie.scale
}

// The place of a lane (0 .. member_count - 1) on the strap.
TieLanePoint :: proc(tie: ^Tie, lane: int, spacing: f32) -> Vec2 {
    _, normal := TieAxes(tie.angle)
    offset: f32 = (f32(lane) - f32(tie.member_count - 1) * 0.5) * spacing * tie.scale
    return tie.position + normal * offset
}

// The four corners of the strap, `width` across the cables, closing the loop in order.
TieCorners :: proc(tie: ^Tie, spacing: f32, width: f32) -> [4]Vec2 {
    tangent, normal := TieAxes(tie.angle)
    half: f32 = TieHalfLength(tie, spacing)
    side: Vec2 = tangent * (width * 0.5)
    low: Vec2 = tie.position - normal * half
    high: Vec2 = tie.position + normal * half
    return {low - side, low + side, high + side, high - side}
}

// Is a point on the strap (`pad` pixels around it count)? In the frame of the tie: along its length and across.
TieContains :: proc(tie: ^Tie, spacing: f32, width: f32, point: Vec2, pad: f32) -> bool {
    tangent, normal := TieAxes(tie.angle)
    delta: Vec2 = point - tie.position
    across: f32 = abs(delta.x * normal.x + delta.y * normal.y)
    along: f32 = abs(delta.x * tangent.x + delta.y * tangent.y)
    return across <= TieHalfLength(tie, spacing) + pad && along <= width * 0.5 + pad
}

// Does the piece from `a` to `b` cross the strap (or end on it)?
TieCrossedBy :: proc(tie: ^Tie, spacing: f32, width: f32, a: Vec2, b: Vec2) -> bool {
    if TieContains(tie, spacing, width, a, 0) || TieContains(tie, spacing, width, b, 0) { return true }
    corners: [4]Vec2 = TieCorners(tie, spacing, width)
    for i in 0 ..< 4 {
        if _, hit := SegmentCross(a, b, corners[i], corners[(i + 1) % 4]); hit { return true }
    }
    return false
}

// The end of the strap where the rotating handle is (the end the lanes with the highest numbers are at).
TieHead :: proc(tie: ^Tie, spacing: f32) -> Vec2 {
    _, normal := TieAxes(tie.angle)
    return tie.position + normal * TieHalfLength(tie, spacing)
}
