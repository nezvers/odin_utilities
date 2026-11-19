package ui

// Docking: panels that sit in tabs inside of a tree of splits, and that the person moves by dragging their tab. The layout is plain data in a `Dock` that the program owns (fixed capacities,
// no pointers into it, so it can be copied, saved and loaded as bytes), and `UiDock` draws it. A node of the tree is a split (two children and a proportion) or a leaf (the panels that share
// a place, one tab each, one shown). The program only says what is in a panel:
//
//     dock: ui.Dock
//     ui.DockInit(&dock)
//     tools, _ := ui.DockPanelAdd(&dock, "Tools")
//     view, _ := ui.DockPanelAdd(&dock, "View")
//     ui.DockPanelDock(&dock, tools, ui.DockLeafOf(&dock, view), .LEFT)          // Tools to the left of View
//     ...
//     ui.UiDock(&ctx, "workspace", &dock, proc(ctx: ^ui.Context, dock: ^ui.Dock, panel: int, user: rawptr) {
//         switch panel { case 0: ...; case 1: ... }                              // the content of the panel that is shown
//     })
//
// Dragging a tab over a panel shows where it would go: the middle makes it a tab of that panel, an edge splits the panel and puts the dragged one on that side. The move happens when the
// button goes up, after the frame was built (the tree is never changed while it is declared). The handle between two parts of a split is dragged like UiSplit's. `DockPanelClose` hides a
// panel (the program offers a menu that calls `DockPanelOpen`). `dock.serial` counts every change of the layout, for a program that saves it.

DOCK_NODES :: #config(DOCK_NODES, 64)
DOCK_PANELS :: #config(DOCK_PANELS, 32)
DOCK_MIN_SIZE :: f32(60)                // the least room a part of a split keeps

DockZone :: enum u8 {
    CENTER,             // a tab of the panel that is there
    LEFT,
    RIGHT,
    TOP,
    BOTTOM,
}

DockNodeKind :: enum u8 {
    LEAF,
    SPLIT,
}

DockNode :: struct {
    used: bool,
    kind: DockNodeKind,
    direction: SplitDirection,          // SPLIT: HORIZONTAL puts the first child on the left
    ratio: f32,                         // SPLIT: the part of the room the first child has
    parent: int,                        // -1 for the root
    first, second: int,                 // SPLIT: the children
    panel_count: int,                   // LEAF: the tabs, in order
    active: int,                        // LEAF: the tab that is shown
    panels: [DOCK_PANELS]i8,
}

DockPanel :: struct {
    used: bool,
    name: [GRAPH_NAME_MAX]u8,
    name_length: int,
    node: int,                          // the leaf it is in, -1 while it is closed
    user: rawptr,                       // of the program (not meant to be saved)
}

@(private)
DockMove :: struct {
    panel: int,
    target: int,
    zone: DockZone,
}

Dock :: struct {
    nodes: [DOCK_NODES]DockNode,
    panels: [DOCK_PANELS]DockPanel,
    root: int,                          // -1: nothing is docked
    serial: u64,
    pending: DockMove,                  // a drop that UiDock applies when the frame is built (panel -1: none)
}

DockContentProc :: #type proc(ctx: ^Context, dock: ^Dock, panel: int, user: rawptr)

DockInit :: proc(dock: ^Dock) {
    dock^ = {root = -1, pending = {panel = -1}}
}

DockPanelName :: proc(dock: ^Dock, panel: int) -> string {
    if panel < 0 || panel >= DOCK_PANELS || !dock.panels[panel].used { return "" }
    return string(dock.panels[panel].name[:dock.panels[panel].name_length])
}

DockPanelIsOpen :: proc(dock: ^Dock, panel: int) -> bool {
    return panel >= 0 && panel < DOCK_PANELS && dock.panels[panel].used && dock.panels[panel].node >= 0
}

// The leaf a panel is in (-1 when it is closed or there is no such panel)
DockLeafOf :: proc(dock: ^Dock, panel: int) -> int {
    if panel < 0 || panel >= DOCK_PANELS || !dock.panels[panel].used { return -1 }
    return dock.panels[panel].node
}

