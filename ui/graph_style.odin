package ui

// What a style decides about a graph: how cables are routed (a connected cable and a cable that is being dragged can differ), the rectangle and the
// distance function that make cables cheap to cull and to click, how a cable and a zip tie are drawn, and the numbers of the layout. Everything has a
// default, so a style fills only what it wants to change; the drawing procs are the only ones a style must give (the library draws nothing itself).
//
//     style.graph.draw_cable = MyDrawCable                         // draws a CableDraw with the painter of the framework
//     style.graph.route_dragged = ui.CableRouteStraight            // a cable that is dragged is a straight line
//     style.graph.route_connected = MyRightAngledRoute             // connected cables turn at right angles (and give their own bounds and distance)
//     style.graph.pickup = .NEW                                    // dragging from a connected input makes a second cable instead of taking its cable

// Dragging from an input that has a cable.
PickupMode :: enum u8 {
    PICKUP,             // the cable is taken: its output end stays, the other end follows the pointer; let go over a port it connects there, over nothing it is removed
    NEW,                // a new cable starts at the input and the old one stays (an input that merges takes both)
}

// A cable to draw, in screen coordinates.
CableDraw :: struct {
    route: ^CableRoute,
    color: Color,               // of the link, else of the output port; alpha 0: the style's own
    width: f32,
    flags: Flags,               // HOVERED: the pointer is on it, SELECTED, PRESSED: it is the cable being dragged, DISABLED: its end was picked up (it is drawn faint)
    dragging: bool,
    link: LinkHandle,           // not valid for a cable that is being dragged
    from_type: u32,             // the data types of its ports (0 when only one end is known), for a style that draws a bus thicker than a signal
    to_type: u32,
    label: string,              // the text on the cable (GraphLinkLabel), empty for none: a style draws it where the cable is half way
    user: rawptr,               // `user` of the GraphStyle
}

// A zip tie to draw, in screen coordinates.
TieDraw :: struct {
    center: Vec2,
    corners: [4]Vec2,           // the strap, in order
    tangent: Vec2,              // the way the cables go through it
    normal: Vec2,               // across: the lanes are along it, the head (the end for the rotating handle) is at +normal
    half_length: f32,
    width: f32,
    color: Color,               // alpha 0: the style's own
    name: string,
    lanes: int,
    flags: Flags,               // HOVERED, SELECTED
    user: rawptr,
}

CableDrawProc :: proc(ctx: ^Context, cable: ^CableDraw)
TieDrawProc :: proc(ctx: ^Context, tie: ^TieDraw)

GraphStyle :: struct {
    route_connected: CableRouteProc,            // nil: CableRouteDefault
    route_dragged: CableRouteProc,              // nil: the same as route_connected
    bounds: CableBoundsProc,                    // nil: CableBoundsDefault
    distance: CableDistanceProc,                // nil: CableDistanceDefault
    draw_cable: CableDrawProc,
    draw_tie: TieDrawProc,
    pickup: PickupMode,
    cable_width: f32,                           // 0: 2.5
    hit_distance: f32,                          // how far from a cable the pointer still counts as on it: 0 is 8
    pin_size: f32,                              // the square a pin takes (the pin draws smaller inside of it, the whole square takes the pointer): 0 is 20
    node_width: f32,                            // the least width of a node: 0 is 190
    tie_spacing: f32,                           // between the lanes of a zip tie: 0 is 10
    tie_width: f32,                             // of the strap: 0 is 9
    snap: f32,                                  // nodes snap to a grid of this size when they are let go (0: no snapping)
    rotate_snap: f32,                           // a tie turns in steps of this many degrees: 0 is 15, a negative number turns freely
    grid: f32,                                  // the spacing of the background grid a style may draw: 0 is 24
    user: rawptr,                               // comes back in the route input and in what is drawn
}

GRAPH_CABLE_WIDTH :: f32(2.5)
GRAPH_HIT_DISTANCE :: f32(8)
GRAPH_PIN_SIZE :: f32(20)
GRAPH_NODE_WIDTH :: f32(190)
GRAPH_TIE_SPACING :: f32(10)
GRAPH_TIE_WIDTH :: f32(9)
GRAPH_ROTATE_SNAP :: f32(15)
GRAPH_GRID :: f32(24)

// The style with every empty place filled by the default.
GraphStyleResolved :: proc(style: ^Style) -> GraphStyle {
    result: GraphStyle = style.graph
    if result.route_connected == nil { result.route_connected = CableRouteDefault }
    if result.route_dragged == nil { result.route_dragged = result.route_connected }
    if result.bounds == nil { result.bounds = CableBoundsDefault }
    if result.distance == nil { result.distance = CableDistanceDefault }
    if result.cable_width <= 0 { result.cable_width = GRAPH_CABLE_WIDTH }
    if result.hit_distance <= 0 { result.hit_distance = GRAPH_HIT_DISTANCE }
    if result.pin_size <= 0 { result.pin_size = GRAPH_PIN_SIZE }
    if result.node_width <= 0 { result.node_width = GRAPH_NODE_WIDTH }
    if result.tie_spacing <= 0 { result.tie_spacing = GRAPH_TIE_SPACING }
    if result.tie_width <= 0 { result.tie_width = GRAPH_TIE_WIDTH }
    if result.rotate_snap == 0 { result.rotate_snap = GRAPH_ROTATE_SNAP }
    if result.grid <= 0 { result.grid = GRAPH_GRID }
    return result
}
