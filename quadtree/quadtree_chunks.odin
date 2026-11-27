// Chunked quadtree for big worlds: the world is a grid of chunks, each chunk has its own immediate mode `Quadtree` in LOCAL coordinates (relative to the chunk corner), and only a window of chunks
// around the player is loaded. What it solves compared to one big tree:
// - precision: world positions are f64, the trees only see small f32 offsets, so a world a million units from the origin still has fine leaves
// - memory: it follows the loaded window (W x H chunks), not the size of the world
// - streaming: `QuadtreeChunksStream` unloads far chunks and loads the new ones near the center, calling your `fill` for every loaded chunk
// How an element is placed (a "loose grid"): it lives in exactly ONE chunk, the one that holds its top left corner. It may stick out of that chunk by up to `max_item_size`. A query looks at the chunks
// whose elements can reach into the query rectangle (the query grown by `max_item_size`), so every element is reported once, with no duplicates across chunks and no copies per overlapped chunk.
// An item bigger than `max_item_size` is refused: keep terrain, rivers and huge triggers in a separate list.
// Chunks are a ring: coordinate (cx, cy) goes to slot (cx mod W, cy mod H), so a lookup is O(1) and the window can slide forever. Two loaded chunks must not share a slot: unload first (`Stream` does).
// Like the other trees it is immediate mode per chunk: load fills a chunk, `QuadtreeChunksClear` empties every chunk but keeps it loaded (a second world for the moving things, refilled each frame).
package quadtree

WorldVec :: [2]f64

// x, y = top left corner, in world units
WorldRect :: struct {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
}

// Called by `QuadtreeChunksStream` for a chunk that was just loaded (fill it, with QuadtreeChunksInsert) or is about to be unloaded
QuadtreeChunksProc :: proc(user: rawptr, cx: int, cy: int)

// Called for every node by QuadtreeChunksVisit, in world coordinates
QuadtreeChunksNodeProc :: proc(user: rawptr, rect: WorldRect, depth: int, leaf: bool, count: int)

QuadtreeChunk :: struct($E: uint, $N: uint, $L: uint) {
    cx: int,
    cy: int,
    loaded: bool,
    tree: Quadtree(E, N, L),
}

// W x H = the window of chunks, E / N / L = the capacities of the tree of ONE chunk (see Quadtree).
// Put it in a global or in your own struct: it holds all of its memory (W * H trees).
QuadtreeChunks :: struct($W: uint, $H: uint, $E: uint, $N: uint, $L: uint) {
    chunk_size: f64,
    max_item_size: f64,
    max_elements: int,
    max_depth: int,
    chunks: [W * H]QuadtreeChunk(E, N, L),
}

// `chunk_size`: side of a chunk in world units. `max_item_size`: the largest width or height of an item (at most `chunk_size`). `max_elements` / `max_depth` are for the tree of each chunk.
// Unloads everything.
QuadtreeChunksInit :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), chunk_size: f64, max_item_size: f64, max_elements: int = 8, max_depth: int = 6) {
    assert(chunk_size > 0)
    assert(max_item_size > 0 && max_item_size <= chunk_size)
    assert(W >= 1 && H >= 1)
    world.chunk_size = chunk_size
    world.max_item_size = max_item_size
    world.max_elements = max_elements
    world.max_depth = max_depth
    for &chunk in world.chunks { chunk.loaded = false }
}

// The chunk coordinate that holds a world coordinate
QuadtreeChunksCoord :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), value: f64) -> int {
    scaled: f64 = value / world.chunk_size
    cell: int = int(scaled)
    return cell - 1 if f64(cell) > scaled else cell    // int() cuts toward zero: fix negatives
}

// The world rectangle of a chunk
QuadtreeChunksBounds :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), cx: int, cy: int) -> WorldRect {
    return {f64(cx) * world.chunk_size, f64(cy) * world.chunk_size, world.chunk_size, world.chunk_size}
}

QuadtreeChunksIsLoaded :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), cx: int, cy: int) -> bool {
    _, ok := chunksFind(world, cx, cy)
    return ok
}

// Make a chunk available (empty). True when it is loaded afterwards, also when it already was (then its content stays). False when its slot holds another loaded chunk: unload that one first
QuadtreeChunksLoad :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), cx: int, cy: int) -> bool {
    chunk: ^QuadtreeChunk(E, N, L) = chunksSlot(world, cx, cy)
    if chunk.loaded { return chunk.cx == cx && chunk.cy == cy }
    chunk.cx = cx
    chunk.cy = cy
    chunk.loaded = true
    QuadtreeInit(&chunk.tree, {0, 0, f32(world.chunk_size), f32(world.chunk_size)}, world.max_elements, world.max_depth)
    return true
}

