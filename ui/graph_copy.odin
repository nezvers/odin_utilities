package ui

// Copy and paste of a part of a graph: the selected nodes with their ports, the links between them, and the zip ties that hold only those links. The copy lives in a
// `GraphClipboard` that the program provides (one for the program, big enough for the copied part, fixed capacities: what does not fit is left out), so a copy outlives the nodes
// it was made from, and the same copy can be pasted into another graph.
//
//     clipboard: ui.GraphClipboard                       // a global or a heap allocation
//     ui.GraphCopy(&graph, &clipboard)                   // the selected nodes
//     ui.GraphPaste(&graph, &clipboard, {200, 120})      // the top left of the copied nodes goes there; the new nodes are the selection
//
// The new nodes tell it in their NODE_ADDED event (`copied_from`): a program that keeps data for a node (a plugin instance, its parameters) makes its own copy of it then. The `user`
// pointers of nodes and ports are copied as they are, the rules decide for every link (one that may not be made is left out).

import hm "core:container/handle_map"

GRAPH_COPY_NODES :: #config(GRAPH_COPY_NODES, 64)
GRAPH_COPY_PORTS :: #config(GRAPH_COPY_PORTS, 512)
GRAPH_COPY_LINKS :: #config(GRAPH_COPY_LINKS, 512)
GRAPH_COPY_TIES :: #config(GRAPH_COPY_TIES, 32)

@(private)
GraphCopiedPort :: struct {
    name: [GRAPH_NAME_MAX]u8,
    name_length: int,
    kind: PortKind,
    flags: PortFlags,
    data_type: u32,
    color: Color,
    user: rawptr,
    source: PortHandle,
}

@(private)
GraphCopiedNode :: struct {
    name: [GRAPH_NAME_MAX]u8,
    name_length: int,
    offset: Vec2,               // from the top left of everything that was copied
    color: Color,
    user: rawptr,
    source: NodeHandle,
    first_port: int,            // in the clipboard
    port_count: int,
}

@(private)
GraphCopiedLink :: struct {
    from: int,                  // the port, in the clipboard
    to: int,
    color: Color,
    user: rawptr,
    source: LinkHandle,
}

@(private)
GraphCopiedTie :: struct {
    offset: Vec2,
    angle: f32,
    scale: f32,
    color: Color,
    name: [GRAPH_NAME_MAX]u8,
    name_length: int,
    members: [GRAPH_TIE_MEMBERS]int,    // links, in the clipboard
    member_count: int,
}

GraphClipboard :: struct {
    nodes: [GRAPH_COPY_NODES]GraphCopiedNode,
    node_count: int,
    ports: [GRAPH_COPY_PORTS]GraphCopiedPort,
    port_count: int,
    links: [GRAPH_COPY_LINKS]GraphCopiedLink,
    link_count: int,
    ties: [GRAPH_COPY_TIES]GraphCopiedTie,
    tie_count: int,
    size: Vec2,                 // of the box around the copied nodes
}

// Copies the selected nodes (as many as fit) with their ports, the links that join two of them and the zip ties that gather only such links, in place of what the clipboard held.
// Returns the number of nodes.
GraphCopy :: proc(graph: ^Graph, clipboard: ^GraphClipboard) -> int {
    clipboard^ = {}
    low, high: Vec2 = {max(f32), max(f32)}, {-max(f32), -max(f32)}
    it := hm.iterator_make(&graph.nodes)
    for node, _ in hm.iterate(&it) {
        if !node.selected { continue }
        low = {min(low.x, node.position.x), min(low.y, node.position.y)}
        high = {max(high.x, node.position.x + node.size.x), max(high.y, node.position.y + node.size.y)}
    }
    it = hm.iterator_make(&graph.nodes)
    for node, handle in hm.iterate(&it) {
        if !node.selected || clipboard.node_count >= len(clipboard.nodes) { continue }
        // all of its ports or none of them
        if clipboard.port_count + node.port_count > len(clipboard.ports) { continue }
        entry: ^GraphCopiedNode = &clipboard.nodes[clipboard.node_count]
        entry^ = {name = node.name, name_length = node.name_length, offset = node.position - low, color = node.color, user = node.user, source = handle, first_port = clipboard.port_count}
        port_handle: PortHandle = node.first_port
        for port_handle != {} {
            port: ^Port = GraphPort(graph, port_handle)
            if port == nil { break }
            clipboard.ports[clipboard.port_count] = {
                name = port.name, name_length = port.name_length, kind = port.kind, flags = port.flags, data_type = port.data_type, color = port.color, user = port.user, source = port_handle,
            }
            clipboard.port_count += 1
            entry.port_count += 1
            port_handle = port.next_in_node
        }
        clipboard.node_count += 1
    }
    clipboard.size = {max(high.x - low.x, 0), max(high.y - low.y, 0)} if clipboard.node_count > 0 else {}
    index_of_port :: proc(clipboard: ^GraphClipboard, port: PortHandle) -> int {
        for i in 0 ..< clipboard.port_count {
            if clipboard.ports[i].source == port { return i }
        }
        return -1
    }
    links := hm.iterator_make(&graph.links)
    for link, handle in hm.iterate(&links) {
        if clipboard.link_count >= len(clipboard.links) { break }
        from, to: int = index_of_port(clipboard, link.from), index_of_port(clipboard, link.to)
        if from < 0 || to < 0 { continue }
        clipboard.links[clipboard.link_count] = {from = from, to = to, color = link.color, user = link.user, source = handle}
        clipboard.link_count += 1
    }
    ties := hm.iterator_make(&graph.ties)
    for tie, _ in hm.iterate(&ties) {
        if clipboard.tie_count >= len(clipboard.ties) { break }
        entry: GraphCopiedTie = {offset = tie.position - low, angle = tie.angle, scale = tie.scale, color = tie.color, name = tie.name, name_length = tie.name_length}
        complete: bool = tie.member_count > 0
        for i in 0 ..< tie.member_count {
            found: int = -1
            for k in 0 ..< clipboard.link_count {
                if clipboard.links[k].source == tie.members[i] { found = k }
            }
            if found < 0 {
                complete = false
                break
            }
            entry.members[entry.member_count] = found
            entry.member_count += 1
        }
        if complete {
            clipboard.ties[clipboard.tie_count] = entry
            clipboard.tie_count += 1
        }
    }
    return clipboard.node_count
}

