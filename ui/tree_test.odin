#+build !js
package ui

import "core:testing"

@(private = "file")
newTree :: proc() -> ^Tree {
    tree: ^Tree = new(Tree)
    TreeInit(tree)
    return tree
}

@(private = "file")
names :: proc(tree: ^Tree, rows: []TreeRow) -> [16]string {
    result: [16]string
    for row, i in rows { result[i] = TreeName(TreeGet(tree, row.node)) }
    return result
}

@(test)
test_a_tree_shows_the_children_of_open_nodes_in_order_with_their_depth :: proc(t: ^testing.T) {
    tree: ^Tree = newTree()
    defer free(tree)
    src, _ := TreeAdd(tree, {}, "src", branch = true)
    main, _ := TreeAdd(tree, src, "main.odin")
    util, _ := TreeAdd(tree, src, "util", branch = true)
    deep, _ := TreeAdd(tree, util, "deep.odin")
    TreeAdd(tree, {}, "README")
    TreeAdd(tree, src, "last.odin")
    rows: [16]TreeRow
    count: int = TreeVisible(tree, rows[:])
    testing.expect_value(t, count, 2)                                  // everything is closed: "src" and "README"
    testing.expect(t, rows[0].expandable && !rows[0].expanded && !rows[1].expandable)
    TreeExpand(tree, src)
    count = TreeVisible(tree, rows[:])
    shown: [16]string = names(tree, rows[:count])
    testing.expect_value(t, count, 5)
    testing.expect(t, shown[0] == "src" && shown[1] == "main.odin" && shown[2] == "util" && shown[3] == "last.odin" && shown[4] == "README", "a closed child hides its children")
    testing.expect(t, rows[0].depth == 0 && rows[1].depth == 1 && rows[3].depth == 1 && rows[4].depth == 0)
    TreeExpand(tree, util)
    count = TreeVisible(tree, rows[:])
    testing.expect_value(t, count, 6)
    testing.expect(t, rows[3].node == deep && rows[3].depth == 2 && rows[4].depth == 1 && rows[5].depth == 0, "back up from the deepest level")
    // a node that can have children shows an arrow before it has any
    TreeExpand(tree, util, false)
    lazy, _ := TreeAdd(tree, {}, "folder", branch = true)
    count = TreeVisible(tree, rows[:])
    testing.expect(t, rows[count - 1].node == lazy && rows[count - 1].expandable)
    _ = main
    testing.expect_value(t, TreeVisible(tree, rows[:2]), 2)           // as many as fit
}

@(test)
test_removing_a_node_removes_everything_under_it_and_keeps_the_rest_linked :: proc(t: ^testing.T) {
    tree: ^Tree = newTree()
    defer free(tree)
    a, _ := TreeAdd(tree, {}, "a", branch = true)
    b, _ := TreeAdd(tree, {}, "b", branch = true)
    c, _ := TreeAdd(tree, {}, "c")
    for i in 0 ..< 3 {
        child, _ := TreeAdd(tree, b, "child", branch = true)
        TreeAdd(tree, child, "grandchild")
        TreeAdd(tree, child, "grandchild")
        _ = i
    }
    TreeAdd(tree, a, "under a")
    testing.expect_value(t, TreeCount(tree), 3 + 3 * 3 + 1)
    testing.expect(t, TreeRemove(tree, b))
    testing.expect_value(t, TreeCount(tree), 3)                        // a, "under a", c
    testing.expect(t, TreeGet(tree, b) == nil && !TreeRemove(tree, b))
    testing.expect(t, TreeGet(tree, a).next == c && TreeGet(tree, c).previous == a, "the nodes around it are linked to each other")
    testing.expect(t, tree.first == a && tree.last == c)
    // the last of a parent, the only child, the first at the top
    under: TreeHandle = TreeGet(tree, a).first_child
    testing.expect(t, TreeRemove(tree, under))
    testing.expect(t, TreeGet(tree, a).first_child == {} && TreeGet(tree, a).last_child == {} && TreeGet(tree, a).child_count == 0)
    testing.expect(t, TreeRemove(tree, a))
    testing.expect(t, tree.first == c && tree.last == c)
    testing.expect(t, TreeRemove(tree, c))
    testing.expect(t, tree.first == {} && tree.last == {} && TreeCount(tree) == 0)
}

@(test)
test_revealing_a_node_opens_the_nodes_above_it :: proc(t: ^testing.T) {
    tree: ^Tree = newTree()
    defer free(tree)
    a, _ := TreeAdd(tree, {}, "a", branch = true)
    b, _ := TreeAdd(tree, a, "b", branch = true)
    c, _ := TreeAdd(tree, b, "c")
    rows: [8]TreeRow
    testing.expect_value(t, TreeVisible(tree, rows[:]), 1)
    TreeReveal(tree, c)
    testing.expect_value(t, TreeVisible(tree, rows[:]), 3)
    _, added := TreeAdd(tree, TreeHandle{idx = 99, gen = 1}, "x")
    testing.expect(t, !added, "a parent that is not there")
}
