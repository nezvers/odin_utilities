package ui

// A node graph on screen: a canvas that pans, nodes inside of it that are dragged by their title, pins on the nodes that make cables when they are dragged,
// zip ties, and a minimap. The graph itself (graph.odin) is the program's; the widgets draw it and change it with the pointer, and the changes come back
// as events.
//
//     if ui.UiGraph(&ctx, "Audio", &graph, &view) {                           // the canvas: nodes can only be declared inside of it
//         for each node, in the order of GraphNodeAt (the front one last):
//             if ui.UiGraphNode(&ctx, &graph, node) {                           // the title bar drags it; the body takes any widgets
//                 ui.UiSlider(&ctx, "Gain", &gain, 0, 2)
//                 for each port of the node: ui.UiGraphPin(&ctx, &graph, port)
//             }
//     }
//     ui.UiGraphMinimap(&ctx, "map", &graph, &view)                           // anywhere: the whole graph, and the part that the canvas shows
//
// A pin is dragged like anything else that is dragged and dropped (dragdrop.odin): the cable follows the pointer, the pins that the cable fits are lit, one
// that it does not fit is dimmed, and where it is let go it is connected (GraphConnect, with the rules of the graph). Dragging from an input that has a
// cable takes that cable. Cables, ties and the cable that is dragged are drawn by the style (graph_style.odin) in the order: background, cables, ties,
// nodes, the cable that is dragged.
//
// A node is an absolute child of the canvas (it sits at its position, takes no room in the flow, drawn and hit in the order it is declared), not a floating root,
// so the number of nodes is only limited by the elements of the storage. Cables and ties are not elements: they are drawn from the model, and hit with the rectangle and
// the distance function of the style, so a graph with thousands of cables costs the cables that are on screen.

import "core:math"
import hm "core:container/handle_map"

UI_MAX_GRAPHS :: 4              // canvases in one frame
GRAPH_ZOOM_MIN :: f32(0.25)
GRAPH_ZOOM_MAX :: f32(2.5)
GRAPH_ZOOM_STEP :: f32(1.1)     // per notch of the wheel
GRAPH_CABLE_KIND :: "graph cable"

GraphTool :: enum u8 {
    SELECT,             // a press on a cable or a tie selects it, a press on the canvas pans and clears the selection of nodes
    BOX,                // dragging across the canvas draws a rectangle: the nodes it touches are selected (a press without a drag clears the selection)
    TIES,               // dragging across the canvas draws a cut: the cables it crosses are gathered by a zip tie, a tie it crosses is removed
}

@(private)
GraphGesture :: enum u8 {
    NONE,
    PAN,
    TIE_MOVE,
    TIE_ROTATE,
    CUT,
    BOX,
}

// What the canvas keeps for the program: where it looks, what is selected, which tool is on. Everything is plain data, so a program can save the view with the graph.
GraphView :: struct {
    origin: Vec2,               // canvas coordinates at the top left corner of the view
    zoom: f32,                  // how many pixels a canvas unit is (0 is 1); the wheel over the empty canvas changes it, around the pointer
    viewport: Vec2,             // the size of the view in canvas units (the pixels of the canvas divided by the zoom, as in the last frame)
    rect: Rect,                 // where the canvas is on the screen (the same)
    tool: GraphTool,
    moving: NodeHandle,         // the node whose title is held: every selected node moves with it
    move_last: Vec2,            // where the pointer was in the last frame of the move
    selected_link: LinkHandle,
    selected_tie: TieHandle,
    hover_link: LinkHandle,
    hover_tie: TieHandle,
    // gesture state
    gesture: GraphGesture,
    gesture_tie: TieHandle,
    cut_from: Vec2,             // the cut of the tie tool, or the rectangle of the box tool: canvas coordinates
    cut_to: Vec2,
    last_mouse: Vec2,
    pickup_link: LinkHandle,    // the link whose end is being dragged
    drag_source: PortHandle,    // where the cable that is dragged starts
    drag_target: PortHandle,    // the pin under the pointer that it fits
    reroute_on_double_click: bool,  // a double click on a cable puts a reroute point there (GraphRerouteAdd)
    history: ^GraphHistory,     // set: finished edits become steps and Ctrl + Z, Ctrl + Y go through them (graph_history.odin)
    clipboard: ^GraphClipboard, // set: Ctrl + C, X, V and D copy, cut, paste (at the pointer) and duplicate the selected nodes (graph_copy.odin)
}

// The zoom of a view (1 when it was left at 0).
GraphViewZoom :: proc(view: ^GraphView) -> f32 {
    return clamp(view.zoom, GRAPH_ZOOM_MIN, GRAPH_ZOOM_MAX) if view.zoom > 0 else 1
}

// What a canvas is in a frame, for what draws it.
GraphFrame :: struct {
    graph: ^Graph,
    view: ^GraphView,
    style: GraphStyle,          // resolved
    canvas: Id,
    element: i32,
    stamp: u32,
}

// What a minimap draws: the content span and the view in canvas coordinates, and the mapping to the rectangle of the minimap (`rect` of the DrawInfo).
GraphMinimapData :: struct {
    graph: ^Graph,
    view: ^GraphView,
    content: Rect,              // the nodes and the view together, canvas coordinates
    viewport: Rect,            // the part of it that the canvas shows
}

GraphCablePayload :: struct {
    port: PortHandle,           // where the cable starts
    pickup: LinkHandle,         // the link that was taken from an input (nothing for a new cable)
}

@(private)
dot2 :: proc(a: Vec2, b: Vec2) -> f32 {
    return a.x * b.x + a.y * b.y
}

@(private)
graphNodeId :: proc(canvas: Id, handle: NodeHandle) -> Id {
    return IdFromIndex(u32(handle.idx) | u32(handle.gen) << 16, IdFromString("node", canvas))
}

@(private)
graphPinId :: proc(canvas: Id, handle: PortHandle) -> Id {
    return IdFromIndex(u32(handle.idx) | u32(handle.gen) << 16, IdFromString("pin", canvas))
}

