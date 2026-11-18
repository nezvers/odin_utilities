package ui

// A tree of rows that open and close: a file browser, a project outline, a list of presets in folders. The model is the program's (fixed storage in the Tree, checked handles, no
// allocation): nodes with a name, a `user` pointer and an open or closed state. `UiTree` flattens the nodes that are visible (the children of open nodes) into rows and shows them as a
// list of any length (virtual.odin: only the rows in view are declared).
//
//     tree: ui.Tree                                              // big: a global or a heap allocation
//     view: ui.TreeView                                          // big too
//     ui.TreeInit(&tree)
//     ui.TreeViewInit(&view)
//     src, _ := ui.TreeAdd(&tree, {}, "src", branch = true)       // a branch may be opened before it has children: add them when `view.toggled` says it was opened
//     ui.TreeAdd(&tree, src, "main.odin", user = &file)
//     ui.UiTree(&ctx, "Files", &tree, &view, {ui.Fixed(300), ui.Fixed(400)})
//     if view.activated { open(view.selected) }
//
// A click on the arrow opens or closes a node, a click on a row selects it, a double click or Enter activates it (a branch opens too); right opens a closed branch or goes to its first child,
// left closes an open branch or goes to the parent; up, down, page up, page down, Home and End move through the visible rows.

import hm "core:container/handle_map"

TREE_NODES :: #config(TREE_NODES, 4096)
TREE_ROWS :: #config(TREE_ROWS, 4096)          // the visible rows (the nodes under open parents) the view can hold
TREE_NAME_MAX :: 64
TREE_INDENT :: f32(16)

TreeHandle :: distinct hm.Handle32

TreeNode :: struct {
    handle: TreeHandle,
    parent: TreeHandle,         // none for a node at the top
    first_child: TreeHandle,
    last_child: TreeHandle,
    next: TreeHandle,           // the next node with the same parent
    previous: TreeHandle,
    name: [TREE_NAME_MAX]u8,
    name_length: int,
    user: rawptr,               // of the program (a file, a preset)
    expanded: bool,
    branch: bool,               // it can have children (it shows an arrow) even while it has none: a folder that is read when it is opened
    child_count: int,
}

Tree :: struct {
    nodes: hm.Static_Handle_Map(TREE_NODES, TreeNode, TreeHandle),
    first: TreeHandle,          // the first node at the top
    last: TreeHandle,
    user: rawptr,
}

TreeInit :: proc(tree: ^Tree, user: rawptr = nil) {
    tree^ = {}
    tree.user = user
}

TreeGet :: proc(tree: ^Tree, handle: TreeHandle) -> ^TreeNode {
    if handle == {} { return nil }
    item, ok := hm.get(&tree.nodes, handle)
    return item if ok else nil
}

TreeName :: proc(node: ^TreeNode) -> string {
    return string(node.name[:node.name_length])
}

TreeCount :: proc(tree: ^Tree) -> int {
    return int(hm.len(tree.nodes))
}

// A node as the last child of `parent` (none: at the top). `branch`: it shows an arrow even without children. False when the parent is gone or the storage is full.
TreeAdd :: proc(tree: ^Tree, parent: TreeHandle, name: string, user: rawptr = nil, branch: bool = false) -> (handle: TreeHandle, ok: bool) {
    owner: ^TreeNode = TreeGet(tree, parent)
    if parent != {} && owner == nil { return }
    node: TreeNode = {parent = parent, user = user, branch = branch}
    count: int = min(len(name), TREE_NAME_MAX)
    copy(node.name[:count], name[:count])
    node.name_length = count
    last: TreeHandle = tree.last if owner == nil else owner.last_child
    node.previous = last
    handle, ok = hm.add(&tree.nodes, node)
    if !ok { return }
    if previous := TreeGet(tree, last); previous != nil { previous.next = handle }
    if owner == nil {
        if tree.first == {} { tree.first = handle }
        tree.last = handle
    } else {
        if owner.first_child == {} { owner.first_child = handle }
        owner.last_child = handle
        owner.child_count += 1
    }
    return
}

