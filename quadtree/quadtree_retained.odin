// Retained mode quadtree: the same broad phase as quadtree.odin, but the tree lives between frames. Elements are added once, get a stable `Handle` (a generation checked reference from
// `core:container/handle_map`), and are moved or removed one by one when they change, instead of rebuilding everything each frame. Use it when most of the scene stays where it is
// (static scenery, many sleeping objects) and only a few things move; when most things move every frame, the immediate mode tree (QuadtreeClear + QuadtreeInsert) is simpler and as fast.
// Memory is the same kind: fixed arrays, nothing grows, everything fails instead. It shares `Rect`, `Vec2`, the narrow phase helpers and `QuadtreeNodeProc` with quadtree.odin.
package quadtree

import hm "core:container/handle_map"

Handle :: hm.Handle32
HandleNone: Handle : {}

// A rectangle in the retained tree
RetainedElement :: struct {
    handle: Handle,     // Required by the handle map, set by QuadtreeRetainedAdd
    rect: Rect,
    ptr: rawptr,        // Generic way to carry user facing data
    stamp: u32,         // Runtime: the query that already reported this element (an element sits in several leaves)
}

// One element in one leaf. Public only so that the caller can size the scratch memory of QuadtreeRetainedCompact
RetainedLink :: struct {
    next: i32,
    element: Handle,
    rect: Rect,         // a copy of the rectangle of the element, see Link in quadtree.odin: queries test it without looking the element up
}

// E = elements (usable capacity is E - 1, the handle map keeps slot 0 as "no handle"), N = nodes (the root and groups of four), L = links (an element takes one for every leaf it overlaps).
// Put it in a global or in your own struct: it holds all of its memory.
QuadtreeRetained :: struct($E: uint, $N: uint, $L: uint) {
    bounds: Rect,               // Where the tree divides space. Rectangles outside still work: they sit in the border leaves
    max_elements: i32,          // A leaf with more elements splits
    max_depth: i32,
    elements: hm.Static_Handle_Map(E, RetainedElement, Handle),
    nodes: [N]Node,
    node_used: i32,             // Nodes handed out: the root, then four at a time
    group_free: i32,            // First of the freed groups of four (linked through `first`), -1 for none
    links: [L]RetainedLink,
    link_used: i32,             // Links handed out from the array so far
    link_free: i32,             // First of the freed links (linked through `next`), -1 for none
    links_in_use: i32,
    stamp: u32,
}

// Set the area and remove all elements. `max_elements` is how many a leaf takes before it splits, `max_depth` how often the space is divided at most
QuadtreeRetainedInit :: proc(tree: ^QuadtreeRetained($E, $N, $L), bounds: Rect, max_elements: int = 8, max_depth: int = 8) {
    assert(bounds.w > 0 && bounds.h > 0)
    assert(max_elements >= 1)
    assert(max_depth >= 0 && max_depth <= QUADTREE_MAX_DEPTH)
    assert(N >= 1 && L >= 1)
    tree.bounds = bounds
    tree.max_elements = i32(max_elements)
    tree.max_depth = i32(max_depth)
    QuadtreeRetainedClear(tree)
}

// Remove all elements, handles become invalid
QuadtreeRetainedClear :: proc(tree: ^QuadtreeRetained($E, $N, $L)) {
    hm.clear(&tree.elements)
    tree.nodes[0] = {first = -1, count = 0}
    tree.node_used = 1
    tree.group_free = -1
    tree.link_used = 0
    tree.link_free = -1
    tree.links_in_use = 0
    tree.stamp = 0
}

QuadtreeRetainedLen :: proc(tree: ^QuadtreeRetained($E, $N, $L)) -> uint {
    return hm.len(tree.elements)
}

// Nodes and links in use, to size N and L
QuadtreeRetainedUsage :: proc(tree: ^QuadtreeRetained($E, $N, $L)) -> (nodes: int, links: int) {
    free_nodes: int
    for group := tree.group_free; group != -1; group = tree.nodes[group].first { free_nodes += 4 }
    return int(tree.node_used) - free_nodes, int(tree.links_in_use)
}

