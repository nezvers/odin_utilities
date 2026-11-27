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

// Items of the elements whose rectangle overlaps `rect` (each once, `omit` left out). Returns how many were written: results are limited by the size of `out`
QuadtreeQuery :: proc(tree: ^Quadtree($E, $N, $L), rect: Rect, out: []Item, omit: Item = ITEM_NONE) -> int {
    query: Query = {rect = rect, out = out, omit = omit}
    tree.stamp += 1
    nodeQuery(tree, 0, rootArea(tree), &query)
    return query.count
}

// Items of the elements whose rectangle contains the point
QuadtreeQueryPoint :: proc(tree: ^Quadtree($E, $N, $L), point: Vec2, out: []Item) -> int {
    query: Query = {rect = {point.x, point.y, 0, 0}, out = out, omit = ITEM_NONE, point = true}
    tree.stamp += 1
    nodeQuery(tree, 0, rootArea(tree), &query)
    return query.count
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
    rect: Rect,
    out: []Item,
    omit: Item,
    point: bool,
    count: int,
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
    if tree.nodes[node].count < 0 {
        first: i32 = tree.nodes[node].first
        hit: [4]bool = quadrants(area, rect)
        for quadrant in 0 ..< 4 {
            if !hit[quadrant] { continue }
            if !nodeAdd(tree, first + i32(quadrant), areaChild(area, quadrant), depth + 1, element, rect, may_split) { return false }
        }
        return true
    }
    link: i32 = linkTake(tree)
    if link < 0 { return false }
    tree.links[link] = {next = tree.nodes[node].first, element = element}
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

@(private)
nodeQuery :: proc(tree: ^Quadtree($E, $N, $L), node: i32, area: Area, query: ^Query) {
    if tree.nodes[node].count < 0 {
        first: i32 = tree.nodes[node].first
        hit: [4]bool = quadrants(area, query.rect)
        for quadrant in 0 ..< 4 {
            if hit[quadrant] { nodeQuery(tree, first + i32(quadrant), areaChild(area, quadrant), query) }
        }
        return
    }
    for link := tree.nodes[node].first; link != -1; link = tree.links[link].next {
        element: ^Element = &tree.elements[tree.links[link].element]
        if element.stamp == tree.stamp || element.item == query.omit { continue }
        element.stamp = tree.stamp
        hit: bool = RectContainsPoint(element.rect, {query.rect.x, query.rect.y}) if query.point else RectOverlaps(element.rect, query.rect)
        if hit && query.count < len(query.out) {
            query.out[query.count] = element.item
            query.count += 1
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
