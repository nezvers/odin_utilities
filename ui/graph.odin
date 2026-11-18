package ui

// The model of a node graph: nodes with ports, links between ports, zip ties that bundle links into ribbons, the rules that say what may be connected,
// and the news of every change. It knows nothing of drawing: the widgets in graph_widgets.odin draw it and change it with the pointer, a program (an audio
// engine, a shader editor) reads it. Everything is fixed storage in the Graph (sizes are `#config`, a link costs ~100 bytes), handles are checked
// (a handle of something that is gone is refused, never another thing), and nothing allocates.
//
//   graph: ui.Graph                                    // big: a global or a heap allocation
//   ui.GraphInit(&graph)
//   osc, _ := ui.GraphNodeAdd(&graph, "Oscillator", {40, 40})
//   out, _ := ui.GraphPortAdd(&graph, osc, "out", .OUTPUT, data_type = 1)
//   gain, _ := ui.GraphNodeAdd(&graph, "Gain", {260, 60})
//   in, _ := ui.GraphPortAdd(&graph, gain, "in", .INPUT, data_type = 1)
//   link, result := ui.GraphConnect(&graph, out, in)  // the rules decide (GraphCanConnect says why not)
//   for { event := ui.GraphPollEvent(&graph) or_break; ... }            // or graph.on_event, with the context of the program
//
// For a program that moves data along the links (audio buffers, parameters) the graph is built to be read, not just drawn: a port keeps the list of its links
// (fan out from an output is any number of links, fan in to an input with the MERGE flag is any number), `GraphOrder` gives the order in which to run
// the nodes, and `GraphCompile` turns the graph into a flat plan of steps with the buffer every port reads and writes, buffers reused as soon as their
// last reader has run. The plan is plain data: the thread that runs it can keep its own copy while the user edits the graph.

import hm "core:container/handle_map"

GRAPH_NODES :: #config(GRAPH_NODES, 256)
GRAPH_PORTS :: #config(GRAPH_PORTS, 2048)
GRAPH_LINKS :: #config(GRAPH_LINKS, 4096)
GRAPH_TIES :: #config(GRAPH_TIES, 512)
GRAPH_EVENTS :: #config(GRAPH_EVENTS, 256)
GRAPH_NAME_MAX :: 48
GRAPH_TIE_MEMBERS :: 16         // links in one zip tie
GRAPH_LINK_TIES :: 4            // zip ties one link passes through

NodeHandle :: distinct hm.Handle32
PortHandle :: distinct hm.Handle32
LinkHandle :: distinct hm.Handle32
TieHandle :: distinct hm.Handle32

PortKind :: enum u8 {
    INPUT,
    OUTPUT,
}

PortFlag :: enum u8 {
    MERGE,              // an input that takes any number of links (their data is merged, summed or mixed by the program); without it an input takes one
    SINGLE,             // an output that takes one link only (without it an output splits to any number)
    HIDDEN,             // not drawn and not connected by the pointer, the program may still link it
}
PortFlags :: bit_set[PortFlag; u8]

Port :: struct {
    handle: PortHandle,
    node: NodeHandle,
    kind: PortKind,
    flags: PortFlags,
    data_type: u32,             // what flows through it: ports connect when their types are compatible (0 is any, see GraphRules)
    name: [GRAPH_NAME_MAX]u8,
    name_length: int,
    color: Color,               // of the pin and of the cables that start here, alpha 0 for the style's own
    user: rawptr,               // of the program: it comes back in the events (a channel, a parameter, a buffer)
    index: int,                 // among the ports of its node, in the order they were added
    first_link: LinkHandle,     // the links of this port (as source for an output, as target for an input), in the order they were made
    last_link: LinkHandle,
    link_count: int,
    next_in_node: PortHandle,
    anchor: Vec2,               // where the pin is, in canvas coordinates (the widgets keep it up to date)
    anchor_known: bool,
    offset: Vec2,               // where the pin is from the position of its node: it keeps the anchor right when the node moves while it is not on screen
    element: i32,               // the element of the last frame (graph_widgets.odin)
    stamp: u32,
    buffer: u32,                // GraphCompile: the buffer an output writes
    remaining: u32,
}

Node :: struct {
    handle: NodeHandle,
    name: [GRAPH_NAME_MAX]u8,
    name_length: int,
    position: Vec2,             // canvas coordinates of the top left corner
    size: Vec2,                 // as it was drawn in the last frame
    color: Color,               // the accent of the title, alpha 0 for the style's own
    user: rawptr,
    first_port: PortHandle,
    last_port: PortHandle,
    port_count: int,
    z: i16,                     // drawn after the nodes with a lower number (GraphNodeRaise)
    selected: bool,
    collapsed: bool,            // only the title is drawn; its cables go to the edges of the title (a double click on the title, GraphNodeCollapse)
    reroute: bool,              // a point on a cable (GraphRerouteAdd): one input and one output, drawn as a small dot; a program passes the data straight through it
    element: i32,
    stamp: u32,
    degree: u32,                // scratch of GraphOrder
    visit: u32,                 // scratch of the cycle search
}

Link :: struct {
    handle: LinkHandle,
    from: PortHandle,           // an output
    to: PortHandle,             // an input
    prev_from, next_from: LinkHandle,   // the list of the output port
    prev_to, next_to: LinkHandle,       // the list of the input port
    color: Color,               // alpha 0: the color of the output port, else the style's own
    user: rawptr,
    ties: [GRAPH_LINK_TIES]TieHandle,   // the zip ties it passes through, in the order along the link (GraphTieOrderLinks)
    tie_count: int,
    label: [GRAPH_NAME_MAX]u8,          // a text on the cable (GraphLinkLabel): what flows there
    label_length: int,
}