// Add an element. Fails (nothing is changed) when the map, the nodes or the links are full
QuadtreeRetainedAdd :: proc(tree: ^QuadtreeRetained($E, $N, $L), rect: Rect, ptr: rawptr = nil) -> (handle: Handle, ok: bool) {
    handle, ok = hm.add(&tree.elements, RetainedElement{rect = rect, ptr = ptr})
    if !ok { return }
    if !retainedNodeAdd(tree, 0, retainedRootArea(tree), 0, handle, rect, true) {
        retainedNodeRemove(tree, 0, retainedRootArea(tree), handle, rect)
        hm.remove(&tree.elements, handle)
        return HandleNone, false
    }
    return
}

// Returns false when the handle is not valid
QuadtreeRetainedRemove :: proc(tree: ^QuadtreeRetained($E, $N, $L), handle: Handle) -> bool {
    element: ^RetainedElement = hm.get(&tree.elements, handle) or_return
    retainedNodeRemove(tree, 0, retainedRootArea(tree), handle, element.rect)
    return hm.remove(&tree.elements, handle)
}

QuadtreeRetainedGet :: proc(tree: ^QuadtreeRetained($E, $N, $L), handle: Handle) -> (element: ^RetainedElement, ok: bool) {
    return hm.get(&tree.elements, handle)
}

// Give an element another rectangle. When the links run out the move does not happen and the element stays where it was; only when it cannot even be put back
// (a split of a leaf used the freed links) it is removed and the handle is stale. Returns false in both cases
QuadtreeRetainedMove :: proc(tree: ^QuadtreeRetained($E, $N, $L), handle: Handle, rect: Rect) -> bool {
    element: ^RetainedElement = hm.get(&tree.elements, handle) or_return
    old: Rect = element.rect
    // a small step usually reaches the same leaves: then only the copies of the rectangle change, nothing is unlinked, linked or split
    if retainedNodeResize(tree, 0, retainedRootArea(tree), handle, old, rect) {
        element.rect = rect
        return true
    }
    retainedNodeRemove(tree, 0, retainedRootArea(tree), handle, old)
    element.rect = rect
    if retainedNodeAdd(tree, 0, retainedRootArea(tree), 0, handle, rect, true) { return true }
    retainedNodeRemove(tree, 0, retainedRootArea(tree), handle, rect)
    element.rect = old
    if !retainedNodeAdd(tree, 0, retainedRootArea(tree), 0, handle, old, true) {
        retainedNodeRemove(tree, 0, retainedRootArea(tree), handle, old)
        hm.remove(&tree.elements, handle)
    }
    return false
}

// Handles of the elements whose rectangle overlaps `rect` (each once, `omit` left out). Returns how many were written: results are limited by the size of `out`.
// Every query takes an optional `session`: without it the elements are marked in the tree (one thread at a time), with it the tree is only read (see QuerySession; its stamps need `E` entries,
// they are indexed by the slot of the handle).
QuadtreeRetainedQuery :: proc(tree: ^QuadtreeRetained($E, $N, $L), rect: Rect, out: []Handle, omit: Handle = HandleNone, session: ^QuerySession = nil) -> int {
    return retainedTreeQuery(tree, probeRect(rect), out, omit, session)
}

// Handles of the elements whose rectangle contains the point
QuadtreeRetainedQueryPoint :: proc(tree: ^QuadtreeRetained($E, $N, $L), point: Vec2, out: []Handle, session: ^QuerySession = nil) -> int {
    return retainedTreeQuery(tree, probePoint(point), out, HandleNone, session)
}

// Handles of the elements whose rectangle overlaps the circle (a rectangle that only touches it does not count)
QuadtreeRetainedQueryCircle :: proc(tree: ^QuadtreeRetained($E, $N, $L), center: Vec2, radius: f32, out: []Handle, omit: Handle = HandleNone, session: ^QuerySession = nil) -> int {
    return retainedTreeQuery(tree, probeCircle(center, radius), out, omit, session)
}