// Returns false when the chunk was not loaded
QuadtreeChunksUnload :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), cx: int, cy: int) -> bool {
    chunk: ^QuadtreeChunk(E, N, L) = chunksFind(world, cx, cy) or_return
    chunk.loaded = false
    return true
}

// Empty the tree of one chunk, it stays loaded
QuadtreeChunksClearChunk :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), cx: int, cy: int) -> bool {
    chunk: ^QuadtreeChunk(E, N, L) = chunksFind(world, cx, cy) or_return
    QuadtreeClear(&chunk.tree)
    return true
}

// Empty the tree of every loaded chunk (the first call of a frame for a world of moving things)
QuadtreeChunksClear :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L)) {
    for &chunk in world.chunks {
        if chunk.loaded { QuadtreeClear(&chunk.tree) }
    }
}

// Put an item into the chunk that holds the top left corner of `rect`. Fails (nothing changes) when that chunk is not loaded, the rectangle is bigger than `max_item_size`, or the chunk's tree is full
QuadtreeChunksInsert :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), rect: WorldRect, item: Item) -> bool {
    if rect.w > world.max_item_size || rect.h > world.max_item_size { return false }
    chunk: ^QuadtreeChunk(E, N, L) = chunksFind(world, QuadtreeChunksCoord(world, rect.x), QuadtreeChunksCoord(world, rect.y)) or_return
    return QuadtreeInsert(&chunk.tree, chunksLocal(world, chunk, rect), item)
}

// Items whose rectangle overlaps `rect` (each once, `omit` left out), from the loaded chunks. Returns how many were written: results are limited by the size of `out`.
// Every query takes an optional `session` (see QuerySession): without it the elements are marked in the trees (one thread at a time), with it the world is only read. One session serves all
// the chunks (its stamps need `E` entries).
QuadtreeChunksQuery :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), rect: WorldRect, out: []Item, omit: Item = ITEM_NONE, session: ^QuerySession = nil) -> int {
    return chunksQuery(world, {kind = .RECT, rect = rect}, out, omit, session)
}

// Items whose rectangle contains the point
QuadtreeChunksQueryPoint :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), point: WorldVec, out: []Item, session: ^QuerySession = nil) -> int {
    return chunksQuery(world, {kind = .POINT, rect = {point.x, point.y, 0, 0}}, out, ITEM_NONE, session)
}

// Items whose rectangle overlaps the circle (a rectangle that only touches it does not count)
QuadtreeChunksQueryCircle :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), center: WorldVec, radius: f64, out: []Item, omit: Item = ITEM_NONE, session: ^QuerySession = nil) -> int {
    probe: ChunkProbe = {kind = .CIRCLE, rect = {center.x - radius, center.y - radius, radius * 2, radius * 2}, center = center, radius = radius}
    return chunksQuery(world, probe, out, omit, session)
}

// Items whose rectangle the segment from `a` to `b` crosses (touching an edge counts, a segment inside a rectangle too), in no particular order. Chunks that the segment does not reach are skipped
QuadtreeChunksQuerySegment :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), a: WorldVec, b: WorldVec, out: []Item, omit: Item = ITEM_NONE, session: ^QuerySession = nil) -> int {
    return chunksQuery(world, chunksSegment(a, b), out, omit, session)
}

// The first item along the segment from `a` to `b` and `t` in [0, 1] (the hit is at a + t * (b - a)). Reads the world only, so it is thread safe without a session. The geometry is done in f32 relative to
// each chunk corner: a segment many chunks long gets a coarser `t` than a short one.
QuadtreeChunksSegmentFirst :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), a: WorldVec, b: WorldVec, omit: Item = ITEM_NONE) -> (item: Item, t: f32, hit: bool) {
    probe: ChunkProbe = chunksSegment(a, b)
    found: [W * H]^QuadtreeChunk(E, N, L)
    candidates: int = chunksCandidates(world, &probe, found[:])
    best: f32 = 2
    item = ITEM_NONE
    for i in 0 ..< candidates {
        local: Probe = chunksProbeLocal(world, found[i], &probe)
        reach: f32 = f32(world.chunk_size + world.max_item_size)
        enter, _, reached := segmentBox(local.a, local.d, {0, 0}, {reach, reach})
        if !reached || enter > best { continue }
        found_item, found_t, found_hit := QuadtreeSegmentFirst(&found[i].tree, local.a, local.a + local.d, omit)
        if found_hit && found_t < best {
            best = found_t
            item = found_item
        }
    }
    if item == ITEM_NONE { return ITEM_NONE, 0, false }
    return item, best, true
}