// A zip tie: a strap that gathers several links into a ribbon. The links go through it side by side, in the order of `members`, each in its own lane,
// all in the direction of `angle`, and come apart again after it. The idea (a strap across the wires, a lane for every wire, ties that can be moved and
// turned, a tie that holds a piece of a wire) is the one of comfyui-zip-ties and of Zip ties for Blender.
Tie :: struct {
    handle: TieHandle,
    position: Vec2,             // canvas coordinates of the middle of the strap
    angle: f32,                 // the direction of the links through it (radians, 0 is along +x)
    scale: f32,                 // of the length of the strap and of the lanes (1 is the style's)
    color: Color,
    name: [GRAPH_NAME_MAX]u8,
    name_length: int,
    members: [GRAPH_TIE_MEMBERS]LinkHandle,
    member_count: int,
}

// ------------------------------------------------------------------------------------------------------------------------
// What may be connected

ConnectResult :: enum u8 {
    OK,
    REPLACES,           // it may, and the link that the single input has now goes away
    INVALID,            // a port that is not there
    SAME_NODE,          // an output and an input of one node
    SAME_KIND,          // two outputs or two inputs
    TYPE,               // the data types do not fit
    DUPLICATE,          // these two are linked already
    FULL,               // an input without MERGE or an output with SINGLE that has its link, and the rules refuse to replace it
    CYCLE,              // it would make a loop (feedback), which the rules do not allow
}

ConnectOk :: proc(result: ConnectResult) -> bool {
    return result == .OK || result == .REPLACES
}

// What the program decides. A nil proc is the default: DefaultCanConnect. A proc of the program can call the default and add to it (a node that takes
// only its own kind, a limit of connections...). `types_fit` says when two data types connect (nil: equal, or one of them is 0).
GraphRules :: struct {
    can_connect: proc(graph: ^Graph, from: ^Port, to: ^Port, user: rawptr) -> ConnectResult,
    types_fit: proc(from_type: u32, to_type: u32, user: rawptr) -> bool,
    refuse_when_full: bool,         // a second link into a single input is refused (FULL) instead of replacing the first
    allow_cycles: bool,             // feedback: a link that closes a loop is fine
    user: rawptr,
}

// ------------------------------------------------------------------------------------------------------------------------
// News

GraphEventKind :: enum u8 {
    NONE,
    CONNECTED,          // a link was made: from / to
    DISCONNECTED,       // a link is gone: why is in `reason`
    NODE_ADDED,
    NODE_REMOVED,
    NODE_MOVED,         // the node was dragged and let go (`position` is where it is now)
    TIE_ADDED,
    TIE_REMOVED,
    TIE_CHANGED,        // moved, turned or scaled and let go
    NODE_COLLAPSED,     // a node was collapsed or opened: `node`, `collapsed`
    LINK_LABELED,       // the text on a cable changed: `link`
    DROPPED_ON_EMPTY,   // a cable that was dragged from a port was let go over empty room at `position` (canvas coordinates): a program may offer a node to put there
}

DisconnectReason :: enum u8 {
    REQUEST,            // the program (or the user, with the delete key) asked
    REPLACED,           // another link took the single input
    PICKED_UP,          // the end of a connected cable was dragged off, and let go over nothing
    MOVED,              // the end of a connected cable was dragged to another port (a DISCONNECTED and then a CONNECTED)
    NODE_REMOVED,
}

// Everything the program may want to know about a change, with its own pointers (the `user` of the graph, of the ports and of the nodes) so a handler needs no
// lookup. After a disconnect the link handle is not valid any more, the rest is a copy.
GraphEvent :: struct {
    kind: GraphEventKind,
    reason: DisconnectReason,
    link: LinkHandle,
    from: PortHandle,
    to: PortHandle,
    from_node: NodeHandle,
    to_node: NodeHandle,
    from_user: rawptr,          // `user` of the output port, of the input port, of their nodes, and of the graph
    to_user: rawptr,
    from_node_user: rawptr,
    to_node_user: rawptr,
    graph_user: rawptr,
    node: NodeHandle,           // NODE_*
    collapsed: bool,            // NODE_COLLAPSED: the state now
    copied_from: NodeHandle,    // NODE_ADDED by a paste: the node it is a copy of (it may be gone): a program that keeps data for a node makes its own copy of it now
    tie: TieHandle,             // TIE_*
    position: Vec2,
}

GraphEventProc :: proc(graph: ^Graph, event: ^GraphEvent)

// ------------------------------------------------------------------------------------------------------------------------

Graph :: struct {
    nodes: hm.Static_Handle_Map(GRAPH_NODES, Node, NodeHandle),
    ports: hm.Static_Handle_Map(GRAPH_PORTS, Port, PortHandle),
    links: hm.Static_Handle_Map(GRAPH_LINKS, Link, LinkHandle),
    ties: hm.Static_Handle_Map(GRAPH_TIES, Tie, TieHandle),
    rules: GraphRules,
    user: rawptr,                           // comes back in the events
    on_event: GraphEventProc,               // called when something happens (the events are also queued for GraphPollEvent)
    events: [GRAPH_EVENTS]GraphEvent,
    event_head: int,
    event_count: int,
    events_lost: int,                       // the oldest events that were thrown away because nobody polled
    z_counter: i16,
    stamp: u32,                             // numbers the visits of the searches
    frame: u32,                             // numbers the frames of the widgets
}