// The leaf that comes first in the tree (the top left one), -1 for an empty dock
DockFirstLeaf :: proc(dock: ^Dock) -> int {
    node: int = dock.root
    for node >= 0 && dock.nodes[node].kind == .SPLIT { node = dock.nodes[node].first }
    return node
}

@(private)
dockNodeNew :: proc(dock: ^Dock, kind: DockNodeKind) -> int {
    for &node, i in dock.nodes {
        if !node.used {
            node = {used = true, kind = kind, parent = -1, first = -1, second = -1, ratio = 0.5}
            return i
        }
    }
    return -1
}

@(private)
dockFreeNodes :: proc(dock: ^Dock) -> (count: int) {
    for node in dock.nodes { if !node.used { count += 1 } }
    return
}

// `new` takes the place of `old` in the tree
@(private)
dockReplace :: proc(dock: ^Dock, old: int, new: int) {
    parent: int = dock.nodes[old].parent
    dock.nodes[new].parent = parent
    if parent < 0 {
        dock.root = new
    } else if dock.nodes[parent].first == old {
        dock.nodes[parent].first = new
    } else {
        dock.nodes[parent].second = new
    }
}

// Takes a panel out of its leaf. An empty leaf goes, and the split above it with it: its other child takes the place of the split.
@(private)
dockDetach :: proc(dock: ^Dock, panel: int) {
    leaf_index: int = dock.panels[panel].node
    if leaf_index < 0 { return }
    leaf: ^DockNode = &dock.nodes[leaf_index]
    for i in 0 ..< leaf.panel_count {
        if int(leaf.panels[i]) == panel {
            for j in i ..< leaf.panel_count - 1 { leaf.panels[j] = leaf.panels[j + 1] }
            leaf.panel_count -= 1
            if leaf.active > i || leaf.active >= leaf.panel_count { leaf.active = max(leaf.active - 1, 0) }
            break
        }
    }
    dock.panels[panel].node = -1
    if leaf.panel_count > 0 { return }
    parent: int = leaf.parent
    if parent < 0 {
        dock.root = -1
    } else {
        sibling: int = dock.nodes[parent].second if dock.nodes[parent].first == leaf_index else dock.nodes[parent].first
        dockReplace(dock, parent, sibling)
        dock.nodes[parent] = {}
    }
    dock.nodes[leaf_index] = {}
}

@(private)
dockAttach :: proc(dock: ^Dock, panel: int, leaf_index: int) {
    leaf: ^DockNode = &dock.nodes[leaf_index]
    leaf.panels[leaf.panel_count] = i8(panel)
    leaf.active = leaf.panel_count
    leaf.panel_count += 1
    dock.panels[panel].node = leaf_index
}

// A panel with a name. It is docked as a tab in the first leaf (the dock gets its first leaf from the first panel), or left closed.
DockPanelAdd :: proc(dock: ^Dock, name: string, user: rawptr = nil, closed: bool = false) -> (panel: int, ok: bool) {
    for &entry, i in dock.panels {
        if entry.used { continue }
        entry = {used = true, node = -1, user = user}
        setName(entry.name[:], &entry.name_length, name)
        dock.serial += 1
        if !closed { DockPanelOpen(dock, i) }
        return i, true
    }
    return -1, false
}

// Shows a closed panel again: as a tab in the first leaf, or as the whole dock when it is empty
DockPanelOpen :: proc(dock: ^Dock, panel: int) -> bool {
    if panel < 0 || panel >= DOCK_PANELS || !dock.panels[panel].used || dock.panels[panel].node >= 0 { return false }
    leaf: int = DockFirstLeaf(dock)
    if leaf < 0 {
        leaf = dockNodeNew(dock, .LEAF)
        if leaf < 0 { return false }
        dock.root = leaf
    } else if dock.nodes[leaf].panel_count == DOCK_PANELS {
        return false
    }
    dockAttach(dock, panel, leaf)
    dock.serial += 1
    return true
}

// Hides a panel (it stays in the dock, closed). An empty place goes.
DockPanelClose :: proc(dock: ^Dock, panel: int) -> bool {
    if !DockPanelIsOpen(dock, panel) { return false }
    dockDetach(dock, panel)
    dock.serial += 1
    return true
}