// Handles of the elements whose rectangle the segment from `a` to `b` crosses (touching an edge counts, a segment inside a rectangle too), in no particular order
QuadtreeRetainedQuerySegment :: proc(tree: ^QuadtreeRetained($E, $N, $L), a: Vec2, b: Vec2, out: []Handle, omit: Handle = HandleNone, session: ^QuerySession = nil) -> int {
    return retainedTreeQuery(tree, probeSegment(a, b), out, omit, session)
}

// The first element along the segment from `a` to `b`: its handle and `t` in [0, 1] (the hit is at a + t * (b - a)). Reads the tree only, so it is thread safe without a session.
QuadtreeRetainedSegmentFirst :: proc(tree: ^QuadtreeRetained($E, $N, $L), a: Vec2, b: Vec2, omit: Handle = HandleNone) -> (handle: Handle, t: f32, hit: bool) {
    probe: Probe = probeSegment(a, b)
    first: RetainedFirst = {omit = omit, t = 2}
    retainedNodeFirst(tree, 0, retainedRootArea(tree), EXTENT_LOW, EXTENT_HIGH, &probe, &first)
    if first.handle == HandleNone { return HandleNone, 0, false }
    return first.handle, first.t, true
}

// The `out` / `distances` (as long as the shorter one) nearest elements to `point`, nearest first, with their distances. See QuadtreeNearest. Reads the tree only: thread safe
QuadtreeRetainedNearest :: proc(tree: ^QuadtreeRetained($E, $N, $L), point: Vec2, out: []Handle, distances: []f32, omit: Handle = HandleNone, max_distance: f32 = max(f32)) -> int {
    k: int = min(len(out), len(distances))
    if k == 0 { return 0 }
    nearest: Nearest(Handle) = {items = out[:k], distances = distances[:k], limit = max_distance * max_distance, omit = omit}
    retainedNodeNearest(tree, 0, retainedRootArea(tree), EXTENT_LOW, EXTENT_HIGH, point, &nearest)
    return nearestFinish(nearest.distances, nearest.count)
}

// Optional: put the links of every leaf next to each other in memory (see QuadtreeCompact), for faster queries and moves after a lot of adds, removes and moves scattered them. `scratch` is at least
// `QuadtreeRetainedUsage` links long. Handles stay valid, nothing else changes
QuadtreeRetainedCompact :: proc(tree: ^QuadtreeRetained($E, $N, $L), scratch: []RetainedLink) {
    assert(len(scratch) >= int(tree.links_in_use), "the scratch of QuadtreeRetainedCompact is smaller than the links in use")
    used: i32
    retainedCompactNode(tree, 0, scratch, &used)
    assert(used == tree.links_in_use)
    copy(tree.links[:used], scratch[:used])
    tree.link_used = used
    tree.link_free = -1
}

// Merge four empty leaves into their parent, so the nodes can be used again. Call it now and then (once a frame is fine), after elements moved or were removed
QuadtreeRetainedCleanup :: proc(tree: ^QuadtreeRetained($E, $N, $L)) {
    retainedNodeCleanup(tree, 0)
}

// Walk the nodes, branches before their children. For drawing the tree or counting
QuadtreeRetainedVisit :: proc(tree: ^QuadtreeRetained($E, $N, $L), user: rawptr, visit: QuadtreeNodeProc) {
    retainedNodeVisit(tree, 0, retainedRootArea(tree), 0, user, visit)
}

// ------------------------------------------------------------------------------------------------------------------------

@(private)
RetainedQuery :: struct {
    probe: Probe,
    out: []Handle,
    omit: Handle,
    session: ^QuerySession,
    count: int,
}

@(private)
RetainedFirst :: struct {
    omit: Handle,
    handle: Handle,
    t: f32,
}