// The nodes in the order they are to be declared: the one in front last (nodes are floating elements, the later one is drawn above).
// Writes into `order` and returns how many (the nodes of the graph, or as many as fit).
//
// With a `view`, the nodes that are known to be outside of it are left out (they are not declared, so they cost nothing in the layout; cables and
// ties are drawn from the model and anchors are kept by `GraphNodeMove`). A node that has not been laid out yet is always included, so is the one that is moved.
GraphNodesByDepth :: proc(graph: ^Graph, order: []NodeHandle, view: ^GraphView = nil) -> int {
    count: int
    it := hm.iterator_make(&graph.nodes)
    for node, handle in hm.iterate(&it) {
        if count >= len(order) { break }
        if view != nil && !GraphNodeVisible(view, node) && view.moving != handle { continue }
        // an insertion by z (stable: nodes with one z keep the order of their handles)
        position: int = count
        for position > 0 {
            other: ^Node = GraphNode(graph, order[position - 1])
            if other.z < node.z || other.z == node.z && other.handle.idx < node.handle.idx { break }
            order[position] = order[position - 1]
            position -= 1
        }
        order[position] = handle
        count += 1
    }
    return count
}

// Does the node touch the part of the canvas that is shown? A node of unknown size (it was never declared) does.
GraphNodeVisible :: proc(view: ^GraphView, node: ^Node, margin: f32 = 0) -> bool {
    if node.size.x <= 0 || node.size.y <= 0 || view.viewport.x <= 0 { return true }
    shown: Rect = {view.origin.x - margin, view.origin.y - margin, view.viewport.x + 2 * margin, view.viewport.y + 2 * margin}
    return RectOverlaps({node.position.x, node.position.y, node.size.x, node.size.y}, shown)
}

// The rectangle of all the nodes (canvas coordinates), false for a graph without nodes.
GraphContentBounds :: proc(graph: ^Graph) -> (bounds: Rect, any: bool) {
    low: Vec2 = {INFINITE, INFINITE}
    high: Vec2 = {-INFINITE, -INFINITE}
    it := hm.iterator_make(&graph.nodes)
    for node, _ in hm.iterate(&it) {
        low = {min(low.x, node.position.x), min(low.y, node.position.y)}
        high = {max(high.x, node.position.x + node.size.x), max(high.y, node.position.y + node.size.y)}
        any = true
    }
    if !any { return {}, false }
    return {low.x, low.y, high.x - low.x, high.y - low.y}, true
}

// Moves the view so that all the nodes are in it, centered (as far as they fit: the view does not zoom).
GraphViewFit :: proc(graph: ^Graph, view: ^GraphView) {
    bounds, any := GraphContentBounds(graph)
    if !any { return }
    view.origin = {bounds.x + bounds.z * 0.5 - view.viewport.x * 0.5, bounds.y + bounds.w * 0.5 - view.viewport.y * 0.5}
}

// ------------------------------------------------------------------------------------------------------------------------
// Routes, picking and ties

// The route of a link in canvas coordinates (through its zip ties), false when its pins have not been drawn yet.
@(private)
graphLinkRoute :: proc(graph: ^Graph, link: ^Link, style: ^GraphStyle) -> (route: CableRoute, ok: bool) {
    from, to: ^Port = GraphPort(graph, link.from), GraphPort(graph, link.to)
    if from == nil || to == nil || !from.anchor_known || !to.anchor_known { return }
    input: CableRouteInput = {from = from.anchor, to = to.anchor, link = link.handle, from_port = link.from, to_port = link.to, user = style.user}
    flow: Vec2 = to.anchor - from.anchor
    for i in 0 ..< link.tie_count {
        tie: ^Tie = GraphTie(graph, link.ties[i])
        if tie == nil { continue }
        lane: int = GraphTieLane(graph, tie.handle, link.handle)
        if lane < 0 { continue }
        tangent, _ := TieAxes(tie.angle)
        if dot2(tangent, flow) < 0 { tangent = -tangent }                       // through the tie the way the cable goes
        input.waypoints[input.waypoint_count] = {TieLanePoint(tie, lane, style.tie_spacing), tangent}
        input.waypoint_count += 1
    }
    style.route_connected(&input, &route)
    return route, route.count > 0
}

// The link nearest to a point (canvas coordinates) within the hit distance: the rectangles first, the distance function on the few that hold the point.
@(private)
graphPickLink :: proc(graph: ^Graph, style: ^GraphStyle, point: Vec2) -> LinkHandle {
    best: LinkHandle
    best_distance: f32 = style.hit_distance
    it := hm.iterator_make(&graph.links)
    for link, handle in hm.iterate(&it) {
        route, ok := graphLinkRoute(graph, link, style)
        if !ok { continue }
        if !RectContains(style.bounds(&route, style.hit_distance), point) { continue }
        distance: f32 = style.distance(&route, point)
        if distance < best_distance {
            best_distance = distance
            best = handle
        }
    }
    return best
}

@(private)
graphPickTie :: proc(graph: ^Graph, style: ^GraphStyle, point: Vec2) -> TieHandle {
    best: TieHandle
    it := hm.iterator_make(&graph.ties)
    for tie, handle in hm.iterate(&it) {
        if TieContains(tie, style.tie_spacing, style.tie_width, point, style.hit_distance * 0.5) { best = handle }       // the one drawn last is on top
    }
    return best
}