@(private)
chunksSegment :: proc(a: WorldVec, b: WorldVec) -> ChunkProbe {
    return {kind = .SEGMENT, rect = {min(a.x, b.x), min(a.y, b.y), abs(b.x - a.x), abs(b.y - a.y)}, a = a, b = b}
}

// Keep the square of chunks around `center` loaded: unload the chunks farther than `radius` chunks (`drop` is called before each), then load the missing ones (`fill` is called after each, to insert its items).
// `radius` chunks on each side must fit the window: 2 * radius + 1 <= W and <= H. Returns how many chunks were loaded and unloaded
QuadtreeChunksStream :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), center: WorldVec, radius: int, user: rawptr, fill: QuadtreeChunksProc, drop: QuadtreeChunksProc = nil) -> (loaded: int, unloaded: int) {
    assert(radius >= 0 && 2 * radius + 1 <= int(W) && 2 * radius + 1 <= int(H))
    center_x: int = QuadtreeChunksCoord(world, center.x)
    center_y: int = QuadtreeChunksCoord(world, center.y)
    for &chunk in world.chunks {
        if !chunk.loaded { continue }
        if abs(chunk.cx - center_x) <= radius && abs(chunk.cy - center_y) <= radius { continue }
        if drop != nil { drop(user, chunk.cx, chunk.cy) }
        chunk.loaded = false
        unloaded += 1
    }
    for cy in center_y - radius ..= center_y + radius {
        for cx in center_x - radius ..= center_x + radius {
            if QuadtreeChunksIsLoaded(world, cx, cy) { continue }
            if !QuadtreeChunksLoad(world, cx, cy) { continue }
            loaded += 1
            if fill != nil { fill(user, cx, cy) }
        }
    }
    return
}

// Chunks that are loaded
QuadtreeChunksLoadedCount :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L)) -> int {
    count: int
    for &chunk in world.chunks {
        if chunk.loaded { count += 1 }
    }
    return count
}

// Items in all loaded chunks
QuadtreeChunksLen :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L)) -> int {
    count: int
    for &chunk in world.chunks {
        if chunk.loaded { count += QuadtreeLen(&chunk.tree) }
    }
    return count
}

// Nodes and links in use over all loaded chunks, and the largest of one chunk (to size E, N and L of a chunk)
QuadtreeChunksUsage :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L)) -> (nodes: int, links: int, most_nodes: int, most_links: int) {
    for &chunk in world.chunks {
        if !chunk.loaded { continue }
        chunk_nodes, chunk_links := QuadtreeUsage(&chunk.tree)
        nodes += chunk_nodes
        links += chunk_links
        most_nodes = max(most_nodes, chunk_nodes)
        most_links = max(most_links, chunk_links)
    }
    return
}

// Walk the nodes of every loaded chunk, in world coordinates. For drawing the trees
QuadtreeChunksVisit :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), user: rawptr, visit: QuadtreeChunksNodeProc) {
    for &chunk in world.chunks {
        if !chunk.loaded { continue }
        adapter: ChunksVisit = {user = user, visit = visit, origin_x = f64(chunk.cx) * world.chunk_size, origin_y = f64(chunk.cy) * world.chunk_size}
        QuadtreeVisit(&chunk.tree, &adapter, chunksVisitNode)
    }
}

// ------------------------------------------------------------------------------------------------------------------------

@(private)
ChunksVisit :: struct {
    user: rawptr,
    visit: QuadtreeChunksNodeProc,
    origin_x: f64,
    origin_y: f64,
}

@(private)
chunksVisitNode :: proc(user: rawptr, rect: Rect, depth: int, leaf: bool, count: int) {
    adapter: ^ChunksVisit = cast(^ChunksVisit)user
    adapter.visit(adapter.user, {adapter.origin_x + f64(rect.x), adapter.origin_y + f64(rect.y), f64(rect.w), f64(rect.h)}, depth, leaf, count)
}

@(private)
chunksSlot :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), cx: int, cy: int) -> ^QuadtreeChunk(E, N, L) {
    column: int = ((cx % int(W)) + int(W)) % int(W)
    row: int = ((cy % int(H)) + int(H)) % int(H)
    return &world.chunks[row * int(W) + column]
}