@(private)
retainedTreeQuery :: proc(tree: ^QuadtreeRetained($E, $N, $L), probe: Probe, out: []Handle, omit: Handle, session: ^QuerySession) -> int {
    query: RetainedQuery = {probe = probe, out = out, omit = omit, session = session}
    switch probe.kind {
    case .RECT, .POINT: retainedNodeQuery(tree, 0, retainedRootArea(tree), EXTENT_LOW, EXTENT_HIGH, &query)
    case .CIRCLE, .SEGMENT:
        if session != nil { sessionBegin(session, int(E)) } else { retainedStampNext(tree) }
        retainedNodeQueryShape(tree, 0, retainedRootArea(tree), EXTENT_LOW, EXTENT_HIGH, &query)
    }
    return query.count
}

@(private)
retainedRootArea :: proc(tree: ^QuadtreeRetained($E, $N, $L)) -> Area {
    half_x: f32 = tree.bounds.w * 0.5
    half_y: f32 = tree.bounds.h * 0.5
    return {tree.bounds.x + half_x, tree.bounds.y + half_y, half_x, half_y}
}

@(private)
retainedLinkTake :: proc(tree: ^QuadtreeRetained($E, $N, $L)) -> i32 {
    link: i32 = -1
    if tree.link_free != -1 {
        link = tree.link_free
        tree.link_free = tree.links[link].next
    } else if tree.link_used < i32(L) {
        link = tree.link_used
        tree.link_used += 1
    } else {
        return -1
    }
    tree.links_in_use += 1
    return link
}

@(private)
retainedLinkGive :: proc(tree: ^QuadtreeRetained($E, $N, $L), link: i32) {
    tree.links[link].next = tree.link_free
    tree.link_free = link
    tree.links_in_use -= 1
}

@(private)
retainedGroupTake :: proc(tree: ^QuadtreeRetained($E, $N, $L)) -> i32 {
    group: i32 = -1
    if tree.group_free != -1 {
        group = tree.group_free
        tree.group_free = tree.nodes[group].first
    } else if tree.node_used + 4 <= i32(N) {
        group = tree.node_used
        tree.node_used += 4
    } else {
        return -1
    }
    for i: i32 = 0; i < 4; i += 1 { tree.nodes[group + i] = {first = -1, count = 0} }
    return group
}

// Put the element into every leaf its rectangle overlaps. A leaf that gets too full splits, only from the outermost call: the elements of a split are put into the new children without splitting those again
@(private)
retainedNodeAdd :: proc(tree: ^QuadtreeRetained($E, $N, $L), node: i32, area: Area, depth: i32, handle: Handle, rect: Rect, may_split: bool) -> bool {
    node: i32 = node
    area: Area = area
    depth: i32 = depth
    // most rectangles fit one quadrant at most levels: follow that path in a loop and recurse only where the rectangle is in several
    for tree.nodes[node].count < 0 {
        first: i32 = tree.nodes[node].first
        left: bool = rect.x <= area.cx
        right: bool = rect.x + rect.w > area.cx
        top: bool = rect.y <= area.cy
        bottom: bool = rect.y + rect.h > area.cy
        if left != right && top != bottom {
            quadrant: int = (1 if right else 0) + (2 if bottom else 0)
            node = first + i32(quadrant)
            area = areaChild(area, quadrant)
            depth += 1
            continue
        }
        hit: [4]bool = {left && top, right && top, left && bottom, right && bottom}
        for quadrant in 0 ..< 4 {
            if !hit[quadrant] { continue }
            if !retainedNodeAdd(tree, first + i32(quadrant), areaChild(area, quadrant), depth + 1, handle, rect, may_split) { return false }
        }
        return true
    }
    link: i32 = retainedLinkTake(tree)
    if link < 0 { return false }
    tree.links[link] = {next = tree.nodes[node].first, element = handle, rect = rect}
    tree.nodes[node].first = link
    tree.nodes[node].count += 1
    if may_split && tree.nodes[node].count > tree.max_elements && depth < tree.max_depth {
        retainedLeafSplit(tree, node, area, depth)
    }
    return true
}