// The gesture of the tie tool ended: a tie that the cut crosses is removed, else the cables it crosses are gathered by a new tie.
@(private)
graphCut :: proc(graph: ^Graph, view: ^GraphView, style: ^GraphStyle) {
    a, b: Vec2 = view.cut_from, view.cut_to
    delta: Vec2 = b - a
    if dot2(delta, delta) < 36 { return }                                          // a click, not a cut
    removed: bool
    for {
        found: TieHandle
        it := hm.iterator_make(&graph.ties)
        for tie, handle in hm.iterate(&it) {
            if TieCrossedBy(tie, style.tie_spacing, style.tie_width, a, b) { found = handle }
        }
        if found == {} { break }
        GraphTieRemove(graph, found)
        removed = true
    }
    if removed { return }
    Crossing :: struct {
        link: LinkHandle,
        point: Vec2,
        direction: Vec2,
        t: f32,
    }
    crossings: [GRAPH_TIE_MEMBERS]Crossing
    count: int
    cut_bounds: Rect = {min(a.x, b.x), min(a.y, b.y), abs(delta.x), abs(delta.y)}
    it := hm.iterator_make(&graph.links)
    for link, handle in hm.iterate(&it) {
        if count >= len(crossings) { break }
        route, ok := graphLinkRoute(graph, link, style)
        if !ok { continue }
        if !RectOverlaps(style.bounds(&route, 0), {cut_bounds.x - 1, cut_bounds.y - 1, cut_bounds.z + 2, cut_bounds.w + 2}) { continue }
        t, point, direction, crossed := CableCrossing(&route, a, b)
        if crossed {
            crossings[count] = {handle, point, direction, t}
            count += 1
        }
    }
    if count == 0 { return }
    // the strap points the way the first cable it crosses goes; the lanes are in the order the cut met the cables across that direction
    // (the direction at the cut would be the slope of the curve there, steep in the middle of an S: the flow from the outputs to the inputs is calmer)
    flow: Vec2
    for i in 0 ..< count {
        link: ^Link = GraphLink(graph, crossings[i].link)
        from, to: ^Port = GraphPort(graph, link.from), GraphPort(graph, link.to)
        if from == nil || to == nil { continue }
        chord: Vec2 = to.anchor - from.anchor
        length: f32 = math.sqrt(dot2(chord, chord))
        if length > 1e-3 { flow += chord / length }
    }
    if dot2(flow, flow) < 1e-6 { flow = crossings[0].direction }
    angle: f32 = math.atan2(flow.y, flow.x)
    _, normal := TieAxes(angle)
    middle: Vec2
    for i in 0 ..< count { middle += crossings[i].point }
    middle = middle / f32(count)
    for i in 1 ..< count {
        current: Crossing = crossings[i]
        key: f32 = dot2(current.point - middle, normal)
        j: int = i - 1
        for j >= 0 && dot2(crossings[j].point - middle, normal) > key {
            crossings[j + 1] = crossings[j]
            j -= 1
        }
        crossings[j + 1] = current
    }
    links: [GRAPH_TIE_MEMBERS]LinkHandle
    for i in 0 ..< count { links[i] = crossings[i].link }
    if tie, ok := GraphTieAdd(graph, middle, angle, links[:count]); ok {
        view.selected_tie = tie
        view.selected_link = {}
        GraphSelectClear(graph)
    }
}

// Moves every selected node by `delta` (and snaps them to the grid of the style when the move ends, then tells the program about each).
@(private)
graphMoveSelected :: proc(graph: ^Graph, snap: f32, delta: Vec2, done: bool) {
    it := hm.iterator_make(&graph.nodes)
    for node, handle in hm.iterate(&it) {
        if !node.selected { continue }
        position: Vec2 = node.position + delta
        if done && snap > 0 { position = {math.round(position.x / snap) * snap, math.round(position.y / snap) * snap} }
        GraphNodeMove(graph, handle, position)
        if done { graphEmit(graph, {kind = .NODE_MOVED, node = handle, position = position}) }
    }
}

// The box of the box tool ended: the nodes it touches are selected, a press that did not drag clears the selection.
@(private)
graphBoxSelect :: proc(graph: ^Graph, view: ^GraphView) {
    a, b: Vec2 = view.cut_from, view.cut_to
    box: Rect = {min(a.x, b.x), min(a.y, b.y), abs(a.x - b.x), abs(a.y - b.y)}
    GraphSelectClear(graph)
    if box.z < 3 && box.w < 3 { return }
    it := hm.iterator_make(&graph.nodes)
    for node, _ in hm.iterate(&it) {
        node.selected = RectOverlaps({node.position.x, node.position.y, node.size.x, node.size.y}, box)
    }
}

// ------------------------------------------------------------------------------------------------------------------------
// The canvas