// Takes a node out of the list of its parent (the node keeps its own children and is not freed).
@(private)
treeUnlink :: proc(tree: ^Tree, node: ^TreeNode) {
    if previous := TreeGet(tree, node.previous); previous != nil { previous.next = node.next }
    if next := TreeGet(tree, node.next); next != nil { next.previous = node.previous }
    if owner := TreeGet(tree, node.parent); owner != nil {
        if owner.first_child == node.handle { owner.first_child = node.next }
        if owner.last_child == node.handle { owner.last_child = node.previous }
        owner.child_count -= 1
    } else {
        if tree.first == node.handle { tree.first = node.next }
        if tree.last == node.handle { tree.last = node.previous }
    }
    node.next, node.previous = {}, {}
}

// Whether `ancestor` is the node or one of the nodes above it.
TreeIsAbove :: proc(tree: ^Tree, ancestor: TreeHandle, handle: TreeHandle) -> bool {
    for current := handle; current != {}; {
        if current == ancestor { return true }
        node: ^TreeNode = TreeGet(tree, current)
        if node == nil { return false }
        current = node.parent
    }
    return false
}

// Moves a node with everything under it: under `parent` (none: to the top), before the node `before` of that parent (none: as the last child). False when a handle is gone, when `before`
// is not a child of `parent`, or when the node would go into itself or under its own children.
TreeMove :: proc(tree: ^Tree, handle: TreeHandle, parent: TreeHandle, before: TreeHandle = {}) -> bool {
    node: ^TreeNode = TreeGet(tree, handle)
    if node == nil || before == handle { return false }
    if parent != {} && (TreeGet(tree, parent) == nil || TreeIsAbove(tree, handle, parent)) { return false }
    if before != {} {
        marker: ^TreeNode = TreeGet(tree, before)
        if marker == nil || marker.parent != parent { return false }
    }
    treeUnlink(tree, node)
    node.parent = parent
    owner: ^TreeNode = TreeGet(tree, parent)
    next: TreeHandle = before
    previous: TreeHandle = tree.last if owner == nil else owner.last_child
    if before != {} { previous = TreeGet(tree, before).previous }
    node.previous, node.next = previous, next
    if p := TreeGet(tree, previous); p != nil { p.next = handle }
    if n := TreeGet(tree, next); n != nil { n.previous = handle }
    if owner == nil {
        if tree.first == {} || tree.first == before { tree.first = handle }
        if before == {} { tree.last = handle }
    } else {
        if owner.first_child == {} || owner.first_child == before { owner.first_child = handle }
        if before == {} { owner.last_child = handle }
        owner.child_count += 1
    }
    return true
}

// A new name for a node (cut to TREE_NAME_MAX bytes). False when the node is gone or the name is empty.
TreeRename :: proc(tree: ^Tree, handle: TreeHandle, name: string) -> bool {
    node: ^TreeNode = TreeGet(tree, handle)
    if node == nil || len(name) == 0 { return false }
    count: int = min(len(name), TREE_NAME_MAX)
    copy(node.name[:count], name[:count])
    node.name_length = count
    return true
}

// Removes a node with everything under it.
TreeRemove :: proc(tree: ^Tree, handle: TreeHandle) -> bool {
    node: ^TreeNode = TreeGet(tree, handle)
    if node == nil { return false }
    // unlink first, then free the subtree (every node of it, down and across, without recursion)
    treeUnlink(tree, node)
    current: TreeHandle = handle
    for current != {} {
        item: ^TreeNode = TreeGet(tree, current)
        if item.first_child != {} {
            current = item.first_child
            continue
        }
        // a leaf now: remove it and go on at its next sibling, or at its parent
        next: TreeHandle = item.next if current != handle else TreeHandle{}
        parent: TreeHandle = item.parent if current != handle else TreeHandle{}
        hm.remove(&tree.nodes, current)
        if next != {} {
            current = next
        } else if parent != {} {
            parent_node: ^TreeNode = TreeGet(tree, parent)
            parent_node.first_child = {}
            current = parent
        } else {
            current = {}
        }
    }
    return true
}

TreeExpand :: proc(tree: ^Tree, handle: TreeHandle, expanded: bool = true) {
    if node := TreeGet(tree, handle); node != nil { node.expanded = expanded }
}