// Turn a leaf into a branch. Only when it cannot fail half way: the group of four nodes is there, and so are the links for the worst case (every element in all four children, minus the links this frees)
@(private)
retainedLeafSplit :: proc(tree: ^QuadtreeRetained($E, $N, $L), node: i32, area: Area, depth: i32) {
    count: i32 = tree.nodes[node].count
    if i32(L) - tree.links_in_use < 3 * count { return }
    group: i32 = retainedGroupTake(tree)
    if group < 0 { return }
    link: i32 = tree.nodes[node].first
    tree.nodes[node] = {first = group, count = -1}
    for link != -1 {
        next: i32 = tree.links[link].next
        handle: Handle = tree.links[link].element
        retainedLinkGive(tree, link)
        element: ^RetainedElement = hm.get(&tree.elements, handle) or_else nil
        if element != nil { retainedNodeAdd(tree, node, area, depth, handle, element.rect, false) }
        link = next
    }
}

// Take the element out of the leaves its rectangle overlaps. Leaves that do not hold it (a failed add) are skipped
// Give the links of the element their new rectangle when the new rectangle reaches exactly the leaves the old one did. False as soon as the leaves differ: some links may already have the new rectangle then,
// which does no harm, the fallback in QuadtreeRetainedMove unlinks the element by its handle and links it again (or restores the old rectangle)
@(private)
retainedNodeResize :: proc(tree: ^QuadtreeRetained($E, $N, $L), node: i32, area: Area, handle: Handle, old: Rect, rect: Rect) -> bool {
    if tree.nodes[node].count < 0 {
        first: i32 = tree.nodes[node].first
        was: [4]bool = quadrants(area, old)
        now: [4]bool = quadrants(area, rect)
        if was != now { return false }
        for quadrant in 0 ..< 4 {
            if !now[quadrant] { continue }
            if !retainedNodeResize(tree, first + i32(quadrant), areaChild(area, quadrant), handle, old, rect) { return false }
        }
        return true
    }
    for link := tree.nodes[node].first; link != -1; link = tree.links[link].next {
        if tree.links[link].element == handle {
            tree.links[link].rect = rect
            return true
        }
    }
    return false
}

@(private)
retainedNodeRemove :: proc(tree: ^QuadtreeRetained($E, $N, $L), node: i32, area: Area, handle: Handle, rect: Rect) {
    if tree.nodes[node].count < 0 {
        first: i32 = tree.nodes[node].first
        hit: [4]bool = quadrants(area, rect)
        for quadrant in 0 ..< 4 {
            if hit[quadrant] { retainedNodeRemove(tree, first + i32(quadrant), areaChild(area, quadrant), handle, rect) }
        }
        return
    }
    previous: i32 = -1
    for link := tree.nodes[node].first; link != -1; link = tree.links[link].next {
        if tree.links[link].element == handle {
            if previous == -1 { tree.nodes[node].first = tree.links[link].next } else { tree.links[previous].next = tree.links[link].next }
            retainedLinkGive(tree, link)
            tree.nodes[node].count -= 1
            return
        }
        previous = link
    }
}

@(private)
retainedStampNext :: proc(tree: ^QuadtreeRetained($E, $N, $L)) {
    tree.stamp += 1
    if tree.stamp != 0 { return }
    // wrapped around: forget every old mark, or an element could look reported already
    it := hm.iterator_make(&tree.elements)
    for element, _ in hm.iterate(&it) { element.stamp = 0 }
    tree.stamp = 1
}