// The canvas of a graph. Everything of the graph is declared inside of it (nodes, with their pins). Pans when the empty canvas is dragged, selects a cable or a
// tie that is pressed, moves and turns a tie that is dragged (by its middle, or by its head to turn it), and takes the delete key for what is selected.
@(deferred_in = UiGraphEnd)
UiGraph :: proc(ctx: ^Context, name: string, graph: ^Graph, view: ^GraphView, size: Size = {}) -> bool {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    if ctx.graph_frame_count >= UI_MAX_GRAPHS || ctx.graph_stack_count >= len(ctx.graph_stack) {
        ctx.problems += {.GRAPH_MISUSE}
        ctx.graph_stack[min(ctx.graph_stack_count, len(ctx.graph_stack) - 1)] = -1
        ctx.graph_stack_count += 1
        return ElementOpen(ctx, {})
    }
    graph.frame += 1
    style: GraphStyle = GraphStyleResolved(ctx.style)
    view.rect = state.rect
    interaction: Interaction = widgetBehavior(ctx, id)
    mouse: Vec2 = ctx.input.mouse_position
    // the wheel over the empty canvas zooms around the pointer: the canvas point under it stays there
    if ctx.hover == id && ctx.input.wheel.y != 0 && view.gesture == .NONE && ctx.disabled_depth == 0 {
        before: f32 = GraphViewZoom(view)
        after: f32 = clamp(before * math.pow(GRAPH_ZOOM_STEP, ctx.input.wheel.y), GRAPH_ZOOM_MIN, GRAPH_ZOOM_MAX)
        view.origin += (mouse - {state.rect.x, state.rect.y}) * (1 / before - 1 / after)
        view.zoom = after
    }
    zoom: f32 = GraphViewZoom(view)
    view.viewport = {state.rect.z, state.rect.w} / zoom
    canvas_mouse: Vec2 = (mouse - {state.rect.x, state.rect.y}) / zoom + view.origin
    delta: Vec2 = (mouse - view.last_mouse) / zoom                      // in canvas units
    view.last_mouse = mouse
    // what the pointer may be away from a cable or a tie to count as on it is in pixels: in canvas units it is less when zoomed in
    pick: GraphStyle = style
    pick.hit_distance /= zoom
    view.drag_target = {}

    cable_active: bool = ctx.drag.active && ctx.drag.kind == IdFromString(GRAPH_CABLE_KIND)
    if !cable_active && view.gesture == .NONE {
        view.pickup_link, view.drag_source = {}, {}
    }
    if cable_active && ctx.input.mouse_released && ctx.hover == id {
        // a cable that was dragged from a port is let go over empty room: a program may offer a node to put there
        payload: GraphCablePayload = (^GraphCablePayload)(raw_data(UiDragPayload(ctx)))^ if len(UiDragPayload(ctx)) >= size_of(GraphCablePayload) else {}
        event: GraphEvent = {kind = .DROPPED_ON_EMPTY, position = canvas_mouse}
        if source := GraphPort(graph, payload.port); source != nil {
            event.from, event.from_node, event.from_user = payload.port, source.node, source.user
        }
        if payload.pickup != {} { GraphDisconnect(graph, payload.pickup, .PICKED_UP) }
        graphEmit(graph, event)
    }

    // the nodes that are moved by the title that is held (applied here, before the nodes are declared, so they all move in the same frame)
    if view.moving != {} {
        if GraphNode(graph, view.moving) == nil || (!ctx.input.mouse_down && !ctx.input.mouse_released) {
            view.moving = {}
        } else {
            graphMoveSelected(graph, style.snap, (mouse - view.move_last) / zoom, ctx.input.mouse_released)
            view.move_last = mouse
            if ctx.input.mouse_released { view.moving = {} }
        }
    }
    // what the pointer is over (cables and ties are not elements: the model says)
    if view.gesture == .NONE {
        view.hover_tie, view.hover_link = {}, {}
        if ctx.hover == id && !cable_active && ctx.disabled_depth == 0 {
            view.hover_tie = graphPickTie(graph, &pick, canvas_mouse)
            if view.hover_tie == {} && view.tool == .SELECT { view.hover_link = graphPickLink(graph, &pick, canvas_mouse) }
        }
    }
    // a press on the canvas itself
    if interaction.pressed && ctx.input.mouse_pressed && view.gesture == .NONE && !cable_active {
        switch {
        case view.tool == .TIES:
            view.gesture = .CUT
            view.cut_from, view.cut_to = canvas_mouse, canvas_mouse
        case view.tool == .BOX:
            view.gesture = .BOX
            view.cut_from, view.cut_to = canvas_mouse, canvas_mouse
            view.selected_link, view.selected_tie = {}, {}
        case view.hover_tie != {}:
            tie: ^Tie = GraphTie(graph, view.hover_tie)
            view.gesture_tie = view.hover_tie
            head: Vec2 = TieHead(tie, style.tie_spacing)
            delta_head: Vec2 = canvas_mouse - head
            view.gesture = .TIE_ROTATE if dot2(delta_head, delta_head) < style.tie_width * style.tie_width * 2.25 else .TIE_MOVE
            view.selected_tie, view.selected_link = view.hover_tie, {}
            GraphSelectClear(graph)
        case view.hover_link != {}:
            if interaction.double_clicked && view.reroute_on_double_click {
                if made, ok := GraphRerouteAdd(graph, view.hover_link, canvas_mouse); ok {
                    GraphSelectClear(graph)
                    GraphNodeSelect(graph, made)
                    view.selected_link, view.hover_link = {}, {}
                    break
                }
            }
            view.selected_link, view.selected_tie = view.hover_link, {}
            GraphSelectClear(graph)
        case:
            view.gesture = .PAN
            view.selected_link, view.selected_tie = {}, {}
            GraphSelectClear(graph)
        }
    }
    // the gesture goes on while the button is held, and ends with it
    if view.gesture != .NONE {
        if (ctx.input.mouse_down || ctx.input.mouse_released) && !ctx.input.mouse_pressed {      // the last move comes with the release
            switch view.gesture {
            case .PAN:
                view.origin -= delta
            case .TIE_MOVE:
                if tie := GraphTie(graph, view.gesture_tie); tie != nil { tie.position += delta }
            case .TIE_ROTATE:
                if tie := GraphTie(graph, view.gesture_tie); tie != nil {
                    to_mouse: Vec2 = canvas_mouse - tie.position
                    if dot2(to_mouse, to_mouse) > 4 {
                        angle: f32 = math.atan2(to_mouse.y, to_mouse.x) - math.PI * 0.5       // the head is at +normal, a quarter turn from the cables
                        if style.rotate_snap > 0 {
                            step: f32 = math.to_radians(style.rotate_snap)
                            angle = math.round(angle / step) * step
                        }
                        tie.angle = angle
                    }
                }
            case .CUT, .BOX:
                view.cut_to = canvas_mouse
            case .NONE:
            }
        }
        if ctx.input.mouse_released || !ctx.input.mouse_down {
            #partial switch view.gesture {
            case .TIE_MOVE, .TIE_ROTATE:
                if tie := GraphTie(graph, view.gesture_tie); tie != nil {
                    GraphTieOrderLinks(graph, view.gesture_tie)
                    graphEmit(graph, {kind = .TIE_CHANGED, tie = view.gesture_tie, position = tie.position})
                }
            case .CUT:
                view.cut_to = canvas_mouse
                graphCut(graph, view, &style)
            case .BOX:
                view.cut_to = canvas_mouse
                graphBoxSelect(graph, view)
            }
            view.gesture = .NONE
            view.gesture_tie = {}
        }
    }
    // copy, cut, paste and duplicate while the canvas has the focus (or nothing has it)
    if view.clipboard != nil && (ctx.focus == 0 || ctx.focus == id) && ctx.disabled_depth == 0 && view.gesture == .NONE {
        actions: Actions = ctx.input.actions
        if .COPY in actions || .CUT in actions { GraphCopy(graph, view.clipboard) }
        if .CUT in actions {
            for removed := true; removed; {
                removed = false
                it := hm.iterator_make(&graph.nodes)
                for node, handle in hm.iterate(&it) {
                    if node.selected {
                        GraphNodeRemove(graph, handle)
                        removed = true
                        break
                    }
                }
            }
        }
        if .PASTE in actions {
            // at the pointer when it is over the canvas, else in the middle of the view
            inside: bool = RectContains(state.rect, mouse)
            GraphPaste(graph, view.clipboard, canvas_mouse if inside else view.origin + view.viewport * 0.5 - view.clipboard.size * 0.5)
        }
        if .DUPLICATE in actions { GraphDuplicate(graph, view.clipboard) }
    }
    if view.history != nil && view.gesture == .NONE && view.moving == {} && (ctx.focus == 0 || ctx.focus == id) && ctx.disabled_depth == 0 {
        restored: bool
        if .UNDO in ctx.input.actions { restored = GraphHistoryUndo(view.history, graph) }
        if .REDO in ctx.input.actions { restored = GraphHistoryRedo(view.history, graph) || restored }
        if restored { view.selected_link, view.selected_tie, view.hover_link, view.hover_tie = {}, {}, {}, {} }
    }
    // the delete key removes what is selected
    if .DELETE in ctx.input.keys || .BACKSPACE in ctx.input.keys {
        if ctx.focus == 0 || ctx.focus == id {
            if view.selected_link != {} {
                GraphDisconnect(graph, view.selected_link)
                view.selected_link = {}
            }
            if view.selected_tie != {} {
                GraphTieRemove(graph, view.selected_tie)
                view.selected_tie = {}
            }
            for removed := true; removed; {
                removed = false
                it := hm.iterator_make(&graph.nodes)
                for node, handle in hm.iterate(&it) {
                    if node.selected {
                        GraphNodeRemove(graph, handle)
                        removed = true
                        break
                    }
                }
            }
        }
    }
    // an edit that is finished (no gesture is going on) is a step of the history
    if view.history != nil && view.gesture == .NONE && view.moving == {} { GraphHistoryCommit(view.history, graph) }
    if GraphLink(graph, view.selected_link) == nil { view.selected_link = {} }
    if GraphTie(graph, view.selected_tie) == nil { view.selected_tie = {} }

    frame_index: int = ctx.graph_frame_count
    ctx.graph_frames[frame_index] = {graph = graph, view = view, style = style, canvas = id, element = i32(ctx.element_count), stamp = graph.frame}
    ctx.graph_frame_count += 1
    ctx.graph_stack[ctx.graph_stack_count] = frame_index
    ctx.graph_stack_count += 1
    return ElementOpen(ctx, {
        id = id,
        layout = {size = {size.width if size.width != {} else Grow(), size.height if size.height != {} else Grow()}},
        zoom = zoom,
        clip = {horizontal = true, vertical = true, cut = true},
        hit = {.INTERACTIVE, .NO_FOCUS},
        draw = {kind = .GRAPH, name = IdSplitName(name), user = &ctx.graph_frames[frame_index]},
    })
}