// Opens every node above a node, so that it is visible.
TreeReveal :: proc(tree: ^Tree, handle: TreeHandle) {
    node: ^TreeNode = TreeGet(tree, handle)
    for node != nil {
        node = TreeGet(tree, node.parent)
        if node != nil { node.expanded = true }
    }
}

// A visible row: a node with how deep it is.
TreeRow :: struct {
    node: TreeHandle,
    depth: u16,
    expandable: bool,
    expanded: bool,
}

// The visible nodes (the children of open nodes) from the top, into `rows`, as many as fit: how many.
TreeVisible :: proc(tree: ^Tree, rows: []TreeRow) -> int {
    count: int
    depth: int
    current: TreeHandle = tree.first
    for current != {} && count < len(rows) {
        node: ^TreeNode = TreeGet(tree, current)
        expandable: bool = node.branch || node.first_child != {}
        rows[count] = {node = current, depth = u16(depth), expandable = expandable, expanded = node.expanded && expandable}
        count += 1
        if node.expanded && node.first_child != {} {
            current = node.first_child
            depth += 1
            continue
        }
        // the next node: a sibling, else a sibling of the nearest parent that has one
        for current != {} {
            item: ^TreeNode = TreeGet(tree, current)
            if item.next != {} {
                current = item.next
                break
            }
            current = item.parent
            depth -= 1
        }
    }
    return count
}

// Like TreeVisible, but only the nodes whose name contains `filter` (without regard to case) and the nodes above them, all of them open: a filter that opens the parents of what matches.
// An empty filter is TreeVisible.
TreeVisibleFiltered :: proc(tree: ^Tree, rows: []TreeRow, filter: string) -> int {
    if filter == "" { return TreeVisible(tree, rows) }
    keep: [TREE_NODES + 1]bool
    it := hm.iterator_make(&tree.nodes)
    for node, handle in hm.iterate(&it) {
        if !containsFold(TreeName(node), filter) { continue }
        // the node and every node above it, until one that is kept already
        for current: TreeHandle = handle; current != {}; {
            if keep[current.idx] { break }
            keep[current.idx] = true
            current = TreeGet(tree, current).parent
        }
    }
    count: int
    depth: int
    current: TreeHandle = tree.first
    for current != {} && count < len(rows) {
        node: ^TreeNode = TreeGet(tree, current)
        if keep[current.idx] {
            // it is open when something under it is kept
            opened: bool
            for child: TreeHandle = node.first_child; child != {}; child = TreeGet(tree, child).next {
                if keep[child.idx] {
                    opened = true
                    break
                }
            }
            rows[count] = {node = current, depth = u16(depth), expandable = node.branch || node.first_child != {}, expanded = opened}
            count += 1
            if opened {
                current = node.first_child
                depth += 1
                for current != {} && !keep[current.idx] { current = TreeGet(tree, current).next }
                if current != {} { continue }
                // (not reached: `opened` says a child is kept)
            }
        }
        // the next kept node: a sibling, else a sibling of the nearest parent that has one
        for current != {} {
            item: ^TreeNode = TreeGet(tree, current)
            next: TreeHandle = item.next
            for next != {} && !keep[next.idx] { next = TreeGet(tree, next).next }
            if next != {} {
                current = next
                break
            }
            current = item.parent
            depth -= 1
        }
    }
    return count
}

// What the widget keeps and tells: the visible rows, the selection, and what happened in this frame.
TreeView :: struct {
    list: VirtualList,
    rows: [TREE_ROWS]TreeRow,
    row_count: int,
    selected: TreeHandle,       // the selected node (none for none)
    changed: bool,              // the selection changed in this frame
    activated: bool,            // a double click or Enter on a node in this frame
    toggled: TreeHandle,        // the node that was opened or closed in this frame (by the pointer or the keys): look at TreeGet(...).expanded
    moved: TreeHandle,          // the node that was dropped somewhere else in this frame (it is moved already: its `parent` says where)
    renamed: TreeHandle,        // the node whose name was changed in this frame (F2, Enter)
    can_drop: TreeCanDropProc,  // nil: a node may go anywhere that is not under itself
    dragging: bool,
    drag_node: TreeHandle,
    drag_start: Vec2,
    drop_row: int,              // the row under the pointer while dragging, VIRTUAL_NONE for none
    renaming: TreeHandle,       // the node that is being edited
    rename_fresh: bool,         // the text field gets the focus in the next frame
    rename_buffer: [TREE_NAME_MAX]u8,
    rename_length: int,
    filter: [TREE_NAME_MAX]u8,  // only the nodes that match and the nodes above them are shown, all open (TreeViewFilter)
    filter_length: int,
}