@(private)
retainedNodeQuery :: proc(tree: ^QuadtreeRetained($E, $N, $L), node: i32, area: Area, low: Vec2, high: Vec2, query: ^RetainedQuery) {
    node: i32 = node
    area: Area = area
    low: Vec2 = low
    high: Vec2 = high
    rect: Rect = query.probe.rect
    for tree.nodes[node].count < 0 {
        first: i32 = tree.nodes[node].first
        left: bool = rect.x <= area.cx
        right: bool = rect.x + rect.w > area.cx
        top: bool = rect.y <= area.cy
        bottom: bool = rect.y + rect.h > area.cy
        if left != right && top != bottom {
            quadrant: int = (1 if right else 0) + (2 if bottom else 0)
            low, high = extentChild(low, high, area, quadrant)
            node = first + i32(quadrant)
            area = areaChild(area, quadrant)
            continue
        }
        hit: [4]bool = {left && top, right && top, left && bottom, right && bottom}
        for quadrant in 0 ..< 4 {
            if !hit[quadrant] { continue }
            child_low, child_high := extentChild(low, high, area, quadrant)
            retainedNodeQuery(tree, first + i32(quadrant), areaChild(area, quadrant), child_low, child_high, query)
        }
        return
    }
    retainedLeafQueryOwned(tree, node, low, high, query)
}

// Rectangles and points without marks, like leafQueryOwned in quadtree.odin: the one leaf that holds the top left corner of the overlap reports the element
@(private)
retainedLeafQueryOwned :: proc(tree: ^QuadtreeRetained($E, $N, $L), node: i32, low: Vec2, high: Vec2, query: ^RetainedQuery) {
    rect: Rect = query.probe.rect
    point: bool = query.probe.kind == .POINT
    for link := tree.nodes[node].first; link != -1; link = tree.links[link].next {
        other: Rect = tree.links[link].rect
        if point {
            if !RectContainsPoint(other, {rect.x, rect.y}) { continue }
        } else {
            if !RectOverlaps(other, rect) { continue }
            corner_x: f32 = max(other.x, rect.x)
            corner_y: f32 = max(other.y, rect.y)
            if corner_x <= low.x || corner_x > high.x || corner_y <= low.y || corner_y > high.y { continue }
        }
        handle: Handle = tree.links[link].element
        if handle == query.omit { continue }
        if query.count < len(query.out) {
            query.out[query.count] = handle
            query.count += 1
        }
    }
}

// Circles and segments: the nodes are picked by their box (which reaches outward at the border of the tree)
@(private)
retainedNodeQueryShape :: proc(tree: ^QuadtreeRetained($E, $N, $L), node: i32, area: Area, low: Vec2, high: Vec2, query: ^RetainedQuery) {
    if tree.nodes[node].count < 0 {
        first: i32 = tree.nodes[node].first
        for quadrant in 0 ..< 4 {
            child_low, child_high := extentChild(low, high, area, quadrant)
            if probeHitsExtent(&query.probe, child_low, child_high) {
                retainedNodeQueryShape(tree, first + i32(quadrant), areaChild(area, quadrant), child_low, child_high, query)
            }
        }
        return
    }
    retainedLeafQuery(tree, node, query)
}

@(private)
retainedLeafQuery :: proc(tree: ^QuadtreeRetained($E, $N, $L), node: i32, query: ^RetainedQuery) {
    for link := tree.nodes[node].first; link != -1; link = tree.links[link].next {
        handle: Handle = tree.links[link].element
        element: ^RetainedElement = hm.get(&tree.elements, handle) or_continue
        if handle == query.omit { continue }
        if query.session != nil {
            if sessionSeen(query.session, int(handle.idx)) { continue }
        } else {
            if element.stamp == tree.stamp { continue }
            element.stamp = tree.stamp
        }
        if probeHitsRect(&query.probe, element.rect) && query.count < len(query.out) {
            query.out[query.count] = handle
            query.count += 1
        }
    }
}

