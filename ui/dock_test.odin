#+build !js
package ui

import "core:testing"

@(private = "file")
newDock :: proc() -> ^Dock {
    dock: ^Dock = new(Dock)
    DockInit(dock)
    return dock
}

@(test)
test_the_first_panels_share_one_leaf_and_a_split_puts_one_beside_another :: proc(t: ^testing.T) {
    dock: ^Dock = newDock()
    defer free(dock)
    a, _ := DockPanelAdd(dock, "A")
    b, _ := DockPanelAdd(dock, "B")
    testing.expect_value(t, DockLeafOf(dock, a), DockLeafOf(dock, b))
    testing.expect(t, DockCheck(dock))
    testing.expect(t, DockPanelDock(dock, a, DockLeafOf(dock, b), .LEFT))
    testing.expect(t, DockCheck(dock))
    root: ^DockNode = &dock.nodes[dock.root]
    testing.expect_value(t, root.kind, DockNodeKind.SPLIT)
    testing.expect_value(t, root.direction, SplitDirection.HORIZONTAL)
    testing.expect_value(t, root.first, DockLeafOf(dock, a))
    testing.expect_value(t, root.second, DockLeafOf(dock, b))
    testing.expect(t, DockPanelDock(dock, a, DockLeafOf(dock, b), .BOTTOM), "a panel moves from one leaf to the other side of it")
    testing.expect(t, DockCheck(dock))
    testing.expect_value(t, dock.nodes[dock.root].direction, SplitDirection.VERTICAL)
    testing.expect_value(t, dock.nodes[dock.root].second, DockLeafOf(dock, a))
}

@(test)
test_an_empty_leaf_and_its_split_go_and_a_tab_drop_joins_a_leaf :: proc(t: ^testing.T) {
    dock: ^Dock = newDock()
    defer free(dock)
    a, _ := DockPanelAdd(dock, "A")
    b, _ := DockPanelAdd(dock, "B")
    c, _ := DockPanelAdd(dock, "C")
    DockPanelDock(dock, a, DockLeafOf(dock, b), .LEFT)
    DockPanelDock(dock, c, DockLeafOf(dock, b), .TOP)
    testing.expect(t, DockCheck(dock))
    used: int
    for node in dock.nodes { if node.used { used += 1 } }
    testing.expect_value(t, used, 5)                                    // 3 leaves and 2 splits
    testing.expect(t, DockPanelDock(dock, c, DockLeafOf(dock, a), .CENTER))
    testing.expect(t, DockCheck(dock))
    used = 0
    for node in dock.nodes { if node.used { used += 1 } }
    testing.expect_value(t, used, 3)                                    // c left its leaf: that leaf and the split above it are gone
    testing.expect_value(t, DockLeafOf(dock, c), DockLeafOf(dock, a))
    testing.expect_value(t, dock.nodes[DockLeafOf(dock, a)].active, 1)  // the dropped tab is the shown one
    testing.expect(t, !DockPanelDock(dock, c, DockLeafOf(dock, c), .CENTER), "a tab dropped on its own place is nothing")
    testing.expect(t, !DockPanelDock(dock, b, DockLeafOf(dock, b), .LEFT), "a panel that is alone cannot split its own place")
}

@(test)
test_closing_the_last_panel_empties_the_dock_and_opening_brings_it_back :: proc(t: ^testing.T) {
    dock: ^Dock = newDock()
    defer free(dock)
    a, _ := DockPanelAdd(dock, "A")
    b, _ := DockPanelAdd(dock, "B", closed = true)
    testing.expect(t, !DockPanelIsOpen(dock, b))
    testing.expect(t, DockPanelClose(dock, a))
    testing.expect_value(t, dock.root, -1)
    testing.expect(t, DockCheck(dock))
    testing.expect(t, !DockPanelClose(dock, a), "closed already")
    testing.expect(t, DockPanelDock(dock, b, -1, .CENTER), "into an empty dock")
    testing.expect(t, DockPanelOpen(dock, a))
    testing.expect_value(t, DockLeafOf(dock, a), DockLeafOf(dock, b))
    testing.expect(t, DockCheck(dock))
    testing.expect_value(t, DockPanelName(dock, a), "A")
}

@(test)
test_a_dock_that_is_full_refuses_a_split_and_stays_whole :: proc(t: ^testing.T) {
    dock: ^Dock = newDock()
    defer free(dock)
    a, _ := DockPanelAdd(dock, "A")
    b, _ := DockPanelAdd(dock, "B")
    spared: bool
    for &node in dock.nodes {
        if node.used { continue }
        if !spared { spared = true; continue }                           // one node stays free: a split needs two
        node = {used = true, kind = .LEAF, parent = -1, first = -1, second = -1}
    }
    testing.expect_value(t, dockFreeNodes(dock), 1)
    testing.expect(t, !DockPanelDock(dock, a, DockLeafOf(dock, b), .RIGHT))
    testing.expect_value(t, DockLeafOf(dock, a), DockLeafOf(dock, b))
    testing.expect_value(t, dock.nodes[DockLeafOf(dock, a)].panel_count, 2)
}

