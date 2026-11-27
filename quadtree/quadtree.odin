// Immediate mode quadtree broad phase for 2D rectangles, without allocations. The tree is rebuilt every frame: QuadtreeClear, QuadtreeInsert everything that moves or exists, then query.
// Nothing is stored between frames, so there is no remove, no move and no handle to keep valid: the caller owns the objects and the tree only holds a rectangle and the caller's `Item` (usually the index in
// the caller's own array). All memory is fixed arrays (elements, nodes in groups of four, links), everything fails instead of growing.
// The algorithm follows the quadtree of "dragon-energy" (Stack Overflow, see README): an element is stored in every leaf its rectangle overlaps, a leaf splits when it holds more than `max_elements`
// (unless it is at `max_depth`).
package quadtree

Vec2 :: [2]f32

// What the caller gets back from a query: any number that names the object, mostly an index into the caller's array
Item :: int
ITEM_NONE :: Item(-1)

// x, y = top left corner
Rect :: struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
}

QUADTREE_MAX_DEPTH :: 16

@(private)
Element :: struct {
    rect: Rect,
    item: Item,
    stamp: u32,         // the query that already reported this element (an element sits in several leaves)
}

// Leaf: `count` >= 0 elements, `first` is the first link (-1 for none). Branch: `count` = -1, `first` is the first of its four children (top left, top right, bottom left, bottom right).
@(private)
Node :: struct {
    first: i32,
    count: i32,
}

@(private)
Link :: struct {
    next: i32,
    element: i32,
    rect: Rect,         // a copy of the rectangle of the element: a leaf is tested without touching the (scattered) elements
}

// E = elements, N = nodes (the root and groups of four), L = links (an element takes one for every leaf it overlaps). Size them with QuadtreeUsage.
// Put it in a global or in your own struct: it holds all of its memory.
Quadtree :: struct($E: uint, $N: uint, $L: uint) {
    bounds: Rect,               // Where the tree divides space. Rectangles outside still work: they sit in the border leaves
    max_elements: i32,          // A leaf with more elements splits
    max_depth: i32,
    elements: [E]Element,
    element_count: i32,
    nodes: [N]Node,
    node_used: i32,             // Nodes handed out: the root, then four at a time
    links: [L]Link,
    link_used: i32,             // Links handed out from the array so far
    link_free: i32,             // First of the links given back by a failed insert (linked through `next`), -1 for none
    links_in_use: i32,
    stamp: u32,
}

// Centre and half size of a node
@(private)
Area :: struct {
    cx: f32,
    cy: f32,
    hx: f32,
    hy: f32,
}

// Set the area and empty the tree. `max_elements` is how many a leaf takes before it splits, `max_depth` how often the space is divided at most
QuadtreeInit :: proc(tree: ^Quadtree($E, $N, $L), bounds: Rect, max_elements: int = 8, max_depth: int = 8) {
    assert(bounds.w > 0 && bounds.h > 0)
    assert(max_elements >= 1)
    assert(max_depth >= 0 && max_depth <= QUADTREE_MAX_DEPTH)
    assert(E >= 1 && N >= 1 && L >= 1)
    tree.bounds = bounds
    tree.max_elements = i32(max_elements)
    tree.max_depth = i32(max_depth)
    QuadtreeClear(tree)
}

// Empty the tree: the first call of every frame. Costs nothing but resetting counters
QuadtreeClear :: proc(tree: ^Quadtree($E, $N, $L)) {
    tree.element_count = 0
    tree.nodes[0] = {first = -1, count = 0}
    tree.node_used = 1
    tree.link_used = 0
    tree.link_free = -1
    tree.links_in_use = 0
    tree.stamp = 0
}

QuadtreeLen :: proc(tree: ^Quadtree($E, $N, $L)) -> int {
    return int(tree.element_count)
}

// Nodes and links in use, to size N and L
QuadtreeUsage :: proc(tree: ^Quadtree($E, $N, $L)) -> (nodes: int, links: int) {
    return int(tree.node_used), int(tree.links_in_use)
}