UiGraphEnd :: proc(ctx: ^Context, name: string, graph: ^Graph, view: ^GraphView, size: Size = {}) {
    if ctx.graph_stack_count <= 0 {
        ElementClose(ctx)
        return
    }
    ctx.graph_stack_count -= 1
    frame_index: int = ctx.graph_stack[ctx.graph_stack_count]
    if frame_index >= 0 {
        // the layer above the nodes: the cable that is dragged, the cut
        ElementOpen(ctx, {
            layout = {size = {Grow(), Grow()}},
            floating = {attach_to = .PARENT, parent_point = .LEFT_TOP, element_point = .LEFT_TOP, z_index = graph.z_counter + 1, clip_to_parent = true},
            draw = {kind = .GRAPH_OVERLAY, user = &ctx.graph_frames[frame_index]},
        })
        ElementClose(ctx)
    }
    ElementClose(ctx)
}

// ------------------------------------------------------------------------------------------------------------------------
// Nodes and pins

// A node: a title bar that drags it, and a body for what the program puts in (any widgets, and the pins). `true` while it is declared: false for a node that
// is not there, or outside of a canvas (a problem). The position is the node's (`node.position` in canvas coordinates, kept by the graph).
@(deferred_in = UiGraphNodeEnd)
UiGraphNode :: proc(ctx: ^Context, graph: ^Graph, handle: NodeHandle) -> bool {
    node: ^Node = GraphNode(graph, handle)
    frame: ^GraphFrame = currentGraphFrame(ctx)
    if node == nil || frame == nil || frame.graph != graph {
        if frame == nil || frame.graph != graph { ctx.problems += {.GRAPH_MISUSE} }
        ElementOpen(ctx, {})                         // UiGraphNodeEnd closes two elements either way
        ElementOpen(ctx, {})
        return false
    }
    view: ^GraphView = frame.view
    style: ^GraphStyle = &frame.style
    id: Id = graphNodeId(frame.canvas, handle)
    _ = stateGet(ctx, id)
    title_id: Id = IdFromString("title", id)
    title_state: ^WidgetState = stateGet(ctx, title_id)
    interaction: Interaction = widgetBehavior(ctx, title_id)
    _ = title_state
    if interaction.pressed && ctx.input.mouse_pressed {
        // a node that is not selected becomes the only selected one; one that is selected keeps the others: they move together
        GraphNodeRaise(graph, handle)
        if !node.selected {
            GraphSelectClear(graph)
            node.selected = true
        }
        view.selected_link, view.selected_tie = {}, {}
        view.moving, view.move_last = handle, ctx.input.mouse_position
    }
    metrics: ^Metrics = &ctx.style.metrics
    node_element: i32 = i32(ctx.element_count)
    node.element, node.stamp = node_element, frame.stamp
    selected: bool = node.selected
    if node.reroute {
        // a small dot on a cable: the two pins side by side, the node itself is what is held to move it
        grab: Interaction = widgetBehavior(ctx, id)
        if grab.pressed && ctx.input.mouse_pressed {
            GraphNodeRaise(graph, handle)
            if !node.selected {
                GraphSelectClear(graph)
                node.selected = true
            }
            view.selected_link, view.selected_tie = {}, {}
            view.moving, view.move_last = handle, ctx.input.mouse_position
        }
        ElementOpen(ctx, {
            id = id,
            layout = {size = {Fit(), Fit()}, direction = .LEFT_TO_RIGHT, padding = PaddingXY(3, 3), gap = 2},
            absolute = {enabled = true, offset = node.position - view.origin},
            hit = {.INTERACTIVE, .NO_FOCUS},
            draw = {kind = .GRAPH_NODE, name = "", color = node.color, flags = {.SELECTED} if selected else {}, font_size = metrics.font_size},
        })
        return ElementOpen(ctx, {layout = {size = {Fit(), Fit()}, direction = .LEFT_TO_RIGHT, gap = 2}})
    }
    if interaction.double_clicked && interaction.pressed && ctx.input.mouse_pressed { GraphNodeCollapse(graph, handle, !node.collapsed) }
    // the body of a node is held too: a press on the room between its widgets drags the node (and the selected ones with it), as the title does
    grab: Interaction = widgetBehavior(ctx, id)
    if grab.pressed && ctx.input.mouse_pressed {
        GraphNodeRaise(graph, handle)
        if !node.selected {
            GraphSelectClear(graph)
            node.selected = true
        }
        view.selected_link, view.selected_tie = {}, {}
        view.moving, view.move_last = handle, ctx.input.mouse_position
    }
    selected = node.selected
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Fit(style.node_width), Fit()}, direction = .TOP_TO_BOTTOM},
        absolute = {enabled = true, offset = node.position - view.origin},
        hit = {.INTERACTIVE, .NO_FOCUS, .BLOCKER},
        draw = {kind = .GRAPH_NODE, name = GraphNodeName(node), color = node.color, flags = {.SELECTED} if selected else {}, font_size = metrics.font_size},
    })
    ElementOpen(ctx, {
        id = title_id,
        layout = {size = {Grow(), Fixed(metrics.control_height)}},
        hit = {.INTERACTIVE, .NO_FOCUS},
        draw = {kind = .WINDOW_TITLE, name = GraphNodeName(node), font_size = metrics.font_size, flags = {.FOCUSED} if selected else {}},
    })
    ElementClose(ctx)
    if node.collapsed {
        // only the title: an empty body, and false so that the program declares no pins (the cables go to the edges of the title)
        ElementOpen(ctx, {layout = {size = {Grow(), Fixed(0)}}})
        return false
    }
    return ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .TOP_TO_BOTTOM, padding = PaddingXY(metrics.gap, metrics.gap), gap = metrics.gap}})
}