// An empty graph. `user` comes back in every event.
GraphInit :: proc(graph: ^Graph, user: rawptr = nil) {
    graph^ = {}
    graph.user = user
}

@(private)
setName :: proc(buffer: []u8, length: ^int, text: string) {
    length^ = min(len(text), len(buffer))
    copy(buffer[:length^], text)
}

GraphNodeName :: proc(node: ^Node) -> string {
    return string(node.name[:node.name_length])
}

GraphPortName :: proc(port: ^Port) -> string {
    return string(port.name[:port.name_length])
}

GraphTieName :: proc(tie: ^Tie) -> string {
    return string(tie.name[:tie.name_length])
}

// The thing behind a handle, nil when the handle is not valid (the thing was removed, or never was).
GraphNode :: proc(graph: ^Graph, handle: NodeHandle) -> ^Node {
    if handle == {} { return nil }
    item, ok := hm.get(&graph.nodes, handle)
    return item if ok else nil
}

GraphPort :: proc(graph: ^Graph, handle: PortHandle) -> ^Port {
    if handle == {} { return nil }
    item, ok := hm.get(&graph.ports, handle)
    return item if ok else nil
}

GraphLink :: proc(graph: ^Graph, handle: LinkHandle) -> ^Link {
    if handle == {} { return nil }
    item, ok := hm.get(&graph.links, handle)
    return item if ok else nil
}

GraphTie :: proc(graph: ^Graph, handle: TieHandle) -> ^Tie {
    if handle == {} { return nil }
    item, ok := hm.get(&graph.ties, handle)
    return item if ok else nil
}

GraphNodeCount :: proc(graph: ^Graph) -> int {
    return int(hm.len(graph.nodes))
}

GraphLinkCount :: proc(graph: ^Graph) -> int {
    return int(hm.len(graph.links))
}

GraphTieCount :: proc(graph: ^Graph) -> int {
    return int(hm.len(graph.ties))
}

// ------------------------------------------------------------------------------------------------------------------------
// Events

@(private)
graphEmit :: proc(graph: ^Graph, event: GraphEvent) {
    stored: GraphEvent = event
    stored.graph_user = graph.user
    if graph.event_count == len(graph.events) {
        graph.event_head = (graph.event_head + 1) % len(graph.events)          // nobody polls: the oldest goes
        graph.event_count -= 1
        graph.events_lost += 1
    }
    graph.events[(graph.event_head + graph.event_count) % len(graph.events)] = stored
    graph.event_count += 1
    if graph.on_event != nil {
        graph.on_event(graph, &stored)
    }
}

// The oldest event that was not read yet. Read them all every frame (or not at all and use `on_event`).
GraphPollEvent :: proc(graph: ^Graph) -> (event: GraphEvent, ok: bool) {
    if graph.event_count == 0 { return }
    event = graph.events[graph.event_head]
    graph.event_head = (graph.event_head + 1) % len(graph.events)
    graph.event_count -= 1
    return event, true
}

// The event of a link: both ends with their own pointers.
@(private)
linkEvent :: proc(graph: ^Graph, kind: GraphEventKind, link: ^Link) -> GraphEvent {
    event: GraphEvent = {kind = kind, link = link.handle, from = link.from, to = link.to}
    if from := GraphPort(graph, link.from); from != nil {
        event.from_user = from.user
        event.from_node = from.node
        if node := GraphNode(graph, from.node); node != nil { event.from_node_user = node.user }
    }
    if to := GraphPort(graph, link.to); to != nil {
        event.to_user = to.user
        event.to_node = to.node
        if node := GraphNode(graph, to.node); node != nil { event.to_node_user = node.user }
    }
    return event
}

// ------------------------------------------------------------------------------------------------------------------------
// Nodes and ports

// A node at `position` (canvas coordinates). False when the graph has no room.
GraphNodeAdd :: proc(graph: ^Graph, name: string, position: Vec2, user: rawptr = nil, color: Color = {}) -> (handle: NodeHandle, ok: bool) {
    return graphNodeAdd(graph, name, position, user, color, {})
}

@(private)
graphNodeAdd :: proc(graph: ^Graph, name: string, position: Vec2, user: rawptr, color: Color, copied_from: NodeHandle) -> (handle: NodeHandle, ok: bool) {
    node: Node = {position = position, user = user, color = color, element = -1}
    setName(node.name[:], &node.name_length, name)
    graph.z_counter += 1
    node.z = graph.z_counter
    handle, ok = hm.add(&graph.nodes, node)
    if !ok { return }
    graphEmit(graph, {kind = .NODE_ADDED, node = handle, position = position, copied_from = copied_from})
    return
}

// Brings the node in front of the others.
GraphNodeRaise :: proc(graph: ^Graph, handle: NodeHandle) {
    node: ^Node = GraphNode(graph, handle)
    if node == nil || node.z == graph.z_counter { return }
    if graph.z_counter >= 32000 {
        // the numbers are used up: every node gets the number of the nodes below it, plus one (a stable renumbering, rare, quadratic is fine)
        total: i16
        it := hm.iterator_make(&graph.nodes)
        for current, _ in hm.iterate(&it) {
            below: i16
            inner := hm.iterator_make(&graph.nodes)
            for other, _ in hm.iterate(&inner) {
                if other.z < current.z || other.z == current.z && other.handle.idx < current.handle.idx { below += 1 }
            }
            current.degree = u32(below + 1)
            total += 1
        }
        it = hm.iterator_make(&graph.nodes)
        for current, _ in hm.iterate(&it) {
            current.z = i16(current.degree)
        }
        graph.z_counter = total
    }
    graph.z_counter += 1
    node.z = graph.z_counter
}

