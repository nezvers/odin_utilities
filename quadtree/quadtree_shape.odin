package quadtree

// What the trees are asked about besides rectangles and points: a circle and a segment (a ray with an end). The trees prune nodes with `probeHitsExtent` and test the elements with `probeHitsRect`;
// both only read the probe, so the shapes cost the same in the immediate, the retained and the chunked tree.
//
// Thread safety: a query normally marks the elements it reported (`stamp`, an element sits in several leaves), which writes to the tree. With a `QuerySession` the marks live in memory of the
// caller, one session per thread, and the tree is only read: any number of threads may query one tree that nobody changes at the same time.
//
//     stamps: [CAPACITY]u32           // one per element of the tree (the elements `E` of a Quadtree; the handle slots of a retained tree)
//     session: quadtree.QuerySession
//     quadtree.QuerySessionInit(&session, stamps[:])
//     count := quadtree.QuadtreeQueryCircle(&tree, {10, 10}, 5, out[:], session = &session)

// The marks of one thread. `stamps` is the caller's memory, at least as long as the tree has elements (or handle slots); a query makes a new number and compares against it, so nothing is cleared
// between queries (only when the number wraps around, every four billion queries).
QuerySession :: struct {
    stamps: []u32,
    stamp: u32,
}

QuerySessionInit :: proc(session: ^QuerySession, stamps: []u32) {
    session.stamps = stamps
    session.stamp = 0
    for &stamp in stamps { stamp = 0 }
}

@(private)
sessionBegin :: proc(session: ^QuerySession, needed: int) {
    assert(len(session.stamps) >= needed, "the QuerySession is smaller than the tree")
    session.stamp += 1
    if session.stamp != 0 { return }
    for &stamp in session.stamps { stamp = 0 }
    session.stamp = 1
}

// True when `index` was already reported in this query; marks it
@(private)
sessionSeen :: proc(session: ^QuerySession, index: int) -> bool {
    if session.stamps[index] == session.stamp { return true }
    session.stamps[index] = session.stamp
    return false
}

@(private)
ShapeKind :: enum u8 {
    RECT,
    POINT,
    CIRCLE,
    SEGMENT,
}

// A query shape. `rect` is the bounding rectangle (the nodes of rectangle and point queries are picked with it), `a` the start and `d` the vector of a segment
@(private)
Probe :: struct {
    kind: ShapeKind,
    rect: Rect,
    center: Vec2,
    radius: f32,
    a: Vec2,
    d: Vec2,
}

@(private)
probeRect :: proc(rect: Rect) -> Probe {
    return {kind = .RECT, rect = rect}
}

@(private)
probePoint :: proc(point: Vec2) -> Probe {
    return {kind = .POINT, rect = {point.x, point.y, 0, 0}}
}

@(private)
probeCircle :: proc(center: Vec2, radius: f32) -> Probe {
    return {kind = .CIRCLE, center = center, radius = radius, rect = {center.x - radius, center.y - radius, radius * 2, radius * 2}}
}

@(private)
probeSegment :: proc(a: Vec2, b: Vec2) -> Probe {
    return {kind = .SEGMENT, a = a, d = b - a, rect = {min(a.x, b.x), min(a.y, b.y), abs(b.x - a.x), abs(b.y - a.y)}}
}

// The part of a segment inside a box, as the parameters t of a + t * d in [0, 1] (the slab method). `hit` is false when the segment misses the box; touching an edge counts as a hit. A box
// may reach to +-max(f32) (the nodes at the border of the tree extend outward: elements outside of the bounds sit there).
@(private)
segmentBox :: proc(a: Vec2, d: Vec2, low: Vec2, high: Vec2) -> (enter: f32, exit: f32, hit: bool) {
    enter, exit = 0, 1
    for axis in 0 ..< 2 {
        if d[axis] == 0 {
            if a[axis] < low[axis] || a[axis] > high[axis] { return 0, 0, false }
            continue
        }
        inverse: f32 = 1 / d[axis]
        near: f32 = (low[axis] - a[axis]) * inverse
        far: f32 = (high[axis] - a[axis]) * inverse
        if near > far { near, far = far, near }
        enter = max(enter, near)
        exit = min(exit, far)
        if enter > exit { return 0, 0, false }
    }
    return enter, exit, true
}

// Squared distance from a point to a box (0 inside)
@(private)
distanceSquaredToBox :: proc(point: Vec2, low: Vec2, high: Vec2) -> f32 {
    dx: f32 = point.x - clamp(point.x, low.x, high.x)
    dy: f32 = point.y - clamp(point.y, low.y, high.y)
    return dx * dx + dy * dy
}

// Can the shape reach into the box? For the nodes of a circle and a segment query, so it is generous (touching counts)
@(private)
probeHitsExtent :: proc(probe: ^Probe, low: Vec2, high: Vec2) -> bool {
    switch probe.kind {
    case .CIRCLE: return distanceSquaredToBox(probe.center, low, high) <= probe.radius * probe.radius
    case .SEGMENT:
        _, _, hit := segmentBox(probe.a, probe.d, low, high)
        return hit
    case .RECT, .POINT: return RectOverlaps(probe.rect, {low.x, low.y, high.x - low.x, high.y - low.y})
    }
    return false
}

// Does the shape overlap the rectangle of an element? Areas overlap when they share more than an edge; a segment that only touches or runs along an edge counts as a hit
@(private)
probeHitsRect :: proc(probe: ^Probe, rect: Rect) -> bool {
    switch probe.kind {
    case .RECT: return RectOverlaps(rect, probe.rect)
    case .POINT: return RectContainsPoint(rect, {probe.rect.x, probe.rect.y})
    case .CIRCLE: return distanceSquaredToBox(probe.center, {rect.x, rect.y}, {rect.x + rect.w, rect.y + rect.h}) < probe.radius * probe.radius
    case .SEGMENT:
        _, _, hit := segmentBox(probe.a, probe.d, {rect.x, rect.y}, {rect.x + rect.w, rect.y + rect.h})
        return hit
    }
    return false
}

// The box of a child node: the quadrant of the parent's box split at the centre of its area. The outermost nodes keep reaching to +-max(f32), so a shape outside of the bounds still finds the
// elements that sit in the border leaves.
@(private)
extentChild :: proc(low: Vec2, high: Vec2, area: Area, quadrant: int) -> (child_low: Vec2, child_high: Vec2) {
    child_low, child_high = low, high
    if quadrant & 1 != 0 { child_low.x = area.cx } else { child_high.x = area.cx }
    if quadrant & 2 != 0 { child_low.y = area.cy } else { child_high.y = area.cy }
    return
}

@(private)
EXTENT_LOW :: Vec2{-max(f32), -max(f32)}
@(private)
EXTENT_HIGH :: Vec2{max(f32), max(f32)}