// Put a rectangle into the tree. Fails (nothing is changed) when the elements, the nodes or the links are full
QuadtreeInsert :: proc(tree: ^Quadtree($E, $N, $L), rect: Rect, item: Item) -> bool {
    if tree.element_count >= i32(E) { return false }
    index: i32 = tree.element_count
    tree.elements[index] = {rect = rect, item = item}
    tree.element_count += 1
    if nodeAdd(tree, 0, rootArea(tree), 0, index, rect, true) { return true }
    nodeRemove(tree, 0, rootArea(tree), index, rect)
    tree.element_count -= 1
    return false
}

// Items of the elements whose rectangle overlaps `rect` (each once, `omit` left out). Returns how many were written: results are limited by the size of `out`.
// Every query below takes an optional `session`: without it the elements are marked in the tree (one thread at a time), with it the tree is only read (see QuerySession).
QuadtreeQuery :: proc(tree: ^Quadtree($E, $N, $L), rect: Rect, out: []Item, omit: Item = ITEM_NONE, session: ^QuerySession = nil) -> int {
    return treeQuery(tree, probeRect(rect), out, omit, session)
}

// Items of the elements whose rectangle contains the point
QuadtreeQueryPoint :: proc(tree: ^Quadtree($E, $N, $L), point: Vec2, out: []Item, session: ^QuerySession = nil) -> int {
    return treeQuery(tree, probePoint(point), out, ITEM_NONE, session)
}

// Items of the elements whose rectangle overlaps the circle (a rectangle that only touches it does not count). Nodes that the circle cannot reach are not visited
QuadtreeQueryCircle :: proc(tree: ^Quadtree($E, $N, $L), center: Vec2, radius: f32, out: []Item, omit: Item = ITEM_NONE, session: ^QuerySession = nil) -> int {
    return treeQuery(tree, probeCircle(center, radius), out, omit, session)
}

// Items of the elements whose rectangle the segment from `a` to `b` crosses (touching an edge counts, a segment inside a rectangle too). Not in the order along the segment: see QuadtreeSegmentFirst
QuadtreeQuerySegment :: proc(tree: ^Quadtree($E, $N, $L), a: Vec2, b: Vec2, out: []Item, omit: Item = ITEM_NONE, session: ^QuerySession = nil) -> int {
    return treeQuery(tree, probeSegment(a, b), out, omit, session)
}

// The first element along the segment from `a` to `b`: its item and `t` in [0, 1] (the hit is at a + t * (b - a); 0 when `a` is inside the rectangle). Nodes behind a nearer hit are skipped.
// Reads the tree only (no marks are needed to find a minimum), so it is thread safe without a session.
QuadtreeSegmentFirst :: proc(tree: ^Quadtree($E, $N, $L), a: Vec2, b: Vec2, omit: Item = ITEM_NONE) -> (item: Item, t: f32, hit: bool) {
    probe: Probe = probeSegment(a, b)
    first: First = {omit = omit, t = 2, item = ITEM_NONE}
    nodeFirst(tree, 0, rootArea(tree), EXTENT_LOW, EXTENT_HIGH, &probe, &first)
    if first.item == ITEM_NONE { return ITEM_NONE, 0, false }
    return first.item, first.t, true
}

// The `out` / `distances` (as long as the shorter one, `k`) nearest elements to `point`, nearest first, with their distances (0 when the point is inside of a rectangle). `omit` is left out, elements
// farther than `max_distance` are not looked for. Returns how many were found. Reads the tree only, so it is thread safe without a session; one call with k = 1 finds the closest element.
QuadtreeNearest :: proc(tree: ^Quadtree($E, $N, $L), point: Vec2, out: []Item, distances: []f32, omit: Item = ITEM_NONE, max_distance: f32 = max(f32)) -> int {
    k: int = min(len(out), len(distances))
    if k == 0 { return 0 }
    nearest: Nearest(Item) = {items = out[:k], distances = distances[:k], limit = max_distance * max_distance, omit = omit}
    nodeNearest(tree, 0, rootArea(tree), EXTENT_LOW, EXTENT_HIGH, point, &nearest)
    return nearestFinish(nearest.distances, nearest.count)
}