// Moves an open or closed panel next to the panel in leaf `target`: as a tab (CENTER) or beside it (the other zones: the leaf is split and the panel gets its own part on that side). Nothing is
// changed when it cannot be done (no room in the storage, no such leaf, the panel is alone in the leaf it would split).
DockPanelDock :: proc(dock: ^Dock, panel: int, target: int, zone: DockZone = .CENTER) -> bool {
    if panel < 0 || panel >= DOCK_PANELS || !dock.panels[panel].used { return false }
    if dock.root < 0 {
        // an empty dock: the panel is all of it
        return DockPanelOpen(dock, panel)
    }
    if target < 0 || target >= DOCK_NODES || !dock.nodes[target].used || dock.nodes[target].kind != .LEAF { return false }
    source: int = dock.panels[panel].node
    if source == target && (zone != .CENTER && dock.nodes[target].panel_count == 1) { return false }
    if source == target && zone == .CENTER { return false }
    if zone == .CENTER && dock.nodes[target].panel_count == DOCK_PANELS { return false }
    if zone != .CENTER && dockFreeNodes(dock) < 2 { return false }
    dockDetach(dock, panel)
    if zone == .CENTER {
        dockAttach(dock, panel, target)
    } else {
        // the target stays where it is in the order of the tree: a new split takes its place and holds the target and the new leaf
        split: int = dockNodeNew(dock, .SPLIT)
        leaf: int = dockNodeNew(dock, .LEAF)
        dockReplace(dock, target, split)
        dock.nodes[split].direction = .HORIZONTAL if zone == .LEFT || zone == .RIGHT else .VERTICAL
        before: bool = zone == .LEFT || zone == .TOP
        if before {
            dock.nodes[split].first, dock.nodes[split].second = leaf, target
        } else {
            dock.nodes[split].first, dock.nodes[split].second = target, leaf
        }
        dock.nodes[target].parent, dock.nodes[leaf].parent = split, split
        dockAttach(dock, panel, leaf)
    }
    dock.serial += 1
    return true
}

DockSetRatio :: proc(dock: ^Dock, node: int, ratio: f32) {
    if node < 0 || node >= DOCK_NODES || !dock.nodes[node].used || dock.nodes[node].kind != .SPLIT { return }
    dock.nodes[node].ratio = clamp(ratio, SPLIT_RATIO_MIN, 1 - SPLIT_RATIO_MIN)
    dock.serial += 1
}

// The layout is consistent: every open panel is in exactly one leaf, every leaf has panels, the links of the tree agree. For tests and for a layout that was loaded from a file.
DockCheck :: proc(dock: ^Dock) -> bool {
    reached: [DOCK_NODES]bool
    seen: [DOCK_PANELS]int
    visit :: proc(dock: ^Dock, node: int, parent: int, reached: ^[DOCK_NODES]bool, seen: ^[DOCK_PANELS]int) -> bool {
        if node < 0 || node >= DOCK_NODES || reached[node] || !dock.nodes[node].used || dock.nodes[node].parent != parent { return false }
        reached[node] = true
        entry: ^DockNode = &dock.nodes[node]
        if entry.kind == .SPLIT {
            return entry.first != entry.second && visit(dock, entry.first, node, reached, seen) && visit(dock, entry.second, node, reached, seen)
        }
        if entry.panel_count <= 0 || entry.active < 0 || entry.active >= entry.panel_count { return false }
        for i in 0 ..< entry.panel_count {
            panel: int = int(entry.panels[i])
            if panel < 0 || panel >= DOCK_PANELS || !dock.panels[panel].used || dock.panels[panel].node != node { return false }
            seen[panel] += 1
        }
        return true
    }
    if dock.root >= 0 && !visit(dock, dock.root, -1, &reached, &seen) { return false }
    for node, i in dock.nodes {
        if node.used != reached[i] { return false }
    }
    for panel, i in dock.panels {
        if panel.used && (seen[i] > 1 || (seen[i] == 0 && panel.node >= 0)) { return false }
    }
    return true
}