UiGraphNodeEnd :: proc(ctx: ^Context, graph: ^Graph, handle: NodeHandle) {
    ElementClose(ctx)       // the body
    ElementClose(ctx)       // the node
}

@(private)
currentGraphFrame :: proc(ctx: ^Context) -> ^GraphFrame {
    if ctx.graph_stack_count <= 0 { return nil }
    index: int = ctx.graph_stack[ctx.graph_stack_count - 1]
    if index < 0 { return nil }
    return &ctx.graph_frames[index]
}

// A pin of a node, in the body of the node: the connection point and the name of the port, the input at the left and the output at the right. Drag
// it to make a cable; let a cable go over it to connect it. Nothing for a port that is hidden.
UiGraphPin :: proc(ctx: ^Context, graph: ^Graph, handle: PortHandle) {
    port: ^Port = GraphPort(graph, handle)
    frame: ^GraphFrame = currentGraphFrame(ctx)
    if port == nil || frame == nil || frame.graph != graph {
        if frame == nil { ctx.problems += {.GRAPH_MISUSE} }
        return
    }
    if .HIDDEN in port.flags { return }
    view: ^GraphView = frame.view
    style: ^GraphStyle = &frame.style
    id: Id = graphPinId(frame.canvas, handle)
    _ = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    // what a drag from here would carry: from an input that has a cable, the cable is taken (its output end is the start)
    payload: GraphCablePayload = {port = handle}
    if port.kind == .INPUT && port.link_count > 0 && style.pickup == .PICKUP {
        link: ^Link = GraphLink(graph, port.last_link)
        payload = {port = link.from, pickup = port.last_link}
    }
    dragging_from_here: bool = UiDragSource(ctx, GRAPH_CABLE_KIND, mem_bytes(&payload))
    if dragging_from_here {
        view.drag_source = payload.port
        view.pickup_link = payload.pickup
    }
    // a cable that is dragged and lets go over this pin
    bytes, dropped := UiDropTarget(ctx, GRAPH_CABLE_KIND)
    if dropped && len(bytes) >= size_of(GraphCablePayload) {
        carried: GraphCablePayload = (^GraphCablePayload)(raw_data(bytes))^
        if ConnectOk(GraphCanConnect(graph, carried.port, handle)) {
            if carried.pickup != {} { GraphDisconnect(graph, carried.pickup, .MOVED) }
            GraphConnect(graph, carried.port, handle)
        }
    }
    flags: Flags
    if interaction.hovered { flags += {.HOVERED} }
    if dragging_from_here { flags += {.PRESSED} }
    if port.link_count > 0 { flags += {.ON} }
    if ctx.drag.active && ctx.drag.kind == IdFromString(GRAPH_CABLE_KIND) && !dragging_from_here {
        held: []u8 = UiDragPayload(ctx)
        if len(held) >= size_of(GraphCablePayload) {
            carried: GraphCablePayload = (^GraphCablePayload)(raw_data(held))^
            if ConnectOk(GraphCanConnect(graph, carried.port, handle)) {
                flags += {.SELECTED}                                            // the cable fits here
                if ctx.hover == id { view.drag_target = handle }
            } else {
                flags += {.DISABLED}
            }
        }
    }
    metrics: ^Metrics = &ctx.style.metrics
    output: bool = port.kind == .OUTPUT
    ElementOpen(ctx, {layout = {size = {Grow(), Fit()}, direction = .LEFT_TO_RIGHT, gap = metrics.gap, align = {x = .RIGHT if output else .LEFT, y = .CENTER}}})
    if output { TextOpen(ctx, GraphPortName(port)) }
    port.element, port.stamp = i32(ctx.element_count), frame.stamp
    ElementOpen(ctx, {
        id = id,
        layout = {size = {Fixed(style.pin_size), Fixed(style.pin_size)}},
        hit = {.INTERACTIVE, .NO_FOCUS},
        cursor = .HAND,
        draw = {kind = .GRAPH_PIN, name = GraphPortName(port), color = port.color, flags = flags, actual = f32(port.data_type), cursor = 1 if output else 0, font_size = metrics.font_size},
    })
    ElementClose(ctx)
    if !output { TextOpen(ctx, GraphPortName(port)) }
    ElementClose(ctx)
}