// Called for every node by QuadtreeVisit. `count` is the number of elements of a leaf (0 for a branch)
QuadtreeNodeProc :: proc(user: rawptr, rect: Rect, depth: int, leaf: bool, count: int)

// Walk the nodes, branches before their children. For drawing the tree or counting
QuadtreeVisit :: proc(tree: ^Quadtree($E, $N, $L), user: rawptr, visit: QuadtreeNodeProc) {
    nodeVisit(tree, 0, rootArea(tree), 0, user, visit)
}

// Narrow phase. Touching edges are not overlapping
RectOverlaps :: proc(a: Rect, b: Rect) -> bool {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}

RectContainsPoint :: proc(rect: Rect, point: Vec2) -> bool {
    return point.x >= rect.x && point.x < rect.x + rect.w && point.y >= rect.y && point.y < rect.y + rect.h
}

// ------------------------------------------------------------------------------------------------------------------------

@(private)
Query :: struct {
    probe: Probe,
    out: []Item,
    omit: Item,
    session: ^QuerySession,
    stamp: u32,                 // the number of this query when the marks are in the tree
    count: int,
}

@(private)
First :: struct {
    omit: Item,
    item: Item,
    t: f32,
}

@(private)
treeQuery :: proc(tree: ^Quadtree($E, $N, $L), probe: Probe, out: []Item, omit: Item, session: ^QuerySession) -> int {
    query: Query = {probe = probe, out = out, omit = omit, session = session}
    switch probe.kind {
    case .RECT, .POINT:
        // no marks: see leafQuery
        nodeQuery(tree, 0, rootArea(tree), EXTENT_LOW, EXTENT_HIGH, &query)
    case .CIRCLE, .SEGMENT:
        if session != nil {
            sessionBegin(session, int(E))
        } else {
            tree.stamp += 1
            query.stamp = tree.stamp
        }
        nodeQueryShape(tree, 0, rootArea(tree), EXTENT_LOW, EXTENT_HIGH, &query)
    }
    return query.count
}

@(private)
rootArea :: proc(tree: ^Quadtree($E, $N, $L)) -> Area {
    half_x: f32 = tree.bounds.w * 0.5
    half_y: f32 = tree.bounds.h * 0.5
    return {tree.bounds.x + half_x, tree.bounds.y + half_y, half_x, half_y}
}

// Quadrant 0 top left, 1 top right, 2 bottom left, 3 bottom right
@(private)
areaChild :: proc(area: Area, quadrant: int) -> Area {
    half_x: f32 = area.hx * 0.5
    half_y: f32 = area.hy * 0.5
    return {
        area.cx + (half_x if quadrant & 1 != 0 else -half_x),
        area.cy + (half_y if quadrant & 2 != 0 else -half_y),
        half_x,
        half_y,
    }
}

// The quadrants a rectangle reaches. A rectangle that lies outside of the tree still reaches the border ones, so it is found there
@(private)
quadrants :: proc(area: Area, rect: Rect) -> (hit: [4]bool) {
    left: bool = rect.x <= area.cx
    right: bool = rect.x + rect.w > area.cx
    top: bool = rect.y <= area.cy
    bottom: bool = rect.y + rect.h > area.cy
    return {left && top, right && top, left && bottom, right && bottom}
}

@(private)
linkTake :: proc(tree: ^Quadtree($E, $N, $L)) -> i32 {
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
linkGive :: proc(tree: ^Quadtree($E, $N, $L), link: i32) {
    tree.links[link].next = tree.link_free
    tree.link_free = link
    tree.links_in_use -= 1
}

// A group of four empty leaves, -1 when the nodes are used up
@(private)
groupTake :: proc(tree: ^Quadtree($E, $N, $L)) -> i32 {
    if tree.node_used + 4 > i32(N) { return -1 }
    group: i32 = tree.node_used
    tree.node_used += 4
    for i: i32 = 0; i < 4; i += 1 { tree.nodes[group + i] = {first = -1, count = 0} }
    return group
}

// Put the element into every leaf its rectangle overlaps. A leaf that gets too full splits, only from the outermost call: the elements of a split are put into the new children without splitting those again
@(private)
nodeAdd :: proc(tree: ^Quadtree($E, $N, $L), node: i32, area: Area, depth: i32, element: i32, rect: Rect, may_split: bool) -> bool {
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
            if !nodeAdd(tree, first + i32(quadrant), areaChild(area, quadrant), depth + 1, element, rect, may_split) { return false }
        }
        return true
    }
    link: i32 = linkTake(tree)
    if link < 0 { return false }
    tree.links[link] = {next = tree.nodes[node].first, element = element, rect = rect}
    tree.nodes[node].first = link
    tree.nodes[node].count += 1
    if may_split && tree.nodes[node].count > tree.max_elements && depth < tree.max_depth {
        leafSplit(tree, node, area, depth)
    }
    return true
}

