package quadtree

/*
Use bit behaviour to index quadtree nodes.
Node indexes are sorted by depth, top-left, top-right, bottom-left, bottom-right
0,
  1,
    5,6,7,8,
  2,
    9,10,11,12,
  3,
    13,14,15,16,
  4,
    17,18,9,20,
*/

// x, y, halfWidth, halfHeight
AABB :: struct{
    x:i32,
    y:i32,
    w:i32,
    h:i32,
}

AABBIntersect :: proc(a,b: AABB)->bool {
    return abs(a.x - b.x) <= (a.w + b.w) && abs(a.y - b.y) <= (a.h + b.h)
}

QTNode :: struct {
    depth: u32,
    morton: u32, // quadrant path to that node
}

qt_node_index :: proc(node: QTNode)->u32 {
    return qt_depth_index(node.depth) + node.morton
}

qt_depth_index :: proc(depth:u32)->u32 {
    return ((1 << (depth * 2)) - 1) / 3
}

qt_child :: proc(node_idx:u32, child:u32)->u32 {
    return node_idx * 4 + 1 + child
}

qt_parent :: proc(node_idx:u32)->u32 {
    return (node_idx - 1) >> 2
}

qt_first_child :: proc(node_idx:u32)->u32 {
    return node_idx * 4 + 1
}

qt_child_at :: proc(node_idx:u32, depth:u32)->u32 {
    return (node_idx >> (depth * 2)) & 3
}

qt_traverse :: proc(from:u32, limit:u32) {
    node_idx:u32 = from
    for node_idx < limit {
        base:u32 = node_idx * 4 + 1
        for c:u32 = 0; c < 4; c += 1 {
            child:u32 = base + c
            child = child // TODO: process child
        }
        node_idx = base // descent example
    }
}

highest_bit :: proc(val:u32)->u32 {
    // alternative to __builtin_clz
    v:= val
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8
    v |= v >> 16

    debrujin_table:[32]u32 = {
        0, 9, 1,10,13,21, 2,29,
        11,14,16,18,22,25, 3,30,
        8,12,20,28,15,17,24, 7,
        19,27,23, 6,26, 5, 4,31,
    }
    return debrujin_table[(v * 0x07C4ACDD) >> 27]
}

part1by1 :: proc(val:u32)->u32 {
    // Morton encode cell coordinates
    // Interleave the bits of cx and cy
    // Fast bit-spread implementation
    x:= val
    x &= 0x0000ffff
    x = (x | (x << 8)) & 0x00FF00FF
    x = (x | (x << 4)) & 0x0F0F0F0F
    x = (x | (x << 2)) & 0x33333333
    x = (x | (x << 2)) & 0x55555555
    return x
}

// root_exp is the maximum quadtree depth exponent (2^root_exp)
// This lets you map world coordinates into quadtree grid cells using bit shifts
// root_exp = 10 -> 2^10 = 1024
// Meaning the world is divided into a 1024×1024 grid at the finest level.
qt_locate_parent :: proc(obj: AABB, root_exp:u32)-> QTNode {
    left:i32 = obj.x - obj.w
    right:i32 = obj.x + obj.w
    top:i32 = obj.y - obj.h     // Negative is up
    bottom:i32 = obj.y + obj.h  // Positive is down

    dx:u32 = cast(u32)(left ~ right) // bitwise xor
    dy:u32 = cast(u32)(top ~ bottom) // bitwise xor

    d:u32 = dx > dy ? dx : dy
    depth:u32
    if (d == 0){
        depth = root_exp
    } else {
        depth = root_exp - (highest_bit(d) + 1)
    }

    cell_shift:u32 = root_exp - depth

    cx:u32 = cast(u32)obj.x >> cell_shift
    cy:u32 = cast(u32)obj.y >> cell_shift

    morton:u32 = part1by1(cx) | (part1by1(cy) << 1)

    result:QTNode = {depth, morton}
    return result
}

qt_subtree_range :: proc(node: QTNode, max_depth:u32) -> (u32, u32) {
    bits_left := (max_depth - node.depth) * 2

    start := node.morton << bits_left
    end   := ((node.morton + 1) << bits_left) - 1

    return start, end
}

qt_traverse_leaves :: proc(node: QTNode, max_depth:u32) {
    start, end := qt_subtree_range(node, max_depth)

    leaf_base := qt_depth_index(max_depth)

    for m := start; m <= end; m += 1 {
        idx := leaf_base + m
        idx = idx // TODO: process leaf
    }
}

// TODO: root_exp is not used
qt_world_to_grid :: proc(x:i32, y:i32, root_exp:u32, origin_x:i32, origin_y:i32) -> (u32, u32) {
    gx := cast(u32)(x - origin_x)
    gy := cast(u32)(y - origin_y)

    return gx, gy
}