// Where in `rect` a dragged panel would go when dropped at `point`: the middle makes a tab, the nearest edge a split on that side
DockDropZone :: proc(rect: Rect, point: Vec2) -> DockZone {
    if rect.z <= 0 || rect.w <= 0 { return .CENTER }
    fx: f32 = (point.x - rect.x) / rect.z
    fy: f32 = (point.y - rect.y) / rect.w
    if fx > 0.3 && fx < 0.7 && fy > 0.3 && fy < 0.7 { return .CENTER }
    distances: [4]f32 = {fx, 1 - fx, fy, 1 - fy}
    nearest: int
    for i in 1 ..< 4 { if distances[i] < distances[nearest] { nearest = i } }
    zones: [4]DockZone = {.LEFT, .RIGHT, .TOP, .BOTTOM}
    return zones[nearest]
}

// The part of `rect` that a drop in `zone` takes: half of it on the side, all of it for a tab
DockZoneRect :: proc(rect: Rect, zone: DockZone) -> Rect {
    switch zone {
    case .LEFT: return {rect.x, rect.y, rect.z * 0.5, rect.w}
    case .RIGHT: return {rect.x + rect.z * 0.5, rect.y, rect.z * 0.5, rect.w}
    case .TOP: return {rect.x, rect.y, rect.z, rect.w * 0.5}
    case .BOTTOM: return {rect.x, rect.y + rect.w * 0.5, rect.z, rect.w * 0.5}
    case .CENTER: return rect
    }
    return rect
}

// ------------------------------------------------------------------------------------------------------------------------
// The widget

DOCK_DRAG_KIND :: "dock_panel"

// The dock fills the room it is given (`size` says otherwise). Every shown panel's `content` is called inside of its place (a column that cuts what does not fit).
UiDock :: proc(ctx: ^Context, name: string, dock: ^Dock, content: DockContentProc, user: rawptr = nil, size: Size = {}) {
    id: Id = UiId(ctx, name)
    dock.pending = {panel = -1}
    ElementOpen(ctx, {
        id = id,
        layout = {size = {growWhenUnset(size.width), growWhenUnset(size.height)}},
        clip = {horizontal = true, vertical = true, cut = true},
    })
    if dock.root >= 0 { dockBuild(ctx, dock, dock.root, id, {Grow(), Grow()}, content, user) }
    if source, active := UiDragging(ctx); active && ctx.drag.kind == IdFromString(DOCK_DRAG_KIND) && source != 0 {
        UiDragPreview(ctx, DockPanelName(dock, (^int)(raw_data(UiDragPayload(ctx)))^))
    }
    ElementClose(ctx)
    if dock.pending.panel >= 0 {
        DockPanelDock(dock, dock.pending.panel, dock.pending.target, dock.pending.zone)
        dock.pending = {panel = -1}
    }
}

