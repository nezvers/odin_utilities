package quadtree

import "core:math"

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

// Does the leaf with the box (low, high] own the hit of this element? The test of a rectangle, a point or a circle query without marks. An element sits in every leaf it overlaps, so it is reported only by
// the leaf that holds ONE point of the element that does not depend on the leaf: for a rectangle the top left corner of the overlap with the query, for a circle the point of the element nearest to the
// center. That point lies in exactly one leaf (the same centre compare as the descent: left and top when <=, the outermost boxes reach to +-max(f32)), the leaf holds the element (the point is in the element)
// and the leaf is visited (the point is inside of the query: strictly inside for a circle, since the circle test is `<`). A point query is in one leaf only and needs nothing.
// Not for segments: the entry point of a segment is rounded and might fall outside of the leaves that hold the element, so segment queries keep their marks.
@(private)
probeOwns :: #force_inline proc(probe: ^Probe, rect: Rect, low: Vec2, high: Vec2) -> bool {
    corner: Vec2
    switch probe.kind {
    case .POINT: return RectContainsPoint(rect, {probe.rect.x, probe.rect.y})
    case .RECT:
        if !RectOverlaps(rect, probe.rect) { return false }
        corner = {max(rect.x, probe.rect.x), max(rect.y, probe.rect.y)}
    case .CIRCLE:
        corner = {clamp(probe.center.x, rect.x, rect.x + rect.w), clamp(probe.center.y, rect.y, rect.y + rect.h)}
        dx: f32 = corner.x - probe.center.x
        dy: f32 = corner.y - probe.center.y
        if dx * dx + dy * dy >= probe.radius * probe.radius { return false }
    case .SEGMENT: return false
    }
    return corner.x > low.x && corner.x <= high.x && corner.y > low.y && corner.y <= high.y
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

// ------------------------------------------------------------------------------------------------------------------------
// Nearest and k-nearest: the k best so far live in the memory of the caller (`items` and `distances`, sorted, nearest first). A walk visits the nearest child first and skips every node that cannot
// beat the k-th best, so it needs no heap, no allocation and no marks (an element seen in two leaves is found in the short result list instead): it only reads the tree, which makes it thread safe.

@(private)
Nearest :: struct($T: typeid) {
    items: []T,
    distances: []f32,           // squared while searching
    count: int,
    limit: f32,                 // squared `max_distance`
    omit: T,
}

// Could something at this squared distance still enter the result? (the limit is inclusive; a tie with the k-th best does not replace it)
@(private)
nearestWants :: proc(nearest: ^Nearest($T), squared: f32) -> bool {
    if nearest.count < len(nearest.items) { return squared <= nearest.limit }
    return nearest.count > 0 && squared < nearest.distances[nearest.count - 1]
}

@(private)
nearestAdd :: proc(nearest: ^Nearest($T), item: T, squared: f32) {
    for i in 0 ..< nearest.count { if nearest.items[i] == item { return } }
    slot: int = min(nearest.count, len(nearest.items) - 1)
    for slot > 0 && nearest.distances[slot - 1] > squared {
        nearest.items[slot] = nearest.items[slot - 1]
        nearest.distances[slot] = nearest.distances[slot - 1]
        slot -= 1
    }
    nearest.items[slot] = item
    nearest.distances[slot] = squared
    if nearest.count < len(nearest.items) { nearest.count += 1 }
}

// Squared distances to real ones, the count for the caller
@(private)
nearestFinish :: proc(distances: []f32, count: int) -> int {
    for i in 0 ..< count { distances[i] = math.sqrt(distances[i]) }
    return count
}

// The four children of a branch, nearest first: boxes, squared distances and the order
@(private)
nearestChildren :: proc(area: Area, low: Vec2, high: Vec2, point: Vec2) -> (lows: [4]Vec2, highs: [4]Vec2, distances: [4]f32, order: [4]int) {
    order = {0, 1, 2, 3}
    for quadrant in 0 ..< 4 {
        lows[quadrant], highs[quadrant] = extentChild(low, high, area, quadrant)
        distances[quadrant] = distanceSquaredToBox(point, lows[quadrant], highs[quadrant])
    }
    for i in 1 ..< 4 {
        key: int = order[i]
        j: int = i
        for j > 0 && distances[order[j - 1]] > distances[key] {
            order[j] = order[j - 1]
            j -= 1
        }
        order[j] = key
    }
    return
}