@(test)
test_the_drop_zone_is_the_middle_or_the_nearest_edge :: proc(t: ^testing.T) {
    rect: Rect = {100, 100, 200, 100}
    testing.expect_value(t, DockDropZone(rect, {200, 150}), DockZone.CENTER)
    testing.expect_value(t, DockDropZone(rect, {105, 150}), DockZone.LEFT)
    testing.expect_value(t, DockDropZone(rect, {295, 150}), DockZone.RIGHT)
    testing.expect_value(t, DockDropZone(rect, {200, 102}), DockZone.TOP)
    testing.expect_value(t, DockDropZone(rect, {200, 198}), DockZone.BOTTOM)
    testing.expect_value(t, DockZoneRect(rect, .LEFT), Rect{100, 100, 100, 100})
    testing.expect_value(t, DockZoneRect(rect, .BOTTOM), Rect{100, 150, 200, 50})
}

@(test)
test_a_tab_is_inserted_among_the_tabs_of_a_leaf_or_moved_within_it :: proc(t: ^testing.T) {
    dock: ^Dock = newDock()
    defer free(dock)
    a, _ := DockPanelAdd(dock, "A")
    b, _ := DockPanelAdd(dock, "B")
    c, _ := DockPanelAdd(dock, "C")
    leaf: ^DockNode = &dock.nodes[DockLeafOf(dock, a)]
    order :: proc(leaf: ^DockNode) -> [3]i8 { return {leaf.panels[0], leaf.panels[1], leaf.panels[2]} }
    testing.expect_value(t, order(leaf), [3]i8{0, 1, 2})
    testing.expect(t, DockPanelInsert(dock, c, DockLeafOf(dock, a), 0))
    testing.expect_value(t, order(leaf), [3]i8{2, 0, 1})
    testing.expect_value(t, leaf.active, 0)                                   // the moved tab is the shown one
    testing.expect(t, !DockPanelInsert(dock, c, DockLeafOf(dock, a), 0), "where it is")
    testing.expect(t, !DockPanelInsert(dock, c, DockLeafOf(dock, a), 1), "just after itself is where it is")
    testing.expect(t, DockPanelInsert(dock, c, DockLeafOf(dock, a), 99), "a big number is the end")
    testing.expect_value(t, order(leaf), [3]i8{0, 1, 2})
    testing.expect(t, DockPanelInsert(dock, a, DockLeafOf(dock, a), 2))
    testing.expect_value(t, order(leaf), [3]i8{1, 0, 2})
    // from another leaf: the tab joins at the place and the empty leaf goes
    testing.expect(t, DockPanelDock(dock, b, DockLeafOf(dock, a), .RIGHT))
    testing.expect(t, DockPanelInsert(dock, b, DockLeafOf(dock, a), 1))
    testing.expect(t, DockCheck(dock))
    testing.expect_value(t, DockLeafOf(dock, b), DockLeafOf(dock, a))
    testing.expect_value(t, dock.nodes[DockLeafOf(dock, a)].panels[1], i8(b))
    testing.expect_value(t, dock.root, DockLeafOf(dock, a))
}

@(test)
test_a_panel_floats_and_is_docked_again_and_a_floating_panel_can_close :: proc(t: ^testing.T) {
    dock: ^Dock = newDock()
    defer free(dock)
    a, _ := DockPanelAdd(dock, "A")
    b, _ := DockPanelAdd(dock, "B")
    testing.expect(t, DockPanelFloat(dock, b, {100, 50}, {200, 150}))
    testing.expect(t, DockPanelIsFloating(dock, b) && DockPanelIsOpen(dock, b))
    testing.expect_value(t, DockLeafOf(dock, b), -1)
    testing.expect_value(t, dock.nodes[DockLeafOf(dock, a)].panel_count, 1)
    testing.expect(t, DockCheck(dock))
    testing.expect(t, !DockPanelOpen(dock, b), "it is open already")
    testing.expect(t, DockPanelDock(dock, b, DockLeafOf(dock, a), .RIGHT))
    testing.expect(t, !DockPanelIsFloating(dock, b))
    testing.expect(t, DockCheck(dock))
    // the last docked panel floats: the dock is empty, and a floating panel docks into an empty dock
    testing.expect(t, DockPanelFloat(dock, a, {0, 0}))
    testing.expect(t, DockPanelFloat(dock, b, {10, 10}))
    testing.expect_value(t, dock.root, -1)
    testing.expect(t, DockCheck(dock))
    testing.expect(t, DockPanelDock(dock, a, -1, .CENTER))
    testing.expect(t, DockPanelIsFloating(dock, b) && !DockPanelIsFloating(dock, a))
    testing.expect(t, DockPanelClose(dock, b), "a floating panel closes")
    testing.expect(t, !DockPanelIsOpen(dock, b) && !DockPanelIsFloating(dock, b))
    testing.expect(t, DockPanelOpen(dock, b))
    testing.expect(t, DockCheck(dock))
}