// ------------------------------------------------------------------------------------------------------------------------
// After the layout: where the nodes and the pins are

// Called by UiEnd when the layout is done: the sizes of the nodes and the places of the pins (canvas coordinates) for the next frame's hit tests and for the
// cables of this frame (drawn after this).
@(private)
graphAfterLayout :: proc(ctx: ^Context) {
    for i in 0 ..< ctx.graph_frame_count {
        frame: ^GraphFrame = &ctx.graph_frames[i]
        if int(frame.element) >= ctx.element_count { continue }
        canvas: Rect = ctx.elements[frame.element].rect
        zoom: f32 = GraphViewZoom(frame.view)
        frame.view.rect = canvas
        frame.view.viewport = {canvas.z, canvas.w} / zoom
        graph: ^Graph = frame.graph
        origin: Vec2 = frame.view.origin
        it := hm.iterator_make(&graph.nodes)
        for node, _ in hm.iterate(&it) {
            if node.stamp != frame.stamp || node.element < 0 || int(node.element) >= ctx.element_count { continue }
            node.size = {ctx.elements[node.element].rect.z, ctx.elements[node.element].rect.w} / zoom
        }
        // the pins of a collapsed node are not declared: its cables go to the middle of the left and right edges of the title
        collapsed := hm.iterator_make(&graph.nodes)
        for node, _ in hm.iterate(&collapsed) {
            if node.stamp != frame.stamp || !node.collapsed || node.element < 0 || int(node.element) >= ctx.element_count { continue }
            port_handle: PortHandle = node.first_port
            for port_handle != {} {
                port: ^Port = GraphPort(graph, port_handle)
                if port == nil { break }
                port.anchor = node.position + {0 if port.kind == .INPUT else node.size.x, ctx.style.metrics.control_height * 0.5}
                port.anchor_known = true
                port.offset = port.anchor - node.position
                port.stamp = 0
                port_handle = port.next_in_node
            }
        }
        ports := hm.iterator_make(&graph.ports)
        for port, _ in hm.iterate(&ports) {
            if port.stamp != frame.stamp || port.element < 0 || int(port.element) >= ctx.element_count { continue }
            rect: Rect = ctx.elements[port.element].rect
            port.anchor = {(rect.x + rect.z * 0.5 - canvas.x) / zoom + origin.x, (rect.y + rect.w * 0.5 - canvas.y) / zoom + origin.y}
            port.anchor_known = true
            if node := GraphNode(graph, port.node); node != nil { port.offset = port.anchor - node.position }
        }
    }
    ctx.graph_frame_count = 0
    ctx.graph_stack_count = 0
}

// ------------------------------------------------------------------------------------------------------------------------
// The minimap

// The whole graph in a small box, and the part of it that the canvas shows. The box covers the nodes and the view together (so the view is always inside of it,
// even when it looks at empty room); pressing or dragging in it moves the view there. Declared anywhere (a corner of the window, a panel).
UiGraphMinimap :: proc(ctx: ^Context, name: string, graph: ^Graph, view: ^GraphView, size: Size = {}) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    content, any := GraphContentBounds(graph)
    viewport: Rect = {view.origin.x, view.origin.y, max(view.viewport.x, 1), max(view.viewport.y, 1)}
    if any {
        low: Vec2 = {min(content.x, viewport.x), min(content.y, viewport.y)}
        high: Vec2 = {max(content.x + content.z, viewport.x + viewport.z), max(content.y + content.w, viewport.y + viewport.w)}
        content = {low.x, low.y, high.x - low.x, high.y - low.y}
    } else {
        content = viewport
    }
    if interaction.pressed && ctx.input.mouse_down && state.rect.z > 0 {
        scale, offset := GraphMinimapTransform(content, state.rect)
        point: Vec2 = {(ctx.input.mouse_position.x - offset.x) / scale + content.x, (ctx.input.mouse_position.y - offset.y) / scale + content.y}
        view.origin = point - {viewport.z, viewport.w} * 0.5                             // the view is centered where the pointer is
    }
    metrics: ^Metrics = &ctx.style.metrics
    index: int = min(ctx.graph_minimap_count, len(ctx.graph_minimaps) - 1)
    ctx.graph_minimaps[index] = {graph = graph, view = view, content = content, viewport = viewport}
    ctx.graph_minimap_count = min(ctx.graph_minimap_count + 1, len(ctx.graph_minimaps))
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSize(size, metrics.control_width * 1.2, metrics.control_height * 4)},
        hit = {.INTERACTIVE, .NO_FOCUS, .BLOCKER},
        cursor = .HAND,
        draw = {kind = .GRAPH_MINIMAP, name = IdSplitName(name), user = &ctx.graph_minimaps[index], flags = {.HOVERED} if interaction.hovered else {}},
    })
    ElementClose(ctx)
}

MINIMAP_PADDING :: f32(6)

// How the content span (canvas coordinates) is drawn in a rectangle of the screen: the scale, and where the top left corner of the content goes. The content is
// centered in the room that is left after the padding. A style draws a canvas point as `offset + (point - content.xy) * scale`.
GraphMinimapTransform :: proc(content: Rect, rect: Rect) -> (scale: f32, offset: Vec2) {
    room: Vec2 = {max(rect.z - 2 * MINIMAP_PADDING, 1), max(rect.w - 2 * MINIMAP_PADDING, 1)}
    scale = min(room.x / max(content.z, 1), room.y / max(content.w, 1))
    offset = {rect.x + (rect.z - content.z * scale) * 0.5, rect.y + (rect.w - content.w * scale) * 0.5}
    return
}

