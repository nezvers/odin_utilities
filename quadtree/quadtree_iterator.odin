// Queries without a result slice and without a callback: ask for the next hit, stop whenever you have what you need. Rectangle and point queries of the three trees, circle queries of the immediate and the
// retained tree (segment queries mark the elements they report, which an iterator that may be abandoned cannot clean up: use their slice version).
//
//     it: quadtree.QueryIterator
//     quadtree.QuadtreeQueryBegin(&it, &tree, rect, omit = me)
//     for item in quadtree.QuadtreeQueryNext(&tree, &it) { if wanted(item) { break } }
//
// The iterator is a plain value with a small fixed stack (nothing to free, it can be dropped any time, one per thread when threads query). It reads the tree: do not insert, remove or move while one is
// active. It needs no marks because an element is reported by the one leaf that holds the corner of its overlap with the query (see leafQueryOwned), so any number of iterators may run at once.
package quadtree

@(private)
ITERATOR_STACK :: QUADTREE_MAX_DEPTH + 2

@(private)
IteratorFrame :: struct {
    node: i32,
    next: i32,                  // the next quadrant to look at
    area: Area,
    low: Vec2,                  // the box of the node, reaching outward at the border of the tree
    high: Vec2,
}

QueryIterator :: struct {
    stack: [ITERATOR_STACK]IteratorFrame,
    depth: int,
    link: i32,                  // the next link of the leaf being scanned, -1 for none
    leaf_low: Vec2,
    leaf_high: Vec2,
    probe: Probe,
    omit: Item,
    omit_handle: Handle,
}

// Start a rectangle query. Take the hits with QuadtreeQueryNext
QuadtreeQueryBegin :: proc(it: ^QueryIterator, tree: ^Quadtree($E, $N, $L), rect: Rect, omit: Item = ITEM_NONE) {
    iteratorBegin(it, rootArea(tree), probeRect(rect))
    it.omit = omit
}

// Start a point query: the elements whose rectangle contains the point
QuadtreeQueryPointBegin :: proc(it: ^QueryIterator, tree: ^Quadtree($E, $N, $L), point: Vec2) {
    iteratorBegin(it, rootArea(tree), probePoint(point))
}

// Start a circle query: the elements whose rectangle the circle overlaps (a rectangle that only touches it does not count)
QuadtreeQueryCircleBegin :: proc(it: ^QueryIterator, tree: ^Quadtree($E, $N, $L), center: Vec2, radius: f32, omit: Item = ITEM_NONE) {
    iteratorBegin(it, rootArea(tree), probeCircle(center, radius))
    it.omit = omit
}

// The next item, `ok` is false when there are no more. Each element comes once
QuadtreeQueryNext :: proc(tree: ^Quadtree($E, $N, $L), it: ^QueryIterator) -> (item: Item, ok: bool) {
    for {
        link: i32 = iteratorNext(tree, it) or_return
        item = tree.elements[tree.links[link].element].item
        if item != it.omit { return item, true }
    }
}

QuadtreeRetainedQueryBegin :: proc(it: ^QueryIterator, tree: ^QuadtreeRetained($E, $N, $L), rect: Rect, omit: Handle = HandleNone) {
    iteratorBegin(it, retainedRootArea(tree), probeRect(rect))
    it.omit_handle = omit
}

QuadtreeRetainedQueryCircleBegin :: proc(it: ^QueryIterator, tree: ^QuadtreeRetained($E, $N, $L), center: Vec2, radius: f32, omit: Handle = HandleNone) {
    iteratorBegin(it, retainedRootArea(tree), probeCircle(center, radius))
    it.omit_handle = omit
}

QuadtreeRetainedQueryPointBegin :: proc(it: ^QueryIterator, tree: ^QuadtreeRetained($E, $N, $L), point: Vec2) {
    iteratorBegin(it, retainedRootArea(tree), probePoint(point))
}

QuadtreeRetainedQueryNext :: proc(tree: ^QuadtreeRetained($E, $N, $L), it: ^QueryIterator) -> (handle: Handle, ok: bool) {
    for {
        link: i32 = iteratorNext(tree, it) or_return
        handle = tree.links[link].element
        if handle != it.omit_handle { return handle, true }
    }
}

// The chunked world: the chunks that can reach into the query are visited one after the other, each with the iterator of its tree
QuadtreeChunksIterator :: struct {
    rect: WorldRect,
    point: bool,
    omit: Item,
    first_x, last_x, first_y, last_y: int,
    cx, cy: int,                // the coordinates of the next chunk to look at
    slot: int,                  // the next slot, when the rectangle covers more chunks than there are slots
    by_slot: bool,
    current: int,               // the slot of the chunk being iterated
    active: bool,
    inner: QueryIterator,
}

QuadtreeChunksQueryBegin :: proc(it: ^QuadtreeChunksIterator, world: ^QuadtreeChunks($W, $H, $E, $N, $L), rect: WorldRect, omit: Item = ITEM_NONE) {
    chunksIteratorBegin(it, world, rect, false, omit)
}