// A port at the end of the node's list (the order they are shown in). False when the node is not there or the graph has no room.
GraphPortAdd :: proc(graph: ^Graph, node_handle: NodeHandle, name: string, kind: PortKind, data_type: u32 = 0, flags: PortFlags = {}, user: rawptr = nil, color: Color = {}) -> (handle: PortHandle, ok: bool) {
    node: ^Node = GraphNode(graph, node_handle)
    if node == nil { return {}, false }
    port: Port = {node = node_handle, kind = kind, flags = flags, data_type = data_type, user = user, color = color, index = node.port_count, element = -1}
    setName(port.name[:], &port.name_length, name)
    handle, ok = hm.add(&graph.ports, port)
    if !ok { return }
    node = GraphNode(graph, node_handle)
    if node.last_port != {} {
        GraphPort(graph, node.last_port).next_in_node = handle
    } else {
        node.first_port = handle
    }
    node.last_port = handle
    node.port_count += 1
    return
}

// Removes a node: its links go first (each one is a DISCONNECTED event), then its ports.
GraphNodeRemove :: proc(graph: ^Graph, handle: NodeHandle) -> bool {
    node: ^Node = GraphNode(graph, handle)
    if node == nil { return false }
    port_handle: PortHandle = node.first_port
    for port_handle != {} {
        port: ^Port = GraphPort(graph, port_handle)
        for port.first_link != {} {
            GraphDisconnect(graph, port.first_link, .NODE_REMOVED)
            port = GraphPort(graph, port_handle)
        }
        next: PortHandle = port.next_in_node
        hm.remove(&graph.ports, port_handle)
        port_handle = next
    }
    graphEmit(graph, {kind = .NODE_REMOVED, node = handle})
    hm.remove(&graph.nodes, handle)
    return true
}

// ------------------------------------------------------------------------------------------------------------------------
// Links

// The links of a port, in the order they were made.
GraphPortFirstLink :: proc(graph: ^Graph, port: PortHandle) -> LinkHandle {
    item: ^Port = GraphPort(graph, port)
    return item.first_link if item != nil else {}
}

// The link after `link` in the list of `port` (the one whose list it is: a link is in the list of its output and in the list of its input).
GraphLinkNext :: proc(graph: ^Graph, link: LinkHandle, port: PortHandle) -> LinkHandle {
    item: ^Link = GraphLink(graph, link)
    if item == nil { return {} }
    return item.next_from if item.from == port else item.next_to
}

// The port on the other end of a link.
GraphLinkOther :: proc(graph: ^Graph, link: LinkHandle, port: PortHandle) -> PortHandle {
    item: ^Link = GraphLink(graph, link)
    if item == nil { return {} }
    return item.to if item.from == port else item.from
}

// Does a path of links lead from `from` to `to`? (The cycle test of GraphCanConnect: a depth first search with a stack in the stack of the call, no allocation.)
GraphReaches :: proc(graph: ^Graph, from: NodeHandle, to: NodeHandle) -> bool {
    if from == to { return true }
    graph.stamp += 1
    stack: [GRAPH_NODES]NodeHandle
    top: int
    stack[0] = from
    top = 1
    GraphNode(graph, from).visit = graph.stamp
    for top > 0 {
        top -= 1
        node: ^Node = GraphNode(graph, stack[top])
        port_handle: PortHandle = node.first_port
        for port_handle != {} {
            port: ^Port = GraphPort(graph, port_handle)
            if port.kind == .OUTPUT {
                link_handle: LinkHandle = port.first_link
                for link_handle != {} {
                    link: ^Link = GraphLink(graph, link_handle)
                    target: ^Port = GraphPort(graph, link.to)
                    if target.node == to { return true }
                    next: ^Node = GraphNode(graph, target.node)
                    if next.visit != graph.stamp && top < len(stack) {
                        next.visit = graph.stamp
                        stack[top] = target.node
                        top += 1
                    }
                    link_handle = link.next_from
                }
            }
            port_handle = port.next_in_node
        }
    }
    return false
}

// May these two ports be connected? Either order: the output and the input are found. `from` and `to` of the rules are the output and the input.
GraphCanConnect :: proc(graph: ^Graph, a: PortHandle, b: PortHandle) -> ConnectResult {
    first, second: ^Port = GraphPort(graph, a), GraphPort(graph, b)
    if first == nil || second == nil { return .INVALID }
    if first.kind == second.kind { return .SAME_KIND }
    output, input: ^Port = first, second
    if first.kind == .INPUT { output, input = second, first }
    if graph.rules.can_connect != nil {
        return graph.rules.can_connect(graph, output, input, graph.rules.user)
    }
    return DefaultCanConnect(graph, output, input)
}