// Sets the filter of the tree view (a text without regard to case; empty: no filter).
TreeViewFilter :: proc(view: ^TreeView, text: string) {
    view.filter_length = min(len(text), len(view.filter))
    copy(view.filter[:view.filter_length], text[:view.filter_length])
}

@(private)
treeRows :: proc(tree: ^Tree, view: ^TreeView) -> int {
    return TreeVisibleFiltered(tree, view.rows[:], string(view.filter[:view.filter_length]))
}

// Says if a node may be dropped under a parent (none: at the top) before the node `before` (none: last).
TreeCanDropProc :: proc(tree: ^Tree, node: TreeHandle, parent: TreeHandle, before: TreeHandle) -> bool

TreeViewInit :: proc(view: ^TreeView) {
    view^ = {}
    view.list.selected = VIRTUAL_NONE
    view.drop_row = VIRTUAL_NONE
}

@(private)
treeRowOf :: proc(view: ^TreeView, handle: TreeHandle) -> int {
    if handle == {} { return VIRTUAL_NONE }
    for i in 0 ..< view.row_count {
        if view.rows[i].node == handle { return i }
    }
    return VIRTUAL_NONE
}

// The tree as a list of rows with arrows. `row_height` 0: the control height of the style.
UiTree :: proc(ctx: ^Context, name: string, tree: ^Tree, view: ^TreeView, size: Size = {}, row_height: f32 = 0) {
    metrics: ^Metrics = &ctx.style.metrics
    height: f32 = row_height if row_height > 0 else metrics.control_height
    id: Id = UiId(ctx, name)
    view.changed, view.activated, view.toggled, view.moved, view.renamed = false, false, {}, {}, {}
    if TreeGet(tree, view.renaming) == nil { view.renaming = {} }
    editing: bool = view.renaming != {}               // the Enter that ends an edit does not also activate the row
    view.row_count = treeRows(tree, view)
    if TreeGet(tree, view.selected) == nil { view.selected = {} }
    // a selected node that is hidden (a parent was closed) is replaced by its nearest visible parent
    for view.selected != {} && treeRowOf(view, view.selected) == VIRTUAL_NONE {
        view.selected = TreeGet(tree, view.selected).parent
    }
    view.list.selected = treeRowOf(view, view.selected)

    // left and right while the list has the focus: close and open, or go to the parent and to the first child
    if ctx.focus == id && view.selected != {} {
        node: ^TreeNode = TreeGet(tree, view.selected)
        expandable: bool = node.branch || node.first_child != {}
        if .RIGHT in ctx.input.actions {
            if expandable && !node.expanded {
                node.expanded = true
                view.toggled = view.selected
            } else if node.expanded && node.first_child != {} {
                view.selected, view.changed = node.first_child, true
            }
        }
        if .LEFT in ctx.input.actions {
            if expandable && node.expanded {
                node.expanded = false
                view.toggled = view.selected
            } else if node.parent != {} {
                view.selected, view.changed = node.parent, true
            }
        }
        if .RENAME in ctx.input.actions && view.renaming == {} {
            view.renaming, view.rename_fresh = view.selected, true
            view.rename_length = node.name_length
            copy(view.rename_buffer[:node.name_length], node.name[:node.name_length])
        }
        view.row_count = treeRows(tree, view)
        view.list.selected = treeRowOf(view, view.selected)
    }

    view.list.marked = view.drop_row + 1 if view.dragging && view.drop_row != VIRTUAL_NONE else 0
    if UiVirtual(ctx, name, &view.list, view.row_count, height, size) {
        if view.list.changed && view.list.selected != VIRTUAL_NONE {
            view.selected = view.rows[view.list.selected].node
            view.changed = true
        }
        if view.list.activated && view.selected != {} && !editing {
            view.activated = true
            if node := TreeGet(tree, view.selected); node != nil && (node.branch || node.first_child != {}) {
                node.expanded = !node.expanded
                view.toggled = view.selected
            }
        }
        treeDrag(ctx, tree, view)
        for row_index in view.list.first ..< view.list.last {
            row: TreeRow = view.rows[row_index]
            node: ^TreeNode = TreeGet(tree, row.node)
            if node == nil { continue }
            if UiVirtualRow(ctx, &view.list, row_index) {
                ElementOpen(ctx, {layout = {size = {Fixed(f32(row.depth) * TREE_INDENT + 4), Grow()}}})
                ElementClose(ctx)
                arrow_id: Id = IdFromIndex(u32(row.node.idx) | u32(row.node.gen) << 16, id)
                _ = stateGet(ctx, arrow_id)
                arrow: Interaction = widgetBehavior(ctx, arrow_id)
                if arrow.clicked && row.expandable {
                    node.expanded = !node.expanded
                    view.toggled = row.node
                }
                ElementOpen(ctx, {
                    id = arrow_id,
                    layout = {size = {Fixed(TREE_INDENT), Grow()}},
                    hit = {.INTERACTIVE, .NO_FOCUS} if row.expandable else {},
                    draw = {kind = .ARROW if row.expandable else .NONE, actual = 1 if row.expanded else 3, hover = 1 if arrow.hovered else 0, font_size = metrics.font_size},
                })
                ElementClose(ctx)
                ElementOpen(ctx, {layout = {size = {Fixed(4), Grow()}}})
                ElementClose(ctx)
                if row.node == view.renaming {
                    text_id: Id = UiId(ctx, "##rename")
                    if view.rename_fresh {
                        // the whole name is selected: typing replaces it, an arrow key edits it
                        ctx.focus = text_id
                        field: ^WidgetState = stateGet(ctx, text_id)
                        field.anchor, field.cursor = 0, view.rename_length
                        view.rename_fresh = false
                    }
                    _, submitted := UiTextField(ctx, "##rename", view.rename_buffer[:], &view.rename_length, {Grow(), Grow()})
                    if submitted {
                        if TreeRename(tree, row.node, string(view.rename_buffer[:view.rename_length])) { view.renamed = row.node }
                        view.renaming = {}
                    } else if .CANCEL in ctx.input.actions || ctx.focus != text_id {
                        view.renaming = {}
                    }
                } else {
                    UiLabel(ctx, TreeName(node))
                }
            }
        }
    }
}

