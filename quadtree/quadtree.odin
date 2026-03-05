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

qt_child :: proc(node:u32, child:u32)->u32 {
    return node * 4 + 1 + child
}

qt_parent :: proc(node:u32)->u32 {
    return (node - 1) >> 2
}

qt_first_child :: proc(node:u32)->u32 {
    return node * 4 + 1
}

qt_child_at :: proc(node:u32, depth:u32)->u32 {
    return (node >> (depth * 2)) & 3
}

qt_traverse :: proc( from:u32, limit:u32) {
    node:u32 = from
    for node < limit {
        base:u32 = node * 4 + 1
        for c:u32 = 0; c < 4; c += 1 {
            child:u32 = base + c
            child = child // TODO:
            // process child
        }
        node = base // descent example
    }
}

highest_bit :: proc(val:u32)->u32 {
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