// The rules when the program gives none: an output to an input of another node, data types that fit, not twice, an input takes one link (a second
// replaces it, or is refused with `refuse_when_full`) unless it merges, an output with SINGLE takes one, and no loops unless `allow_cycles`.
DefaultCanConnect :: proc(graph: ^Graph, output: ^Port, input: ^Port) -> ConnectResult {
    if output.node == input.node { return .SAME_NODE }
    fits: bool
    if graph.rules.types_fit != nil {
        fits = graph.rules.types_fit(output.data_type, input.data_type, graph.rules.user)
    } else {
        fits = output.data_type == input.data_type || output.data_type == 0 || input.data_type == 0
    }
    if !fits { return .TYPE }
    link_handle: LinkHandle = output.first_link
    for link_handle != {} {
        link: ^Link = GraphLink(graph, link_handle)
        if link.to == input.handle { return .DUPLICATE }
        link_handle = link.next_from
    }
    if .SINGLE in output.flags && output.link_count > 0 { return .FULL }
    replaces: bool
    if .MERGE not_in input.flags && input.link_count > 0 {
        if graph.rules.refuse_when_full { return .FULL }
        replaces = true
    }
    if !graph.rules.allow_cycles && GraphReaches(graph, input.node, output.node) { return .CYCLE }
    return .REPLACES if replaces else .OK
}

// Connects two ports (either order). The link, and what the rules said; without a link nothing was changed. A single input that had a link loses it (a
// DISCONNECTED event with the reason REPLACED comes before the CONNECTED).
GraphConnect :: proc(graph: ^Graph, a: PortHandle, b: PortHandle, user: rawptr = nil) -> (handle: LinkHandle, result: ConnectResult) {
    result = GraphCanConnect(graph, a, b)
    if !ConnectOk(result) { return }
    first: ^Port = GraphPort(graph, a)
    output, input: PortHandle = a, b
    if first.kind == .INPUT { output, input = b, a }
    if result == .REPLACES {
        for GraphPort(graph, input).link_count > 0 {
            GraphDisconnect(graph, GraphPort(graph, input).first_link, .REPLACED)
        }
    }
    ok: bool
    handle, ok = hm.add(&graph.links, Link{from = output, to = input, user = user})
    if !ok { return {}, .FULL }
    link: ^Link = GraphLink(graph, handle)
    // the end of the list of the output port, and of the input port
    out_port: ^Port = GraphPort(graph, output)
    if out_port.last_link != {} {
        previous: ^Link = GraphLink(graph, out_port.last_link)
        previous.next_from = handle
        link.prev_from = out_port.last_link
    } else {
        out_port.first_link = handle
    }
    out_port.last_link = handle
    out_port.link_count += 1
    in_port: ^Port = GraphPort(graph, input)
    if in_port.last_link != {} {
        previous: ^Link = GraphLink(graph, in_port.last_link)
        previous.next_to = handle
        link.prev_to = in_port.last_link
    } else {
        in_port.first_link = handle
    }
    in_port.last_link = handle
    in_port.link_count += 1
    graphEmit(graph, linkEvent(graph, .CONNECTED, link))
    return handle, result if result == .REPLACES else .OK
}

// Removes a link (a DISCONNECTED event). The zip ties that held it let it go, and a tie that holds nothing any more goes too.
GraphDisconnect :: proc(graph: ^Graph, handle: LinkHandle, reason: DisconnectReason = .REQUEST) -> bool {
    link: ^Link = GraphLink(graph, handle)
    if link == nil { return false }
    event: GraphEvent = linkEvent(graph, .DISCONNECTED, link)
    event.reason = reason
    graphTiesLetGo(graph, link)
    out_port: ^Port = GraphPort(graph, link.from)
    if link.prev_from != {} {
        GraphLink(graph, link.prev_from).next_from = link.next_from
    } else {
        out_port.first_link = link.next_from
    }
    if link.next_from != {} {
        GraphLink(graph, link.next_from).prev_from = link.prev_from
    } else {
        out_port.last_link = link.prev_from
    }
    out_port.link_count -= 1
    in_port: ^Port = GraphPort(graph, link.to)
    if link.prev_to != {} {
        GraphLink(graph, link.prev_to).next_to = link.next_to
    } else {
        in_port.first_link = link.next_to
    }
    if link.next_to != {} {
        GraphLink(graph, link.next_to).prev_to = link.prev_to
    } else {
        in_port.last_link = link.prev_to
    }
    in_port.link_count -= 1
    hm.remove(&graph.links, handle)
    event.link = {}                                                 // the handle is not valid any more: the event carries the rest
    graphEmit(graph, event)
    return true
}

// ------------------------------------------------------------------------------------------------------------------------
// Zip ties

// A tie across `links` at `position`, pointing `angle`. The lanes are in the order of `links`, unless all of them are in a tie already: then they keep that
// tie's order, so the strands never cross inside the ribbon. Links that already pass through GRAPH_LINK_TIES ties are left out. False when no link
// remains or the graph has no room.
GraphTieAdd :: proc(graph: ^Graph, position: Vec2, angle: f32, links: []LinkHandle, color: Color = {}) -> (handle: TieHandle, ok: bool) {
    tie: Tie = {position = position, angle = angle, scale = 1, color = color}
    for link_handle in links {
        link: ^Link = GraphLink(graph, link_handle)
        if link == nil || link.tie_count >= GRAPH_LINK_TIES || tie.member_count >= GRAPH_TIE_MEMBERS { continue }
        duplicate: bool
        for i in 0 ..< tie.member_count {
            if tie.members[i] == link_handle { duplicate = true }
        }
        if duplicate { continue }
        tie.members[tie.member_count] = link_handle
        tie.member_count += 1
    }
    if tie.member_count == 0 { return {}, false }
    graphTieKeepOrder(graph, &tie)
    handle, ok = hm.add(&graph.ties, tie)
    if !ok { return }
    stored: ^Tie = GraphTie(graph, handle)
    for i in 0 ..< stored.member_count {
        link: ^Link = GraphLink(graph, stored.members[i])
        link.ties[link.tie_count] = handle
        link.tie_count += 1
    }
    for i in 0 ..< stored.member_count {
        GraphTieOrderLink(graph, stored.members[i])
    }
    graphEmit(graph, {kind = .TIE_ADDED, tie = handle, position = position})
    return
}