@(private)
chunksFind :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), cx: int, cy: int) -> (chunk: ^QuadtreeChunk(E, N, L), ok: bool) {
    chunk = chunksSlot(world, cx, cy)
    return chunk, chunk.loaded && chunk.cx == cx && chunk.cy == cy
}

// A world rectangle relative to the corner of a chunk: the subtraction is done in f64, the result is small
@(private)
chunksLocal :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), chunk: ^QuadtreeChunk(E, N, L), rect: WorldRect) -> Rect {
    return {f32(rect.x - f64(chunk.cx) * world.chunk_size), f32(rect.y - f64(chunk.cy) * world.chunk_size), f32(rect.w), f32(rect.h)}
}

// A query shape in world units (f64). The trees get it back as a local f32 `Probe` for each chunk: the subtraction of the corner of the chunk is done in f64, the result is small
@(private)
ChunkProbe :: struct {
    kind: ShapeKind,
    rect: WorldRect,            // the bounding rectangle: the chunks to look at are picked with it
    center: WorldVec,
    radius: f64,
    a, b: WorldVec,
}

@(private)
chunksProbeLocal :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), chunk: ^QuadtreeChunk(E, N, L), probe: ^ChunkProbe) -> Probe {
    origin_x: f64 = f64(chunk.cx) * world.chunk_size
    origin_y: f64 = f64(chunk.cy) * world.chunk_size
    switch probe.kind {
    case .RECT: return probeRect(chunksLocal(world, chunk, probe.rect))
    case .POINT:
        local: Rect = chunksLocal(world, chunk, probe.rect)
        return probePoint({local.x, local.y})
    case .CIRCLE: return probeCircle({f32(probe.center.x - origin_x), f32(probe.center.y - origin_y)}, f32(probe.radius))
    case .SEGMENT: return probeSegment({f32(probe.a.x - origin_x), f32(probe.a.y - origin_y)}, {f32(probe.b.x - origin_x), f32(probe.b.y - origin_y)})
    }
    return {}
}

// The chunks whose items can reach into the bounding rectangle of the probe (and for circles and segments, whose area the shape can really reach)
@(private)
chunksCandidates :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), probe: ^ChunkProbe, found: []^QuadtreeChunk(E, N, L)) -> int {
    rect: WorldRect = probe.rect
    // the items that can reach into the rectangle have their top left corner up to `max_item_size` before it
    first_x: int = QuadtreeChunksCoord(world, rect.x - world.max_item_size)
    last_x: int = QuadtreeChunksCoord(world, rect.x + rect.w)
    first_y: int = QuadtreeChunksCoord(world, rect.y - world.max_item_size)
    last_y: int = QuadtreeChunksCoord(world, rect.y + rect.h)
    count: int
    if (last_x - first_x + 1) * (last_y - first_y + 1) > int(W * H) {
        // a huge rectangle: asking every slot is cheaper than every coordinate
        for &chunk in world.chunks {
            if !chunk.loaded || chunk.cx < first_x || chunk.cx > last_x || chunk.cy < first_y || chunk.cy > last_y { continue }
            if chunkReachable(world, &chunk, probe) {
                found[count] = &chunk
                count += 1
            }
        }
        return count
    }
    for cy in first_y ..= last_y {
        for cx in first_x ..= last_x {
            chunk: ^QuadtreeChunk(E, N, L) = chunksFind(world, cx, cy) or_continue
            if chunkReachable(world, chunk, probe) {
                found[count] = chunk
                count += 1
            }
        }
    }
    return count
}

// The items of a chunk lie in its square and stick out by up to `max_item_size`: a circle or a segment that misses that box finds nothing in the chunk (a long diagonal segment skips most of the
// chunks of its bounding rectangle)
@(private)
chunkReachable :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), chunk: ^QuadtreeChunk(E, N, L), probe: ^ChunkProbe) -> bool {
    if probe.kind == .RECT || probe.kind == .POINT { return true }
    local: Probe = chunksProbeLocal(world, chunk, probe)
    reach: f32 = f32(world.chunk_size + world.max_item_size)
    return probeHitsExtent(&local, {0, 0}, {reach, reach})
}

@(private)
chunksQuery :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), probe: ChunkProbe, out: []Item, omit: Item, session: ^QuerySession) -> int {
    probe := probe
    found: [W * H]^QuadtreeChunk(E, N, L)
    candidates: int = chunksCandidates(world, &probe, found[:])
    count: int
    for i in 0 ..< candidates {
        if count >= len(out) { break }
        local: Probe = chunksProbeLocal(world, found[i], &probe)
        count += treeQuery(&found[i].tree, local, out[count:], omit, session)
    }
    return count
}
