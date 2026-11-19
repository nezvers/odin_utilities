package ui

// Automatic layout of a graph: the nodes go in columns by how far they are from the sources (a node is one column right of the furthest node that feeds it), the nodes of a column are
// stacked and ordered by where their inputs come from, so cables cross as little as is cheap, and the columns are centered on each other. Fixed storage on the stack, no allocation.
//
//     ui.GraphAutoLayout(&graph, {40, 40})         // the top left of the layout, canvas coordinates
//
// The size of a node is the one of the last frame (Node.size; a node that was never drawn counts as GRAPH_LAYOUT_DEFAULT_SIZE). Every node that moves tells NODE_MOVED, so a history or a
// program that keeps positions hears it. A graph with a loop is left as it is (the result is false).

GRAPH_LAYOUT_DEFAULT_SIZE :: Vec2{160, 80}

// `gap`: the room between columns (x) and between the nodes of a column (y). False when the graph has a cycle.
GraphAutoLayout :: proc(graph: ^Graph, origin: Vec2 = {}, gap: Vec2 = {80, 30}) -> bool {
    if GraphNodeCount(graph) == 0 { return true }
    order: [GRAPH_NODES]NodeHandle
    count, result := GraphOrder(graph, order[:])
    if result != .OK { return false }

    // the column of every node, by the position in the order (visit holds that position while this runs)
    layer: [GRAPH_NODES]int
    for i in 0 ..< count { GraphNode(graph, order[i]).visit = u32(i) }
    layer_count: int = 1
    for i in 0 ..< count {
        node: ^Node = GraphNode(graph, order[i])
        port_handle: PortHandle = node.first_port
        for port_handle != {} {
            port: ^Port = GraphPort(graph, port_handle)
            if port.kind == .INPUT {
                link_handle: LinkHandle = port.first_link
                for link_handle != {} {
                    link: ^Link = GraphLink(graph, link_handle)
                    source: ^Node = GraphNode(graph, GraphPort(graph, link.from).node)
                    layer[i] = max(layer[i], layer[source.visit] + 1)
                    link_handle = link.next_to
                }
            }
            port_handle = port.next_in_node
        }
        layer_count = max(layer_count, layer[i] + 1)
    }

    // inside of a column: the rows follow the average row of the nodes that feed it (a stable insertion order, the first column keeps the order it was added in)
    row: [GRAPH_NODES]f32                      // by position in the order: the row index inside its column
    column_nodes: [GRAPH_NODES]int             // the positions in the order, column after column
    column_start: [GRAPH_NODES + 1]int
    filled: int
    for column in 0 ..< layer_count {
        column_start[column] = filled
        for i in 0 ..< count {
            if layer[i] == column { column_nodes[filled] = i; filled += 1 }
        }
        members: []int = column_nodes[column_start[column]:filled]
        key: [GRAPH_NODES]f32
        for member, k in members {
            key[k] = layoutFeedKey(graph, order[member], &row, f32(k))
        }
        for a in 1 ..< len(members) {                                      // insertion sort by key: stable
            b: int = a
            for b > 0 && key[b - 1] > key[b] {
                key[b - 1], key[b] = key[b], key[b - 1]
                members[b - 1], members[b] = members[b], members[b - 1]
                b -= 1
            }
        }
        for member, k in members { row[member] = f32(k) }
    }
    column_start[layer_count] = filled

    // sizes: the width of a column, the height of a stack, and the tallest one to center the others on
    height: [GRAPH_NODES]f32
    width: [GRAPH_NODES]f32
    tallest: f32
    for column in 0 ..< layer_count {
        members: []int = column_nodes[column_start[column]:column_start[column + 1]]
        for member, k in members {
            size: Vec2 = layoutSize(GraphNode(graph, order[member]))
            width[column] = max(width[column], size.x)
            height[column] += size.y + (gap.y if k > 0 else 0)
        }
        tallest = max(tallest, height[column])
    }
    x: f32 = origin.x
    for column in 0 ..< layer_count {
        members: []int = column_nodes[column_start[column]:column_start[column + 1]]
        y: f32 = origin.y + (tallest - height[column]) * 0.5
        for member in members {
            node: ^Node = GraphNode(graph, order[member])
            position: Vec2 = {x, y}
            if position != node.position {
                GraphNodeMove(graph, order[member], position)
                graphEmit(graph, {kind = .NODE_MOVED, node = order[member], position = position})
            }
            y += layoutSize(node).y + gap.y
        }
        x += width[column] + gap.x
    }
    return true
}

@(private)
layoutSize :: proc(node: ^Node) -> Vec2 {
    return node.size if node.size.x > 0 && node.size.y > 0 else GRAPH_LAYOUT_DEFAULT_SIZE
}

// The average row of the nodes that feed `handle` (`fallback` when nothing does)
@(private)
layoutFeedKey :: proc(graph: ^Graph, handle: NodeHandle, row: ^[GRAPH_NODES]f32, fallback: f32) -> f32 {
    sum: f32
    fed: int
    node: ^Node = GraphNode(graph, handle)
    port_handle: PortHandle = node.first_port
    for port_handle != {} {
        port: ^Port = GraphPort(graph, port_handle)
        if port.kind == .INPUT {
            link_handle: LinkHandle = port.first_link
            for link_handle != {} {
                link: ^Link = GraphLink(graph, link_handle)
                sum += row[GraphNode(graph, GraphPort(graph, link.from).node).visit]
                fed += 1
                link_handle = link.next_to
            }
        }
        port_handle = port.next_in_node
    }
    return sum / f32(fed) if fed > 0 else fallback
}