// When every link of a new tie is in one tie already, its lanes follow the order of that tie.
@(private)
graphTieKeepOrder :: proc(graph: ^Graph, tie: ^Tie) {
    first: ^Link = GraphLink(graph, tie.members[0])
    for i in 0 ..< first.tie_count {
        twin: ^Tie = GraphTie(graph, first.ties[i])
        if twin == nil { continue }
        all: bool = true
        for m in 0 ..< tie.member_count {
            found: bool
            for t in 0 ..< twin.member_count {
                if twin.members[t] == tie.members[m] { found = true }
            }
            if !found { all = false }
        }
        if !all { continue }
        // a stable sort by the place in the twin (the lists are short: an insertion sort)
        place :: proc(twin: ^Tie, link: LinkHandle) -> int {
            for t in 0 ..< twin.member_count {
                if twin.members[t] == link { return t }
            }
            return 0
        }
        for m in 1 ..< tie.member_count {
            current: LinkHandle = tie.members[m]
            key: int = place(twin, current)
            j: int = m - 1
            for j >= 0 && place(twin, tie.members[j]) > key {
                tie.members[j + 1] = tie.members[j]
                j -= 1
            }
            tie.members[j + 1] = current
        }
        return
    }
}

// Orders the ties of a link along the link, from its output to its input, by where they sit between the two pins. Needs the anchors of the pins.
GraphTieOrderLink :: proc(graph: ^Graph, handle: LinkHandle) {
    link: ^Link = GraphLink(graph, handle)
    if link == nil || link.tie_count < 2 { return }
    from, to: ^Port = GraphPort(graph, link.from), GraphPort(graph, link.to)
    if !from.anchor_known || !to.anchor_known { return }
    axis: Vec2 = to.anchor - from.anchor
    length: f32 = axis.x * axis.x + axis.y * axis.y
    if length < 1e-6 { return }
    along :: proc(graph: ^Graph, tie: TieHandle, origin: Vec2, axis: Vec2) -> f32 {
        item: ^Tie = GraphTie(graph, tie)
        if item == nil { return 0 }
        delta: Vec2 = item.position - origin
        return delta.x * axis.x + delta.y * axis.y
    }
    for i in 1 ..< link.tie_count {
        current: TieHandle = link.ties[i]
        key: f32 = along(graph, current, from.anchor, axis)
        j: int = i - 1
        for j >= 0 && along(graph, link.ties[j], from.anchor, axis) > key {
            link.ties[j + 1] = link.ties[j]
            j -= 1
        }
        link.ties[j + 1] = current
    }
}

// The same for every link of a tie (after the tie was moved).
GraphTieOrderLinks :: proc(graph: ^Graph, handle: TieHandle) {
    tie: ^Tie = GraphTie(graph, handle)
    if tie == nil { return }
    for i in 0 ..< tie.member_count {
        GraphTieOrderLink(graph, tie.members[i])
    }
}

// Removes a tie: its links go straight again.
GraphTieRemove :: proc(graph: ^Graph, handle: TieHandle) -> bool {
    tie: ^Tie = GraphTie(graph, handle)
    if tie == nil { return false }
    for i in 0 ..< tie.member_count {
        link: ^Link = GraphLink(graph, tie.members[i])
        if link == nil { continue }
        for t in 0 ..< link.tie_count {
            if link.ties[t] == handle {
                for k in t ..< link.tie_count - 1 { link.ties[k] = link.ties[k + 1] }
                link.tie_count -= 1
                break
            }
        }
    }
    graphEmit(graph, {kind = .TIE_REMOVED, tie = handle, position = tie.position})
    hm.remove(&graph.ties, handle)
    return true
}

// A link is going: every tie that held it lets it go, and a tie with nothing left goes too.
@(private)
graphTiesLetGo :: proc(graph: ^Graph, link: ^Link) {
    for link.tie_count > 0 {
        tie_handle: TieHandle = link.ties[link.tie_count - 1]
        link.tie_count -= 1
        tie: ^Tie = GraphTie(graph, tie_handle)
        if tie == nil { continue }
        for m in 0 ..< tie.member_count {
            if tie.members[m] == link.handle {
                for k in m ..< tie.member_count - 1 { tie.members[k] = tie.members[k + 1] }
                tie.member_count -= 1
                break
            }
        }
        if tie.member_count == 0 {
            graphEmit(graph, {kind = .TIE_REMOVED, tie = tie_handle, position = tie.position})
            hm.remove(&graph.ties, tie_handle)
        }
    }
}

// The lane of a link in a tie, 0 .. member_count - 1 (-1 when the link is not in the tie).
GraphTieLane :: proc(graph: ^Graph, tie_handle: TieHandle, link: LinkHandle) -> int {
    tie: ^Tie = GraphTie(graph, tie_handle)
    if tie == nil { return -1 }
    for i in 0 ..< tie.member_count {
        if tie.members[i] == link { return i }
    }
    return -1
}

// ------------------------------------------------------------------------------------------------------------------------
// For the program that runs the graph

