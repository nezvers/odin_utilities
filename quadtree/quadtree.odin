package quadtree

/*
Linear Morton Quadtree

Nodes are implicitly stored by (depth, morton index).

Depth layout:

depth 0
0

depth 1
1 2 3 4

depth 2
5..20

index formula:
index = qt_depth_index(depth) + morton

Morton codes store quadrant traversal path:
00 = top-left
01 = top-right
10 = bottom-left
11 = bottom-right
*/

AABB :: struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
}

AABBIntersect :: proc(a, b: AABB) -> bool {
    return abs(a.x - b.x) <= (a.w + b.w) &&
           abs(a.y - b.y) <= (a.h + b.h)
}

QTNode :: struct {
    depth:  u32,
    morton: u32,
}

QTObject :: struct {
    bounds: AABB,
    id:     u32,
}

QTLeafRange :: struct {
    first_object: u32,
    count:        u32,
}

Quadtree :: struct {
    root_exponent: u32,
    max_depth:     u32,

    origin_x: i32,
    origin_y: i32,

    objects:     [dynamic]QTObject,
    leaf_ranges: []QTLeafRange,
}

qt_initialize :: proc(
    tree: ^Quadtree,
    root_exponent: u32,
    max_depth: u32,
    origin_x: i32,
    origin_y: i32
) {
    tree.root_exponent = root_exponent
    tree.max_depth     = max_depth
    tree.origin_x      = origin_x
    tree.origin_y      = origin_y

    leaf_count := qt_leaf_count(max_depth)
    tree.leaf_ranges = make([]QTLeafRange, leaf_count)
}

qt_clear :: proc(tree: ^Quadtree) {
    for i:int = 0; i < len(tree.leaf_ranges); i += 1 {
        tree.leaf_ranges[i].count = 0
        tree.leaf_ranges[i].first_object = 0
    }
    clear_dynamic_array(&tree.objects)
}

qt_leaf_count :: proc(depth: u32) -> u32 {
    return 1 << (depth * 2)
}

qt_insert :: proc( tree: ^Quadtree, object: QTObject) {
    node := qt_locate_parent(object.bounds, tree.root_exponent)
    start, _ := qt_subtree_range(node, tree.max_depth)
    leaf_index := start
    leaf := &tree.leaf_ranges[leaf_index]

    if leaf.count == 0 {
        leaf.first_object = cast(u32)len(tree.objects)
    }

    append(&tree.objects, object)
    leaf.count += 1
}

qt_traverse_leaves :: proc(
    tree: ^Quadtree,
    node: QTNode,
    callback: proc(object: QTObject)
) {
    start, end := qt_subtree_range(node, tree.max_depth)
    for morton := start; morton <= end; morton += 1 {
        leaf := tree.leaf_ranges[morton]
        for i: u32 = 0; i < leaf.count; i += 1 {
            object := tree.objects[leaf.first_object + i]
            callback(object)
        }
    }
}

qt_subtree_range :: proc(
    node: QTNode,
    max_depth: u32
) -> (u32, u32) {
    bits_left := (max_depth - node.depth) * 2
    start := node.morton << bits_left
    end   := ((node.morton + 1) << bits_left) - 1
    return start, end
}

qt_locate_parent :: proc(
    object: AABB,
    root_exponent: u32
)->QTNode {
    left   := object.x - object.w
    right  := object.x + object.w
    top    := object.y - object.h
    bottom := object.y + object.h

    dx := cast(u32)(left ~ right)
    dy := cast(u32)(top  ~ bottom)

    difference := dx > dy ? dx : dy

    depth: u32
    if difference == 0 {
        depth = root_exponent
    } else {
        // highest differing bit determines smallest power-of-two cell
        depth = root_exponent - (highest_bit(difference) + 1)
    }

    cell_shift := root_exponent - depth

    cx := cast(u32)object.x >> cell_shift
    cy := cast(u32)object.y >> cell_shift

    morton := part1by1(cx) | (part1by1(cy) << 1)

    return QTNode{depth, morton}
}

highest_bit :: proc(value: u32) -> u32 {
    v := value
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8
    v |= v >> 16

    debrujin_table: [32]u32 = {
        0,9,1,10,13,21,2,29,
        11,14,16,18,22,25,3,30,
        8,12,20,28,15,17,24,7,
        19,27,23,6,26,5,4,31,
    }

    return debrujin_table[(v * 0x07C4ACDD) >> 27]
}

part1by1 :: proc(value: u32) -> u32 {
    // spreads bits apart so they can interleave
    x := value
    x &= 0x0000ffff
    x = (x | (x << 8)) & 0x00FF00FF
    x = (x | (x << 4)) & 0x0F0F0F0F
    x = (x | (x << 2)) & 0x33333333
    x = (x | (x << 1)) & 0x55555555
    return x
}

qt_world_to_grid :: proc(
    x: i32,
    y: i32,
    origin_x: i32,
    origin_y: i32
) -> (u32, u32) {

    gx := cast(u32)(x - origin_x)
    gy := cast(u32)(y - origin_y)

    return gx, gy
}

CollisionPair :: struct {
    a: u32,
    b: u32,
}

qt_find_collision_pairs :: proc(
    tree: ^Quadtree,
    pairs: ^[dynamic]CollisionPair
) {
    for leaf_index: u32 = 0;
        leaf_index < cast(u32)len(tree.leaf_ranges);
        leaf_index += 1
    {
        leaf := tree.leaf_ranges[leaf_index]
        if leaf.count < 2 {
            continue
        }
        start := leaf.first_object
        end   := start + leaf.count

        for i := start; i < end; i += 1 {
            for j := i + 1; j < end; j += 1 {
                object_a := tree.objects[i]
                object_b := tree.objects[j]

                if AABBIntersect(object_a.bounds, object_b.bounds) {
                    append(
                        pairs,
                        CollisionPair{object_a.id, object_b.id}
                    )
                }
            }
        }
    }
}

/*  */
qt_depth_index :: proc(depth: u32) -> u32 {
    // total nodes before this depth
    return ((1 << (depth * 2)) - 1) / 3
}

qt_node_index :: proc(node: QTNode) -> u32 {
    return qt_depth_index(node.depth) + node.morton
}

qt_child :: proc(node_index: u32, child: u32) -> u32 {
    return node_index * 4 + 1 + child
}

qt_parent :: proc(node_index: u32) -> u32 {
    return (node_index - 1) >> 2
}

qt_first_child :: proc(node_index: u32) -> u32 {
    return node_index * 4 + 1
}

qt_child_at :: proc(node_index: u32, depth: u32) -> u32 {
    return (node_index >> (depth * 2)) & 3
}