// Turn a leaf into a branch. Only when it cannot fail half way: the group of four nodes is there, and so are the links for the worst case (every element in all four children, minus the links this frees)
@(private)
leafSplit :: proc(tree: ^Quadtree($E, $N, $L), node: i32, area: Area, depth: i32) {
    count: i32 = tree.nodes[node].count
    if i32(L) - tree.links_in_use < 3 * count { return }
    group: i32 = groupTake(tree)
    if group < 0 { return }
    link: i32 = tree.nodes[node].first
    tree.nodes[node] = {first = group, count = -1}
    for link != -1 {
        next: i32 = tree.links[link].next
        element: i32 = tree.links[link].element
        linkGive(tree, link)
        nodeAdd(tree, node, area, depth, element, tree.elements[element].rect, false)
        link = next
    }
}

// Take the element out of the leaves its rectangle overlaps, only to undo a failed insert. Leaves that do not hold it are skipped
@(private)
nodeRemove :: proc(tree: ^Quadtree($E, $N, $L), node: i32, area: Area, element: i32, rect: Rect) {
    if tree.nodes[node].count < 0 {
        first: i32 = tree.nodes[node].first
        hit: [4]bool = quadrants(area, rect)
        for quadrant in 0 ..< 4 {
            if hit[quadrant] { nodeRemove(tree, first + i32(quadrant), areaChild(area, quadrant), element, rect) }
        }
        return
    }
    previous: i32 = -1
    for link := tree.nodes[node].first; link != -1; link = tree.links[link].next {
        if tree.links[link].element == element {
            if previous == -1 { tree.nodes[node].first = tree.links[link].next } else { tree.links[previous].next = tree.links[link].next }
            linkGive(tree, link)
            tree.nodes[node].count -= 1
            return
        }
        previous = link
    }
}

// Rectangles and points: the nodes are picked by the bounding rectangle
@(private)
nodeQuery :: proc(tree: ^Quadtree($E, $N, $L), node: i32, area: Area, low: Vec2, high: Vec2, query: ^Query) {
    node: i32 = node
    area: Area = area
    low: Vec2 = low
    high: Vec2 = high
    rect: Rect = query.probe.rect
    // a query inside one quadrant follows its path in a loop, the recursion is only for the nodes where it reaches several
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
            nodeQuery(tree, first + i32(quadrant), areaChild(area, quadrant), child_low, child_high, query)
        }
        return
    }
    leafQueryOwned(tree, node, low, high, query)
}

// Rectangles and points without marks, so no write to the tree and no session. An element sits in every leaf it overlaps, so it is reported only by the leaf that holds the top left corner of the
// overlap with the query: that corner lies in exactly one leaf (the same centre compare as the descent: left and top when <=), and this leaf holds the element (it overlaps the element) and is visited
// (it overlaps the query). A point is in one leaf only, so it needs nothing.
@(private)
leafQueryOwned :: proc(tree: ^Quadtree($E, $N, $L), node: i32, low: Vec2, high: Vec2, query: ^Query) {
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
        element: ^Element = &tree.elements[tree.links[link].element]
        if element.item == query.omit { continue }
        if query.count < len(query.out) {
            query.out[query.count] = element.item
            query.count += 1
        }
    }
}