OrderResult :: enum u8 {
    OK,
    CYCLE,              // the nodes that could be ordered are in `order`, the rest is in a loop
    SMALL,              // `order` is smaller than the number of nodes
}

// The nodes in an order in which every node comes after the nodes that feed it (a topological order), writing into `order`. Nodes that do not depend on
// each other come in the order they were added, so the result is the same from run to run. Returns how many were ordered.
GraphOrder :: proc(graph: ^Graph, order: []NodeHandle) -> (count: int, result: OrderResult) {
    total: int = GraphNodeCount(graph)
    if len(order) < total { return 0, .SMALL }
    it := hm.iterator_make(&graph.nodes)
    for node, _ in hm.iterate(&it) {
        node.degree = 0
        port_handle: PortHandle = node.first_port
        for port_handle != {} {
            port: ^Port = GraphPort(graph, port_handle)
            if port.kind == .INPUT { node.degree += u32(port.link_count) }
            port_handle = port.next_in_node
        }
    }
    it = hm.iterator_make(&graph.nodes)
    for node, handle in hm.iterate(&it) {
        if node.degree == 0 {
            order[count] = handle
            count += 1
        }
    }
    head: int
    for head < count {
        node: ^Node = GraphNode(graph, order[head])
        head += 1
        port_handle: PortHandle = node.first_port
        for port_handle != {} {
            port: ^Port = GraphPort(graph, port_handle)
            if port.kind == .OUTPUT {
                link_handle: LinkHandle = port.first_link
                for link_handle != {} {
                    link: ^Link = GraphLink(graph, link_handle)
                    target: ^Node = GraphNode(graph, GraphPort(graph, link.to).node)
                    target.degree -= 1
                    if target.degree == 0 {
                        order[count] = target.handle
                        count += 1
                    }
                    link_handle = link.next_from
                }
            }
            port_handle = port.next_in_node
        }
    }
    return count, .OK if count == total else .CYCLE
}

// One node of a plan: what to read, what to write, in the order of the plan. Its bindings are `bindings[first : first + inputs + outputs]`: the inputs
// first (one binding per link that feeds an input port, the links of a merging input follow each other: sum them), then the outputs (one per output port).
GraphStep :: struct {
    node: NodeHandle,
    first: u32,
    inputs: u16,
    outputs: u16,
}

GraphBinding :: struct {
    port: PortHandle,
    buffer: u32,            // the buffer to read (an input: the one its source writes) or to write (an output)
    link: LinkHandle,       // an input: the link it comes from (invalid for an output)
}

GraphPlan :: struct {
    steps: int,
    bindings: int,
    buffers: int,           // how many buffers the whole graph needs at once
}

PlanResult :: enum u8 {
    OK,
    CYCLE,
    STEPS_FULL,
    BINDINGS_FULL,
}

// The graph as a flat plan for the program that runs it: the nodes in order, and for every port the buffer it reads or writes. An output writes one buffer, read by
// every link that leaves it (a split costs nothing); a buffer is free again after the last node that reads it has run, and the next output takes it, so a long
// chain needs two or three buffers, not one per port. An output nobody reads still gets a buffer for its step (a node writes somewhere), freed at once. The
// engine copies the plan and runs it on its own thread while the graph goes on being edited. Writing into `steps` and `bindings`, nothing is allocated.
GraphCompile :: proc(graph: ^Graph, steps: []GraphStep, bindings: []GraphBinding) -> (plan: GraphPlan, result: PlanResult) {
    order: [GRAPH_NODES]NodeHandle
    count, order_result := GraphOrder(graph, order[:])
    if order_result != .OK { return {}, .CYCLE }
    if count > len(steps) { return {}, .STEPS_FULL }
    free: [GRAPH_PORTS]u32
    free_count: int
    next_buffer: u32
    for index in 0 ..< count {
        node: ^Node = GraphNode(graph, order[index])
        step: GraphStep = {node = order[index], first = u32(plan.bindings)}
        // the inputs read the buffers that their sources write
        port_handle: PortHandle = node.first_port
        for port_handle != {} {
            port: ^Port = GraphPort(graph, port_handle)
            if port.kind == .INPUT {
                link_handle: LinkHandle = port.first_link
                for link_handle != {} {
                    link: ^Link = GraphLink(graph, link_handle)
                    if plan.bindings >= len(bindings) { return {}, .BINDINGS_FULL }
                    bindings[plan.bindings] = {port = port_handle, buffer = GraphPort(graph, link.from).buffer, link = link_handle}
                    plan.bindings += 1
                    step.inputs += 1
                    link_handle = link.next_to
                }
            }
            port_handle = port.next_in_node
        }
        // the outputs take free buffers (or new ones)
        port_handle = node.first_port
        for port_handle != {} {
            port: ^Port = GraphPort(graph, port_handle)
            if port.kind == .OUTPUT {
                if plan.bindings >= len(bindings) { return {}, .BINDINGS_FULL }
                if free_count > 0 {
                    free_count -= 1
                    port.buffer = free[free_count]
                } else {
                    port.buffer = next_buffer
                    next_buffer += 1
                }
                port.remaining = u32(port.link_count)
                bindings[plan.bindings] = {port = port_handle, buffer = port.buffer}
                plan.bindings += 1
                step.outputs += 1
            }
            port_handle = port.next_in_node
        }
        // what this step has read is free after it (when it was the last reader), and so is what it wrote that nobody reads
        for b in 0 ..< int(step.inputs) {
            source: ^Port = GraphPort(graph, GraphLink(graph, bindings[int(step.first) + b].link).from)
            source.remaining -= 1
            if source.remaining == 0 { free[free_count] = source.buffer; free_count += 1 }
        }
        for b in 0 ..< int(step.outputs) {
            written: ^Port = GraphPort(graph, bindings[int(step.first) + int(step.inputs) + b].port)
            if written.remaining == 0 { free[free_count] = written.buffer; free_count += 1 }
        }
        steps[plan.steps] = step
        plan.steps += 1
    }
    plan.buffers = int(next_buffer)
    return plan, .OK
}