// Puts the copy into the graph: the top left corner of the copied nodes at `position`. The pasted nodes are the selection afterwards (the others are not). Returns the number of nodes
// that were made (fewer when the graph has no room); a link that the rules refuse is left out.
GraphPaste :: proc(graph: ^Graph, clipboard: ^GraphClipboard, position: Vec2) -> int {
    if clipboard.node_count == 0 { return 0 }
    GraphSelectClear(graph)
    ports: [GRAPH_COPY_PORTS]PortHandle
    links: [GRAPH_COPY_LINKS]LinkHandle
    made: int
    for i in 0 ..< clipboard.node_count {
        entry: ^GraphCopiedNode = &clipboard.nodes[i]
        handle, ok := graphNodeAdd(graph, string(entry.name[:entry.name_length]), position + entry.offset, entry.user, entry.color, entry.source)
        if !ok { break }
        made += 1
        GraphNodeSelect(graph, handle)
        for k in entry.first_port ..< entry.first_port + entry.port_count {
            copied: ^GraphCopiedPort = &clipboard.ports[k]
            ports[k], _ = GraphPortAdd(graph, handle, string(copied.name[:copied.name_length]), copied.kind, copied.data_type, copied.flags, copied.user, copied.color)
        }
    }
    for i in 0 ..< clipboard.link_count {
        copied: ^GraphCopiedLink = &clipboard.links[i]
        if ports[copied.from] == {} || ports[copied.to] == {} { continue }
        link, result := GraphConnect(graph, ports[copied.from], ports[copied.to], copied.user)
        if ConnectOk(result) && link != {} {
            if stored := GraphLink(graph, link); stored != nil { stored.color = copied.color }
            links[i] = link
        }
    }
    for i in 0 ..< clipboard.tie_count {
        copied: ^GraphCopiedTie = &clipboard.ties[i]
        members: [GRAPH_TIE_MEMBERS]LinkHandle
        count: int
        for k in 0 ..< copied.member_count {
            if links[copied.members[k]] != {} {
                members[count] = links[copied.members[k]]
                count += 1
            }
        }
        if count == 0 { continue }
        if tie, ok := GraphTieAdd(graph, position + copied.offset, copied.angle, members[:count], copied.color); ok {
            stored: ^Tie = GraphTie(graph, tie)
            stored.scale, stored.name, stored.name_length = copied.scale, copied.name, copied.name_length
        }
    }
    return made
}

// A copy of the selected nodes put next to them (the top left of the copy at `offset` from the top left of the originals). The copies are the selection afterwards.
GraphDuplicate :: proc(graph: ^Graph, clipboard: ^GraphClipboard, offset: Vec2 = {32, 32}) -> int {
    low: Vec2 = {max(f32), max(f32)}
    it := hm.iterator_make(&graph.nodes)
    for node, _ in hm.iterate(&it) {
        if node.selected { low = {min(low.x, node.position.x), min(low.y, node.position.y)} }
    }
    if GraphCopy(graph, clipboard) == 0 { return 0 }
    return GraphPaste(graph, clipboard, low + offset)
}