QuadtreeChunksQueryPointBegin :: proc(it: ^QuadtreeChunksIterator, world: ^QuadtreeChunks($W, $H, $E, $N, $L), point: WorldVec) {
    chunksIteratorBegin(it, world, {point.x, point.y, 0, 0}, true, ITEM_NONE)
}

QuadtreeChunksQueryNext :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), it: ^QuadtreeChunksIterator) -> (item: Item, ok: bool) {
    for {
        if it.active {
            chunk: ^QuadtreeChunk(E, N, L) = &world.chunks[it.current]
            if link, found := iteratorNext(&chunk.tree, &it.inner); found {
                item = chunk.tree.elements[chunk.tree.links[link].element].item
                if item != it.omit { return item, true }
                continue
            }
            it.active = false
        }
        chunk: ^QuadtreeChunk(E, N, L) = chunksIteratorChunk(world, it) or_return
        local: Rect = chunksLocal(world, chunk, it.rect)
        iteratorBegin(&it.inner, rootArea(&chunk.tree), probePoint({local.x, local.y}) if it.point else probeRect(local))
        it.current = int(uintptr(chunk) - uintptr(&world.chunks[0])) / size_of(QuadtreeChunk(E, N, L))
        it.active = true
    }
}

// ------------------------------------------------------------------------------------------------------------------------

@(private)
iteratorBegin :: proc(it: ^QueryIterator, root: Area, probe: Probe) {
    it.probe = probe
    it.link = -1
    it.omit = ITEM_NONE
    it.omit_handle = HandleNone
    it.stack[0] = {node = 0, next = 0, area = root, low = EXTENT_LOW, high = EXTENT_HIGH}
    it.depth = 1
}

// The next link that passes the test of leafQueryOwned, for both trees (they share the node and the link layout). The stack holds the branches that still have quadrants to visit; a leaf is scanned link by link
@(private)
iteratorNext :: proc(tree: ^$T, it: ^QueryIterator) -> (link: i32, ok: bool) {
    rect: Rect = it.probe.rect
    for {
        if it.link != -1 {
            link = it.link
            it.link = tree.links[link].next
            if probeOwns(&it.probe, tree.links[link].rect, it.leaf_low, it.leaf_high) { return link, true }
            continue
        }
        if it.depth == 0 { return -1, false }
        frame: ^IteratorFrame = &it.stack[it.depth - 1]
        if tree.nodes[frame.node].count >= 0 {
            it.link = tree.nodes[frame.node].first
            it.leaf_low = frame.low
            it.leaf_high = frame.high
            it.depth -= 1
            continue
        }
        hit: [4]bool = quadrants(frame.area, rect)
        quadrant: i32 = frame.next
        for quadrant < 4 && !hit[quadrant] { quadrant += 1 }
        if quadrant >= 4 {
            it.depth -= 1
            continue
        }
        frame.next = quadrant + 1
        child_low, child_high := extentChild(frame.low, frame.high, frame.area, int(quadrant))
        it.stack[it.depth] = {node = tree.nodes[frame.node].first + quadrant, next = 0, area = areaChild(frame.area, int(quadrant)), low = child_low, high = child_high}
        it.depth += 1
    }
}

@(private)
chunksIteratorBegin :: proc(it: ^QuadtreeChunksIterator, world: ^QuadtreeChunks($W, $H, $E, $N, $L), rect: WorldRect, point: bool, omit: Item) {
    it.rect = rect
    it.point = point
    it.omit = omit
    // the items that can reach into the rectangle have their top left corner up to `max_item_size` before it
    it.first_x = QuadtreeChunksCoord(world, rect.x - world.max_item_size)
    it.last_x = QuadtreeChunksCoord(world, rect.x + rect.w)
    it.first_y = QuadtreeChunksCoord(world, rect.y - world.max_item_size)
    it.last_y = QuadtreeChunksCoord(world, rect.y + rect.h)
    it.cx = it.first_x
    it.cy = it.first_y
    it.slot = 0
    it.by_slot = (it.last_x - it.first_x + 1) * (it.last_y - it.first_y + 1) > int(W * H)
    it.active = false
}

@(private)
chunksIteratorChunk :: proc(world: ^QuadtreeChunks($W, $H, $E, $N, $L), it: ^QuadtreeChunksIterator) -> (chunk: ^QuadtreeChunk(E, N, L), ok: bool) {
    if it.by_slot {
        for it.slot < len(world.chunks) {
            candidate: ^QuadtreeChunk(E, N, L) = &world.chunks[it.slot]
            it.slot += 1
            if candidate.loaded && candidate.cx >= it.first_x && candidate.cx <= it.last_x && candidate.cy >= it.first_y && candidate.cy <= it.last_y { return candidate, true }
        }
        return nil, false
    }
    for it.cy <= it.last_y {
        for it.cx <= it.last_x {
            cx: int = it.cx
            it.cx += 1
            if found, loaded := chunksFind(world, cx, it.cy); loaded { return found, true }
        }
        it.cx = it.first_x
        it.cy += 1
    }
    return nil, false
}
