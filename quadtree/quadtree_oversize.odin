package quadtree

// Items bigger than `max_item_size` in a chunked world: terrain, rivers, huge triggers. They cannot live in a chunk (the loose grid needs a bound on how far an item sticks out), so they go into a
// short list that every query of the world scans after the chunks, linearly and in f64. Give the list its memory with `QuadtreeChunksOversize`; without it a big item is refused as before.
// The list is not tied to the chunks: it is not emptied by an unload, only by `QuadtreeChunksOversizeClear` or `QuadtreeChunksClear`. Keep it short (tens of items): a hundred thousand would be a loop
// over a hundred thousand rectangles at every query.

OversizeEntry :: struct {
    rect: WorldRect,
    item: Item,
}

// The memory of the list (it stays yours); the list is empty after the call
QuadtreeChunksOversize :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), storage: []OversizeEntry) {
    world.oversize = storage
    world.oversize_count = 0
}

QuadtreeChunksOversizeClear :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L)) {
    world.oversize_count = 0
}

QuadtreeChunksOversizeCount :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L)) -> int {
    return world.oversize_count
}

@(private)
oversizeAdd :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), rect: WorldRect, item: Item) -> bool {
    if world.oversize_count >= len(world.oversize) { return false }
    world.oversize[world.oversize_count] = {rect, item}
    world.oversize_count += 1
    return true
}

// The f64 version of `probeHitsRect`: the same rules (areas overlap when they share more than an edge, a point is inside at the left and top edge only, a circle that only touches does not count,
// a segment that touches an edge hits)
@(private)
oversizeHits :: proc(probe: ^ChunkProbe, rect: WorldRect) -> bool {
    switch probe.kind {
    case .RECT:
        return probe.rect.x < rect.x + rect.w && probe.rect.x + probe.rect.w > rect.x && probe.rect.y < rect.y + rect.h && probe.rect.y + probe.rect.h > rect.y
    case .POINT:
        return probe.rect.x >= rect.x && probe.rect.x < rect.x + rect.w && probe.rect.y >= rect.y && probe.rect.y < rect.y + rect.h
    case .CIRCLE:
        return oversizeDistanceSquared(probe.center, rect) < probe.radius * probe.radius
    case .SEGMENT:
        _, hit := oversizeSegmentEnter(probe, rect)
        return hit
    }
    return false
}

@(private)
oversizeDistanceSquared :: proc(point: WorldVec, rect: WorldRect) -> f64 {
    dx: f64 = point.x - clamp(point.x, rect.x, rect.x + rect.w)
    dy: f64 = point.y - clamp(point.y, rect.y, rect.y + rect.h)
    return dx * dx + dy * dy
}

// Where the segment of the probe enters the rectangle, as the parameter t in [0, 1] (the slab test of `segmentBox` in f64)
@(private)
oversizeSegmentEnter :: proc(probe: ^ChunkProbe, rect: WorldRect) -> (enter: f64, hit: bool) {
    start: [2]f64 = {probe.a.x, probe.a.y}
    delta: [2]f64 = {probe.b.x - probe.a.x, probe.b.y - probe.a.y}
    low: [2]f64 = {rect.x, rect.y}
    high: [2]f64 = {rect.x + rect.w, rect.y + rect.h}
    enter = 0
    exit: f64 = 1
    for axis in 0 ..< 2 {
        if delta[axis] == 0 {
            if start[axis] < low[axis] || start[axis] > high[axis] { return 0, false }
            continue
        }
        inverse: f64 = 1 / delta[axis]
        near: f64 = (low[axis] - start[axis]) * inverse
        far: f64 = (high[axis] - start[axis]) * inverse
        if near > far { near, far = far, near }
        enter = max(enter, near)
        exit = min(exit, far)
        if enter > exit { return 0, false }
    }
    return enter, true
}

// The items of the list that the probe hits, written into `out` (the part after the results of the chunks)
@(private)
oversizeQuery :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), probe: ^ChunkProbe, out: []Item, omit: Item) -> int {
    count: int
    for i in 0 ..< world.oversize_count {
        if count >= len(out) { break }
        entry: OversizeEntry = world.oversize[i]
        if entry.item != omit && oversizeHits(probe, entry.rect) {
            out[count] = entry.item
            count += 1
        }
    }
    return count
}