// ------------------------------------------------------------------------------------------------------------------------
// For the styles: drawing the cables and the ties

// A point of the canvas as a point of the screen.
GraphToScreen :: proc(view: ^GraphView, point: Vec2) -> Vec2 {
    return (point - view.origin) * GraphViewZoom(view) + {view.rect.x, view.rect.y}
}

@(private)
routeToScreen :: proc(route: ^CableRoute, view: ^GraphView) {
    for s in 0 ..< route.count {
        for k in 0 ..< 4 {
            route.segments[s].p[k] = GraphToScreen(view, route.segments[s].p[k])
        }
    }
}

// Draws the cables (every one that is in the view, through `draw_cable` of the style) and then the zip ties. A style's GRAPH proc calls this after its
// background, so the cables are above it and below the nodes (which are elements of their own).
GraphDrawLinks :: proc(ctx: ^Context, info: ^DrawInfo) {
    frame: ^GraphFrame = cast(^GraphFrame)info.user
    if frame == nil || frame.style.draw_cable == nil { return }
    graph, view, style := frame.graph, frame.view, &frame.style
    visible: Rect = {view.origin.x, view.origin.y, view.viewport.x, view.viewport.y}
    zoom: f32 = GraphViewZoom(view)
    it := hm.iterator_make(&graph.links)
    for link, handle in hm.iterate(&it) {
        route, ok := graphLinkRoute(graph, link, style)
        if !ok { continue }
        if !RectOverlaps(style.bounds(&route, style.cable_width), visible) { continue }      // the broad phase: only the cables that are in the view
        routeToScreen(&route, view)
        from, to: ^Port = GraphPort(graph, link.from), GraphPort(graph, link.to)
        draw: CableDraw = {route = &route, color = link.color if link.color.a > 0 else from.color, width = style.cable_width * zoom, link = handle, from_type = from.data_type, to_type = to.data_type, user = style.user, label = GraphLinkLabelText(link)}
        if view.hover_link == handle { draw.flags += {.HOVERED} }
        if view.selected_link == handle { draw.flags += {.SELECTED} }
        if view.pickup_link == handle { draw.flags += {.DISABLED} }
        style.draw_cable(ctx, &draw)
    }
    if style.draw_tie == nil { return }
    ties := hm.iterator_make(&graph.ties)
    for tie, handle in hm.iterate(&ties) {
        corners: [4]Vec2 = TieCorners(tie, style.tie_spacing, style.tie_width)
        low: Vec2 = {INFINITE, INFINITE}
        high: Vec2 = {-INFINITE, -INFINITE}
        for corner in corners {
            low = {min(low.x, corner.x), min(low.y, corner.y)}
            high = {max(high.x, corner.x), max(high.y, corner.y)}
        }
        if !RectOverlaps({low.x, low.y, high.x - low.x, high.y - low.y}, visible) { continue }
        tangent, normal := TieAxes(tie.angle)
        draw: TieDraw = {
            center = GraphToScreen(view, tie.position), tangent = tangent, normal = normal, half_length = TieHalfLength(tie, style.tie_spacing) * zoom, width = style.tie_width * zoom,
            color = tie.color, name = GraphTieName(tie), lanes = tie.member_count, user = style.user,
        }
        for k in 0 ..< 4 { draw.corners[k] = GraphToScreen(view, corners[k]) }
        if view.hover_tie == handle { draw.flags += {.HOVERED} }
        if view.selected_tie == handle { draw.flags += {.SELECTED} }
        style.draw_tie(ctx, &draw)
    }
}

// Draws what is above the nodes: the cable that is dragged (from the port it started at to the pointer, or to the pin it fits), and the cut of the tie tool.
GraphDrawOverlay :: proc(ctx: ^Context, info: ^DrawInfo) {
    frame: ^GraphFrame = cast(^GraphFrame)info.user
    if frame == nil || frame.style.draw_cable == nil { return }
    graph, view, style := frame.graph, frame.view, &frame.style
    if ctx.drag.active && ctx.drag.kind == IdFromString(GRAPH_CABLE_KIND) {
        if source := GraphPort(graph, view.drag_source); source != nil && source.anchor_known {
            end: Vec2 = ctx.input.mouse_position
            to_port: PortHandle
            if target := GraphPort(graph, view.drag_target); target != nil && target.anchor_known {
                end = GraphToScreen(view, target.anchor)
                to_port = view.drag_target
            }
            start: Vec2 = GraphToScreen(view, source.anchor)
            input: CableRouteInput = {from = start, to = end, dragging = true, from_port = view.drag_source, to_port = to_port, user = style.user}
            if source.kind == .INPUT { input.from, input.to = end, start }              // a cable that is dragged from an input flows into it
            route: CableRoute
            style.route_dragged(&input, &route)
            draw: CableDraw = {route = &route, color = source.color, width = style.cable_width * GraphViewZoom(view), flags = {.PRESSED}, dragging = true, from_type = source.data_type, user = style.user}
            style.draw_cable(ctx, &draw)
        }
    }
    if view.gesture == .BOX {
        a, b: Vec2 = GraphToScreen(view, view.cut_from), GraphToScreen(view, view.cut_to)
        corners: [4]Vec2 = {a, {b.x, a.y}, b, {a.x, b.y}}
        route: CableRoute = {count = 4}
        for i in 0 ..< 4 { route.segments[i] = lineSegment(corners[i], corners[(i + 1) % 4]) }
        draw: CableDraw = {route = &route, color = {120, 180, 255, 255}, width = 1.5, flags = {.PRESSED}, dragging = true, user = style.user}
        style.draw_cable(ctx, &draw)
    }
    if view.gesture == .CUT {
        input: CableRouteInput = {from = GraphToScreen(view, view.cut_from), to = GraphToScreen(view, view.cut_to), dragging = true, user = style.user}
        route: CableRoute
        CableRouteStraight(&input, &route)
        draw: CableDraw = {route = &route, color = {255, 90, 90, 255}, width = max(style.cable_width * 0.6, 1.5), flags = {.PRESSED}, dragging = true, user = style.user}
        style.draw_cable(ctx, &draw)
    }
}