// ------------------------------------------------------------------------------------------------------------------------
// Moving and selecting nodes

// Moves a node and the anchors of its pins with it (the widgets measure the anchors only for nodes that are declared, a node that is not on screen keeps the
// offsets it had). Does not tell: the caller emits NODE_MOVED when a move is done.
GraphNodeMove :: proc(graph: ^Graph, handle: NodeHandle, position: Vec2) {
    node: ^Node = GraphNode(graph, handle)
    if node == nil { return }
    node.position = position
    port_handle: PortHandle = node.first_port
    for port_handle != {} {
        port: ^Port = GraphPort(graph, port_handle)
        if port == nil { break }
        if port.anchor_known { port.anchor = position + port.offset }
        port_handle = port.next_in_node
    }
}

GraphNodeSelect :: proc(graph: ^Graph, handle: NodeHandle, selected: bool = true) {
    node: ^Node = GraphNode(graph, handle)
    if node != nil { node.selected = selected }
}

GraphSelectClear :: proc(graph: ^Graph) {
    it := hm.iterator_make(&graph.nodes)
    for node, _ in hm.iterate(&it) { node.selected = false }
}

GraphSelectedCount :: proc(graph: ^Graph) -> (count: int) {
    it := hm.iterator_make(&graph.nodes)
    for node, _ in hm.iterate(&it) {
        if node.selected { count += 1 }
    }
    return
}

// ------------------------------------------------------------------------------------------------------------------------
// Collapsed nodes, labels on cables, reroute points

// Collapses a node to its title (its pins are not declared, its cables go to the edges of the title) or opens it again. One NODE_COLLAPSED event when it changed.
GraphNodeCollapse :: proc(graph: ^Graph, handle: NodeHandle, collapsed: bool = true) -> bool {
    node: ^Node = GraphNode(graph, handle)
    if node == nil { return false }
    if node.collapsed != collapsed {
        node.collapsed = collapsed
        graphEmit(graph, {kind = .NODE_COLLAPSED, node = handle, collapsed = collapsed, position = node.position})
    }
    return true
}

// The text on a cable (cut to GRAPH_NAME_MAX bytes, empty: none): what flows through it, a gain, a channel. One LINK_LABELED event when it changed.
GraphLinkLabel :: proc(graph: ^Graph, handle: LinkHandle, text: string) -> bool {
    link: ^Link = GraphLink(graph, handle)
    if link == nil { return false }
    if GraphLinkLabelText(link) != text[:min(len(text), GRAPH_NAME_MAX)] {
        setName(link.label[:], &link.label_length, text)
        graphEmit(graph, linkEvent(graph, .LINK_LABELED, link))
    }
    return true
}

GraphLinkLabelText :: proc(link: ^Link) -> string {
    return string(link.label[:link.label_length])
}

// Puts a reroute point on a cable: a small node at `position` (its middle) with one input and one output, and two cables in place of the one (the color, the `user` pointer
// and the label of the cable stay on both halves). The ports have the data types of the ends they face. False, and the graph as it was, when the cable is not there, the graph has
// no room or the rules refuse a half.
GraphRerouteAdd :: proc(graph: ^Graph, handle: LinkHandle, position: Vec2) -> (node: NodeHandle, ok: bool) {
    link: ^Link = GraphLink(graph, handle)
    if link == nil { return }
    from, to: PortHandle = link.from, link.to
    from_port, to_port: ^Port = GraphPort(graph, from), GraphPort(graph, to)
    color, user, label, label_length := link.color, link.user, link.label, link.label_length
    from_type, to_type: u32 = from_port.data_type, to_port.data_type
    made, made_ok := graphNodeAdd(graph, "", position - {10, 8}, nil, {}, {})
    if !made_ok { return }
    GraphNode(graph, made).reroute = true
    input, input_ok := GraphPortAdd(graph, made, "", .INPUT, from_type)
    output, output_ok := GraphPortAdd(graph, made, "", .OUTPUT, to_type)
    // both halves are asked of the rules before the cable is touched (a full port is fine: the old cable goes)
    fits :: proc(result: ConnectResult) -> bool { return ConnectOk(result) || result == .FULL }
    if !input_ok || !output_ok || !fits(GraphCanConnect(graph, from, input)) || !fits(GraphCanConnect(graph, output, to)) {
        GraphNodeRemove(graph, made)
        return
    }
    GraphDisconnect(graph, handle)
    first, first_result := GraphConnect(graph, from, input, user)
    second, second_result := GraphConnect(graph, output, to, user)
    if !ConnectOk(first_result) || !ConnectOk(second_result) {
        GraphNodeRemove(graph, made)
        GraphConnect(graph, from, to, user)
        return
    }
    for half in ([2]LinkHandle{first, second}) {
        stored: ^Link = GraphLink(graph, half)
        stored.color, stored.label, stored.label_length = color, label, label_length
    }
    return made, true
}