// Circles and segments: the nodes are picked by their box (which reaches outward at the border of the tree)
@(private)
nodeQueryShape :: proc(tree: ^Quadtree($E, $N, $L), node: i32, area: Area, low: Vec2, high: Vec2, query: ^Query) {
    if tree.nodes[node].count < 0 {
        first: i32 = tree.nodes[node].first
        for quadrant in 0 ..< 4 {
            child_low, child_high := extentChild(low, high, area, quadrant)
            if probeHitsExtent(&query.probe, child_low, child_high) {
                nodeQueryShape(tree, first + i32(quadrant), areaChild(area, quadrant), child_low, child_high, query)
            }
        }
        return
    }
    leafQuery(tree, node, query)
}

@(private)
leafQuery :: proc(tree: ^Quadtree($E, $N, $L), node: i32, query: ^Query) {
    for link := tree.nodes[node].first; link != -1; link = tree.links[link].next {
        index: i32 = tree.links[link].element
        element: ^Element = &tree.elements[index]
        if element.item == query.omit { continue }
        if query.session != nil {
            if sessionSeen(query.session, int(index)) { continue }
        } else {
            if element.stamp == query.stamp { continue }
            element.stamp = query.stamp
        }
        if probeHitsRect(&query.probe, element.rect) && query.count < len(query.out) {
            query.out[query.count] = element.item
            query.count += 1
        }
    }
}

// The nearest hit along a segment. An element in several leaves is looked at several times: harmless for a minimum
@(private)
nodeFirst :: proc(tree: ^Quadtree($E, $N, $L), node: i32, area: Area, low: Vec2, high: Vec2, probe: ^Probe, first: ^First) {
    if tree.nodes[node].count < 0 {
        children: i32 = tree.nodes[node].first
        for quadrant in 0 ..< 4 {
            child_low, child_high := extentChild(low, high, area, quadrant)
            enter, _, hit := segmentBox(probe.a, probe.d, child_low, child_high)
            if hit && enter <= first.t { nodeFirst(tree, children + i32(quadrant), areaChild(area, quadrant), child_low, child_high, probe, first) }
        }
        return
    }
    for link := tree.nodes[node].first; link != -1; link = tree.links[link].next {
        element: ^Element = &tree.elements[tree.links[link].element]
        if element.item == first.omit { continue }
        enter, _, hit := segmentBox(probe.a, probe.d, {element.rect.x, element.rect.y}, {element.rect.x + element.rect.w, element.rect.y + element.rect.h})
        if hit && enter < first.t {
            first.t = enter
            first.item = element.item
        }
    }
}

@(private)
nodeVisit :: proc(tree: ^Quadtree($E, $N, $L), node: i32, area: Area, depth: int, user: rawptr, visit: QuadtreeNodeProc) {
    rect: Rect = {area.cx - area.hx, area.cy - area.hy, area.hx * 2, area.hy * 2}
    if tree.nodes[node].count < 0 {
        visit(user, rect, depth, false, 0)
        first: i32 = tree.nodes[node].first
        for quadrant in 0 ..< 4 { nodeVisit(tree, first + i32(quadrant), areaChild(area, quadrant), depth + 1, user, visit) }
        return
    }
    visit(user, rect, depth, true, int(tree.nodes[node].count))
}

@(private)
nodeNearest :: proc(tree: ^Quadtree($E, $N, $L), node: i32, area: Area, low: Vec2, high: Vec2, point: Vec2, nearest: ^Nearest(Item)) {
    if tree.nodes[node].count < 0 {
        first: i32 = tree.nodes[node].first
        lows, highs, distances, order := nearestChildren(area, low, high, point)
        for quadrant in order {
            if nearestWants(nearest, distances[quadrant]) {
                nodeNearest(tree, first + i32(quadrant), areaChild(area, quadrant), lows[quadrant], highs[quadrant], point, nearest)
            }
        }
        return
    }
    for link := tree.nodes[node].first; link != -1; link = tree.links[link].next {
        rect: Rect = tree.links[link].rect
        squared: f32 = distanceSquaredToBox(point, {rect.x, rect.y}, {rect.x + rect.w, rect.y + rect.h})
        if !nearestWants(nearest, squared) { continue }
        item: Item = tree.elements[tree.links[link].element].item
        if item != nearest.omit { nearestAdd(nearest, item, squared) }
    }
}