// The nearest hit along a segment. An element in several leaves is looked at several times: harmless for a minimum
@(private)
retainedNodeFirst :: proc(tree: ^QuadtreeRetained($E, $N, $L), node: i32, area: Area, low: Vec2, high: Vec2, probe: ^Probe, first: ^RetainedFirst) {
    if tree.nodes[node].count < 0 {
        children: i32 = tree.nodes[node].first
        for quadrant in 0 ..< 4 {
            child_low, child_high := extentChild(low, high, area, quadrant)
            enter, _, hit := segmentBox(probe.a, probe.d, child_low, child_high)
            if hit && enter <= first.t { retainedNodeFirst(tree, children + i32(quadrant), areaChild(area, quadrant), child_low, child_high, probe, first) }
        }
        return
    }
    for link := tree.nodes[node].first; link != -1; link = tree.links[link].next {
        handle: Handle = tree.links[link].element
        element: ^RetainedElement = hm.get(&tree.elements, handle) or_continue
        if handle == first.omit { continue }
        enter, _, hit := segmentBox(probe.a, probe.d, {element.rect.x, element.rect.y}, {element.rect.x + element.rect.w, element.rect.y + element.rect.h})
        if hit && enter < first.t {
            first.t = enter
            first.handle = handle
        }
    }
}

// Merge a branch whose four children are empty leaves into an empty leaf. Returns true when the node is an empty leaf afterwards
@(private)
retainedNodeCleanup :: proc(tree: ^QuadtreeRetained($E, $N, $L), node: i32) -> bool {
    if tree.nodes[node].count >= 0 { return tree.nodes[node].count == 0 }
    first: i32 = tree.nodes[node].first
    empty: int
    for quadrant: i32 = 0; quadrant < 4; quadrant += 1 {
        if retainedNodeCleanup(tree, first + quadrant) { empty += 1 }
    }
    if empty < 4 { return false }
    tree.nodes[first].first = tree.group_free
    tree.group_free = first
    tree.nodes[node] = {first = -1, count = 0}
    return true
}

@(private)
retainedNodeVisit :: proc(tree: ^QuadtreeRetained($E, $N, $L), node: i32, area: Area, depth: int, user: rawptr, visit: QuadtreeNodeProc) {
    rect: Rect = {area.cx - area.hx, area.cy - area.hy, area.hx * 2, area.hy * 2}
    if tree.nodes[node].count < 0 {
        visit(user, rect, depth, false, 0)
        first: i32 = tree.nodes[node].first
        for quadrant in 0 ..< 4 { retainedNodeVisit(tree, first + i32(quadrant), areaChild(area, quadrant), depth + 1, user, visit) }
        return
    }
    visit(user, rect, depth, true, int(tree.nodes[node].count))
}

@(private)
retainedNodeNearest :: proc(tree: ^QuadtreeRetained($E, $N, $L), node: i32, area: Area, low: Vec2, high: Vec2, point: Vec2, nearest: ^Nearest(Handle)) {
    if tree.nodes[node].count < 0 {
        first: i32 = tree.nodes[node].first
        lows, highs, distances, order := nearestChildren(area, low, high, point)
        for quadrant in order {
            if nearestWants(nearest, distances[quadrant]) {
                retainedNodeNearest(tree, first + i32(quadrant), areaChild(area, quadrant), lows[quadrant], highs[quadrant], point, nearest)
            }
        }
        return
    }
    for link := tree.nodes[node].first; link != -1; link = tree.links[link].next {
        handle: Handle = tree.links[link].element
        element: ^RetainedElement = hm.get(&tree.elements, handle) or_continue
        rect: Rect = element.rect
        squared: f32 = distanceSquaredToBox(point, {rect.x, rect.y}, {rect.x + rect.w, rect.y + rect.h})
        if nearestWants(nearest, squared) && handle != nearest.omit { nearestAdd(nearest, handle, squared) }
    }
}

@(private)
retainedCompactNode :: proc(tree: ^QuadtreeRetained($E, $N, $L), node: i32, scratch: []RetainedLink, used: ^i32) {
    if tree.nodes[node].count < 0 {
        first: i32 = tree.nodes[node].first
        for quadrant in 0 ..< 4 { retainedCompactNode(tree, first + i32(quadrant), scratch, used) }
        return
    }
    start: i32 = used^
    for link := tree.nodes[node].first; link != -1; link = tree.links[link].next {
        scratch[used^] = tree.links[link]
        scratch[used^].next = used^ + 1
        used^ += 1
    }
    if used^ > start {
        scratch[used^ - 1].next = -1
        tree.nodes[node].first = start
    }
}