// Dragging a row onto another: onto a branch it goes in (as its last child and the branch opens), onto a file it goes after it, as a sibling. Released outside of a row, or Escape: nothing.
@(private)
treeDrag :: proc(ctx: ^Context, tree: ^Tree, view: ^TreeView) {
    mouse: Vec2 = ctx.input.mouse_position
    if view.renaming != {} { view.dragging, view.drag_node = false, {} }
    if ctx.input.mouse_pressed && view.list.hover != VIRTUAL_NONE && view.renaming == {} {
        view.drag_node, view.drag_start, view.dragging = view.rows[view.list.hover].node, mouse, false
    }
    if view.drag_node == {} { return }
    if TreeGet(tree, view.drag_node) == nil || .CANCEL in ctx.input.actions { view.drag_node, view.dragging, view.drop_row = {}, false, VIRTUAL_NONE; return }
    if ctx.input.mouse_down {
        delta: Vec2 = mouse - view.drag_start
        if !view.dragging && delta.x * delta.x + delta.y * delta.y > 36 { view.dragging = true }
        view.drop_row = view.list.hover if view.dragging else VIRTUAL_NONE
        return
    }
    // released
    if view.dragging && view.list.hover != VIRTUAL_NONE {
        target: ^TreeNode = TreeGet(tree, view.rows[view.list.hover].node)
        if target != nil && target.handle != view.drag_node {
            parent, before: TreeHandle = target.parent, target.next
            into: bool = target.branch || target.first_child != {}
            if into { parent, before = target.handle, {} }
            if (view.can_drop == nil || view.can_drop(tree, view.drag_node, parent, before)) && TreeMove(tree, view.drag_node, parent, before) {
                view.moved = view.drag_node
                if into { target.expanded = true }
                view.selected, view.changed = view.drag_node, true
            }
        }
    }
    view.drag_node, view.dragging, view.drop_row = {}, false, VIRTUAL_NONE
}