@(private)
dockBuild :: proc(ctx: ^Context, dock: ^Dock, node_index: int, dock_id: Id, size: Size, content: DockContentProc, user: rawptr) {
    node: ^DockNode = &dock.nodes[node_index]
    node_id: Id = IdFromIndex(u32(node_index), dock_id)
    state: ^WidgetState = stateGet(ctx, node_id)
    if node.kind == .SPLIT {
        horizontal: bool = node.direction == .HORIZONTAL
        extent: f32 = state.rect.z if horizontal else state.rect.w
        ElementOpen(ctx, {
            id = node_id,
            layout = {size = size, direction = .LEFT_TO_RIGHT if horizontal else .TOP_TO_BOTTOM},
            clip = {horizontal = true, vertical = true, cut = true},
        })
        if extent > 0 { node.ratio = clamp(node.ratio, DOCK_MIN_SIZE / extent, max((extent - SPLITTER_THICKNESS - DOCK_MIN_SIZE) / extent, DOCK_MIN_SIZE / extent)) }
        first: SizingAxis = Percent(node.ratio)
        first.min = DOCK_MIN_SIZE
        second: SizingAxis = Percent(max(1 - node.ratio - SPLITTER_THICKNESS / extent, 0)) if extent > 0 else Grow(DOCK_MIN_SIZE)
        dockBuild(ctx, dock, node.first, dock_id, {first, Grow()} if horizontal else {Grow(), first}, content, user)
        dockHandle(ctx, dock, node, node_id, extent)
        dockBuild(ctx, dock, node.second, dock_id, {second, Grow()} if horizontal else {Grow(), second}, content, user)
        ElementClose(ctx)
        return
    }
    metrics: ^Metrics = &ctx.style.metrics
    ElementOpen(ctx, {
        id = node_id,
        layout = {size = size, direction = .TOP_TO_BOTTOM},
        clip = {horizontal = true, vertical = true, cut = true},
        draw = {kind = .PANEL, font_size = metrics.font_size},
    })
    ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .LEFT_TO_RIGHT, gap = 2}})
    for i in 0 ..< node.panel_count {
        panel: int = int(node.panels[i])
        tab: Id = IdFromIndex(u32(panel), IdFromString("tab", dock_id))
        _ = stateGet(ctx, tab)
        interaction: Interaction = widgetBehavior(ctx, tab)
        if interaction.clicked { node.active = i }
        shown: string = DockPanelName(dock, panel)
        ElementOpen(ctx, {
            id = tab,
            layout = {size = {Fit(textWidth(ctx, shown) + metrics.padding.x * 2), Fixed(metrics.control_height)}},
            hit = {.INTERACTIVE},
            draw = {kind = .TAB, name = shown, font_size = metrics.font_size, flags = {.SELECTED} if node.active == i else {}},
        })
        ElementClose(ctx)
        ctx.last_id = tab
        moved: int = panel
        UiDragSourceValue(ctx, DOCK_DRAG_KIND, &moved)
    }
    ElementClose(ctx)
    ElementOpen(ctx, {layout = {size = {Grow(), Grow()}, direction = .TOP_TO_BOTTOM, padding = PaddingXY(metrics.padding.x, metrics.padding.y)}, clip = {horizontal = true, vertical = true, cut = true}})
    if node.panel_count > 0 { content(ctx, dock, int(node.panels[node.active]), user) }
    ElementClose(ctx)
    // a tab is over this place: show where it would go, and take the drop
    if _, dragging := UiDragging(ctx); dragging && ctx.drag.kind == IdFromString(DOCK_DRAG_KIND) && RectContains(state.rect, ctx.input.mouse_position) {
        zone: DockZone = DockDropZone(state.rect, ctx.input.mouse_position)
        area: Rect = DockZoneRect(state.rect, zone)
        ElementOpen(ctx, {
            layout = {size = {Fixed(area.z), Fixed(area.w)}},
            floating = {attach_to = .ROOT, offset = {area.x, area.y}, z_index = 440},
            draw = {kind = .HIGHLIGHT, color = {90, 150, 255, 255}},
        })
        ElementClose(ctx)
        if ctx.input.mouse_released { dock.pending = {panel = (^int)(raw_data(UiDragPayload(ctx)))^, target = node_index, zone = zone} }
    }
    ElementClose(ctx)
}

// The handle between the two parts of a split: it moves the proportion that the split keeps (the same way as UiSplit's)
@(private)
dockHandle :: proc(ctx: ^Context, dock: ^Dock, node: ^DockNode, node_id: Id, extent: f32) {
    id: Id = IdFromString("handle", node_id)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    horizontal: bool = node.direction == .HORIZONTAL
    axis: int = 0 if horizontal else 1
    if extent > 0 && interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
        if ctx.input.mouse_pressed {
            state.drag = ctx.input.mouse_position
        } else {
            shown: f32 = node.ratio * extent
            wanted: f32 = shown + (ctx.input.mouse_position[axis] - state.drag[axis])
            applied: f32 = clamp(wanted, DOCK_MIN_SIZE, max(extent - SPLITTER_THICKNESS - DOCK_MIN_SIZE, DOCK_MIN_SIZE))
            state.drag[axis] += applied - shown
            node.ratio = clamp(applied / extent, SPLIT_RATIO_MIN, 1 - SPLIT_RATIO_MIN)
            dock.serial += 1
        }
    }
    flags: Flags
    if interaction.hovered { flags += {.HOVERED} }
    if interaction.pressed { flags += {.PRESSED} }
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Fixed(SPLITTER_THICKNESS), Grow()} if horizontal else {Grow(), Fixed(SPLITTER_THICKNESS)}},
        hit = {.INTERACTIVE},
        cursor = .RESIZE_HORIZONTAL if horizontal else .RESIZE_VERTICAL,
        draw = {kind = .SPLITTER, name = "dock", actual = f32(node.direction), flags = flags, font_size = ctx.style.metrics.font_size},
    })
    ElementClose(ctx)
}
