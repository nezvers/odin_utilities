#+build !js
package ui

import "core:testing"

// The graphs are big (fixed storage): on the heap, one per test.
@(private = "file")
newGraph :: proc() -> ^Graph {
    graph: ^Graph = new(Graph)
    GraphInit(graph)
    return graph
}

// A node with `inputs` input ports and `outputs` output ports of data type 1.
@(private = "file")
makeNode :: proc(graph: ^Graph, name: string, inputs: int, outputs: int, position: Vec2 = {}) -> (node: NodeHandle, in_ports: [4]PortHandle, out_ports: [4]PortHandle) {
    node, _ = GraphNodeAdd(graph, name, position)
    for i in 0 ..< inputs { in_ports[i], _ = GraphPortAdd(graph, node, "in", .INPUT, 1) }
    for i in 0 ..< outputs { out_ports[i], _ = GraphPortAdd(graph, node, "out", .OUTPUT, 1) }
    return
}

@(private = "file")
drain :: proc(graph: ^Graph) {
    for {
        _, has := GraphPollEvent(graph)
        if !has { break }
    }
}

@(test)
test_graph_connects_and_disconnects_and_tells_who_did_what :: proc(t: ^testing.T) {
    graph: ^Graph = newGraph()
    defer free(graph)
    channel_a: int = 11
    channel_b: int = 22
    node_user: int = 33
    program: int = 44
    graph.user = &program
    source, _ := GraphNodeAdd(graph, "Oscillator", {10, 20}, &node_user)
    out, _ := GraphPortAdd(graph, source, "out", .OUTPUT, 1, user = &channel_a)
    sink, _ := GraphNodeAdd(graph, "Gain", {200, 20})
    input, _ := GraphPortAdd(graph, sink, "in", .INPUT, 1, user = &channel_b)

    added, _ := GraphPollEvent(graph)
    testing.expect_value(t, added.kind, GraphEventKind.NODE_ADDED)
    drain(graph)
    link, result := GraphConnect(graph, out, input)
    testing.expect_value(t, result, ConnectResult.OK)
    testing.expect(t, GraphLink(graph, link) != nil)
    event, has_event := GraphPollEvent(graph)
    testing.expect(t, has_event)
    testing.expect_value(t, event.kind, GraphEventKind.CONNECTED)
    testing.expect_value(t, event.link, link)
    testing.expect(t, event.from == out && event.to == input)
    testing.expect(t, event.from_user == &channel_a && event.to_user == &channel_b, "the pointers of the ports come with the event")
    testing.expect(t, event.from_node_user == &node_user && event.graph_user == &program, "and those of the node and of the graph")
    testing.expect(t, event.from_node == source && event.to_node == sink)

    testing.expect(t, GraphDisconnect(graph, link))
    testing.expect(t, GraphLink(graph, link) == nil, "the handle of a removed link is refused")
    testing.expect(t, !GraphDisconnect(graph, link), "twice is nothing")
    gone, _ := GraphPollEvent(graph)
    testing.expect_value(t, gone.kind, GraphEventKind.DISCONNECTED)
    testing.expect_value(t, gone.reason, DisconnectReason.REQUEST)
    testing.expect(t, gone.from_user == &channel_a && gone.to_user == &channel_b, "a disconnect has them too")
    testing.expect_value(t, GraphPort(graph, out).link_count, 0)
    testing.expect_value(t, GraphLinkCount(graph), 0)
    // a new link takes the place of the removed one: the old handle still means nothing
    again, _ := GraphConnect(graph, input, out)                                    // either order
    testing.expect(t, again != link && GraphLink(graph, link) == nil && GraphLink(graph, again) != nil)
}

@(private = "file")
callback_events: int
@(private = "file")
callback_last: GraphEventKind

@(test)
test_the_program_can_be_called_when_something_changes :: proc(t: ^testing.T) {
    graph: ^Graph = newGraph()
    defer free(graph)
    callback_events = 0
    graph.on_event = proc(graph: ^Graph, event: ^GraphEvent) {
        callback_events += 1
        callback_last = event.kind
    }
    _, _, outs := makeNode(graph, "a", 0, 1)
    _, ins, _ := makeNode(graph, "b", 1, 0)
    before: int = callback_events
    link, _ := GraphConnect(graph, outs[0], ins[0])
    testing.expect_value(t, callback_events, before + 1)
    testing.expect_value(t, callback_last, GraphEventKind.CONNECTED)
    GraphDisconnect(graph, link)
    testing.expect_value(t, callback_last, GraphEventKind.DISCONNECTED)
}

@(test)
test_events_that_nobody_reads_do_not_pile_up :: proc(t: ^testing.T) {
    graph: ^Graph = newGraph()
    defer free(graph)
    for i in 0 ..< GRAPH_EVENTS + 20 {
        // nodes that are removed again: every one is two events
        node, _ := GraphNodeAdd(graph, "n", {f32(i), 0})
        GraphNodeRemove(graph, node)
    }
    testing.expect(t, graph.event_count == GRAPH_EVENTS, "the queue has its size")
    testing.expect(t, graph.events_lost > 0, "and counts what it threw away")
}

@(test)
test_the_rules_say_what_may_be_connected :: proc(t: ^testing.T) {
    graph: ^Graph = newGraph()
    defer free(graph)
    _, a_in, a_out := makeNode(graph, "a", 1, 2)
    _, b_in, b_out := makeNode(graph, "b", 1, 1)
    c, c_in, _ := makeNode(graph, "c", 1, 1)
    testing.expect_value(t, GraphCanConnect(graph, a_out[0], a_in[0]), ConnectResult.SAME_NODE)
    testing.expect_value(t, GraphCanConnect(graph, a_out[0], a_out[1]), ConnectResult.SAME_KIND)
    testing.expect_value(t, GraphCanConnect(graph, a_in[0], b_in[0]), ConnectResult.SAME_KIND)
    testing.expect_value(t, GraphCanConnect(graph, a_out[0], PortHandle{}), ConnectResult.INVALID)
    other_type, _ := GraphPortAdd(graph, c, "mismatch", .INPUT, 2)
    testing.expect_value(t, GraphCanConnect(graph, a_out[0], other_type), ConnectResult.TYPE)
    anything, _ := GraphPortAdd(graph, c, "any", .INPUT, 0)
    testing.expect_value(t, GraphCanConnect(graph, a_out[0], anything), ConnectResult.OK)         // type 0 takes everything

    // a single input: the second link replaces the first, with the reason
    first, _ := GraphConnect(graph, a_out[0], b_in[0])
    testing.expect_value(t, GraphCanConnect(graph, a_out[1], b_in[0]), ConnectResult.REPLACES)
    drain(graph)
    second, result := GraphConnect(graph, a_out[1], b_in[0])
    testing.expect_value(t, result, ConnectResult.REPLACES)
    testing.expect(t, GraphLink(graph, first) == nil && GraphLink(graph, second) != nil)
    replaced, _ := GraphPollEvent(graph)
    testing.expect_value(t, replaced.kind, GraphEventKind.DISCONNECTED)
    testing.expect_value(t, replaced.reason, DisconnectReason.REPLACED)
    connected, _ := GraphPollEvent(graph)
    testing.expect_value(t, connected.kind, GraphEventKind.CONNECTED)
    // refused instead, when the rules say so
    graph.rules.refuse_when_full = true
    testing.expect_value(t, GraphCanConnect(graph, a_out[0], b_in[0]), ConnectResult.FULL)
    _, refused := GraphConnect(graph, a_out[0], b_in[0])
    testing.expect_value(t, refused, ConnectResult.FULL)
    testing.expect_value(t, GraphLinkCount(graph), 1)
    // twice
    testing.expect_value(t, GraphCanConnect(graph, a_out[1], b_in[0]), ConnectResult.DUPLICATE)

    // an output splits to any number of inputs
    _, split_one := GraphConnect(graph, b_out[0], c_in[0])
    _, split_two := GraphConnect(graph, b_out[0], anything)
    _, split_bad := GraphConnect(graph, b_out[0], other_type)
    testing.expect(t, split_one == .OK && split_two == .OK && split_bad == .TYPE)
    testing.expect_value(t, GraphPort(graph, b_out[0]).link_count, 2)
    // an input with MERGE takes any number of outputs
    mixer, _ := GraphNodeAdd(graph, "mixer", {})
    merging, _ := GraphPortAdd(graph, mixer, "sum", .INPUT, 1, {.MERGE})
    _, r1 := GraphConnect(graph, a_out[0], merging)
    _, r2 := GraphConnect(graph, a_out[1], merging)
    _, r3 := GraphConnect(graph, b_out[0], merging)
    testing.expect(t, r1 == .OK && r2 == .OK && r3 == .OK, "a merging input takes them all")
    testing.expect_value(t, GraphPort(graph, merging).link_count, 3)
    // an output with SINGLE takes one
    single_node, _ := GraphNodeAdd(graph, "single", {})
    single_out, _ := GraphPortAdd(graph, single_node, "out", .OUTPUT, 1, {.SINGLE})
    _, s1 := GraphConnect(graph, single_out, merging)
    _, s2 := GraphConnect(graph, single_out, c_in[0])
    testing.expect_value(t, s1, ConnectResult.OK)
    testing.expect_value(t, s2, ConnectResult.FULL)
}

@(test)
test_loops_are_refused_unless_the_rules_allow_feedback :: proc(t: ^testing.T) {
    graph: ^Graph = newGraph()
    defer free(graph)
    _, a_in, a_out := makeNode(graph, "a", 1, 1)
    _, b_in, b_out := makeNode(graph, "b", 1, 1)
    _, c_in, c_out := makeNode(graph, "c", 1, 1)
    _, _ = GraphConnect(graph, a_out[0], b_in[0])
    _, _ = GraphConnect(graph, b_out[0], c_in[0])
    testing.expect_value(t, GraphCanConnect(graph, c_out[0], a_in[0]), ConnectResult.CYCLE)
    testing.expect_value(t, GraphCanConnect(graph, b_out[0], a_in[0]), ConnectResult.CYCLE)
    graph.rules.allow_cycles = true
    testing.expect_value(t, GraphCanConnect(graph, c_out[0], a_in[0]), ConnectResult.OK)
    // the program's own rules can add to the default: here nothing may leave a node called "c"
    graph.rules.allow_cycles = false
    graph.rules.can_connect = proc(graph: ^Graph, from: ^Port, to: ^Port, user: rawptr) -> ConnectResult {
        if GraphNodeName(GraphNode(graph, from.node)) == "c" { return .TYPE }
        return DefaultCanConnect(graph, from, to)
    }
    testing.expect_value(t, GraphCanConnect(graph, c_out[0], a_in[0]), ConnectResult.TYPE)
    testing.expect_value(t, GraphCanConnect(graph, b_out[0], a_in[0]), ConnectResult.CYCLE)       // the default is still behind it
    // and the data types fit by the program's rule: here an output of type n fits an input of type n + 1
    graph.rules = {types_fit = proc(from_type: u32, to_type: u32, user: rawptr) -> bool { return from_type + 1 == to_type }}
    x, _ := GraphNodeAdd(graph, "x", {})
    y, _ := GraphNodeAdd(graph, "y", {})
    x_out, _ := GraphPortAdd(graph, x, "o", .OUTPUT, 1)
    y_one, _ := GraphPortAdd(graph, y, "i1", .INPUT, 1)
    y_two, _ := GraphPortAdd(graph, y, "i2", .INPUT, 2)
    testing.expect_value(t, GraphCanConnect(graph, x_out, y_one), ConnectResult.TYPE)
    testing.expect_value(t, GraphCanConnect(graph, x_out, y_two), ConnectResult.OK)
}

@(test)
test_nodes_are_ordered_so_that_every_node_follows_what_feeds_it :: proc(t: ^testing.T) {
    graph: ^Graph = newGraph()
    defer free(graph)
    // a diamond: source -> left, right -> mixer -> out, and one node nobody is connected to
    source, _, source_out := makeNode(graph, "source", 0, 1)
    left, left_in, left_out := makeNode(graph, "left", 1, 1)
    right, right_in, right_out := makeNode(graph, "right", 1, 1)
    mixer, _, mixer_out := makeNode(graph, "mixer", 0, 1)
    merging, _ := GraphPortAdd(graph, mixer, "sum", .INPUT, 1, {.MERGE})
    out, out_in, _ := makeNode(graph, "out", 1, 0)
    lonely, _, _ := makeNode(graph, "lonely", 0, 0)
    _, _ = GraphConnect(graph, source_out[0], left_in[0])
    _, _ = GraphConnect(graph, source_out[0], right_in[0])
    _, _ = GraphConnect(graph, left_out[0], merging)
    _, _ = GraphConnect(graph, right_out[0], merging)
    _, _ = GraphConnect(graph, mixer_out[0], out_in[0])
    order: [16]NodeHandle
    count, result := GraphOrder(graph, order[:])
    testing.expect_value(t, result, OrderResult.OK)
    testing.expect_value(t, count, 6)
    position :: proc(order: []NodeHandle, node: NodeHandle) -> int {
        for n, i in order { if n == node { return i } }
        return -1
    }
    testing.expect(t, position(order[:count], source) < position(order[:count], left))
    testing.expect(t, position(order[:count], source) < position(order[:count], right))
    testing.expect(t, position(order[:count], left) < position(order[:count], mixer))
    testing.expect(t, position(order[:count], right) < position(order[:count], mixer))
    testing.expect(t, position(order[:count], mixer) < position(order[:count], out))
    testing.expect(t, position(order[:count], lonely) >= 0)
    // the same every time
    again: [16]NodeHandle
    _, _ = GraphOrder(graph, again[:])
    testing.expect(t, order == again)
    // too small
    _, small := GraphOrder(graph, order[:3])
    testing.expect_value(t, small, OrderResult.SMALL)
    // feedback (allowed by the rules) is a loop: the nodes that are not in it are ordered, the plan is refused
    graph.rules.allow_cycles = true
    _, _ = GraphConnect(graph, out_in[0], out_in[0])                              // not possible (two inputs), nothing changes
    _, back_in, back_out := makeNode(graph, "back", 1, 1)
    _, _ = GraphConnect(graph, mixer_out[0], back_in[0])
    _, loop := GraphConnect(graph, back_out[0], GraphPort(graph, left_in[0]).handle)
    testing.expect(t, ConnectOk(loop))
    ordered, cycle := GraphOrder(graph, order[:7])
    testing.expect_value(t, cycle, OrderResult.CYCLE)
    testing.expect(t, ordered < 7)
    steps: [16]GraphStep
    bindings: [64]GraphBinding
    _, plan_result := GraphCompile(graph, steps[:], bindings[:])
    testing.expect_value(t, plan_result, PlanResult.CYCLE)
}

@(test)
test_a_plan_gives_every_port_a_buffer_and_reuses_them :: proc(t: ^testing.T) {
    graph: ^Graph = newGraph()
    defer free(graph)
    // a chain: oscillator -> gain -> filter -> out. Every port needs a buffer, but only two are ever alive at once.
    osc, _, osc_out := makeNode(graph, "osc", 0, 1)
    gain, gain_in, gain_out := makeNode(graph, "gain", 1, 1)
    filter, filter_in, filter_out := makeNode(graph, "filter", 1, 1)
    out, out_in, _ := makeNode(graph, "out", 1, 0)
    _, _ = GraphConnect(graph, osc_out[0], gain_in[0])
    _, _ = GraphConnect(graph, gain_out[0], filter_in[0])
    _, _ = GraphConnect(graph, filter_out[0], out_in[0])
    steps: [16]GraphStep
    bindings: [64]GraphBinding
    plan, result := GraphCompile(graph, steps[:], bindings[:])
    testing.expect_value(t, result, PlanResult.OK)
    testing.expect_value(t, plan.steps, 4)
    testing.expect_value(t, plan.buffers, 2)
    testing.expect(t, steps[0].node == osc && steps[1].node == gain && steps[2].node == filter && steps[3].node == out)
    // the first step writes, the second reads what it wrote and writes somewhere else (not in place)
    first: GraphStep = steps[0]
    testing.expect(t, first.inputs == 0 && first.outputs == 1)
    written: u32 = bindings[first.first].buffer
    second: GraphStep = steps[1]
    testing.expect(t, second.inputs == 1 && second.outputs == 1)
    testing.expect_value(t, bindings[second.first].buffer, written)
    testing.expect(t, bindings[second.first + 1].buffer != written, "not in place: the buffer that is read is still in use while the step writes")
    // the third step reuses the first buffer (nobody reads it any more)
    testing.expect_value(t, bindings[steps[2].first + 1].buffer, written)
    _, _, _ = gain, filter, out

    // a split and a merge: an output read by two (one buffer for both), an input that merges two (two bindings in a row on one port)
    other: ^Graph = newGraph()
    defer free(other)
    _, _, source_out := makeNode(other, "source", 0, 1)
    left, left_in, left_out := makeNode(other, "left", 1, 1)
    right, right_in, right_out := makeNode(other, "right", 1, 1)
    mixer, _ := GraphNodeAdd(other, "mixer", {})
    merging, _ := GraphPortAdd(other, mixer, "sum", .INPUT, 1, {.MERGE})
    mixed, _ := GraphPortAdd(other, mixer, "out", .OUTPUT, 1)
    _, _ = GraphConnect(other, source_out[0], left_in[0])
    _, _ = GraphConnect(other, source_out[0], right_in[0])
    _, _ = GraphConnect(other, left_out[0], merging)
    _, _ = GraphConnect(other, right_out[0], merging)
    plan2, result2 := GraphCompile(other, steps[:], bindings[:])
    testing.expect_value(t, result2, PlanResult.OK)
    testing.expect_value(t, plan2.steps, 4)
    // the source wrote one buffer that both branches read
    source_buffer: u32 = bindings[steps[0].first].buffer
    reads: int
    for step in steps[1:3] {
        testing.expect_value(t, bindings[step.first].buffer, source_buffer)
        reads += 1
    }
    testing.expect_value(t, reads, 2)
    // the mixer's merging input has two bindings on one port, from two different buffers
    mix_step: GraphStep = steps[3]
    testing.expect_value(t, mix_step.node, mixer)
    testing.expect_value(t, mix_step.inputs, 2)
    testing.expect(t, bindings[mix_step.first].port == merging && bindings[mix_step.first + 1].port == merging)
    testing.expect(t, bindings[mix_step.first].buffer != bindings[mix_step.first + 1].buffer)
    testing.expect_value(t, bindings[mix_step.first + 2].port, mixed)
    testing.expect(t, plan2.buffers <= 3, "three buffers are enough for a split and a merge")
    _, _ = left, right

    // refused in words when the plan does not fit
    _, small := GraphCompile(other, steps[:2], bindings[:])
    testing.expect_value(t, small, PlanResult.STEPS_FULL)
    _, tiny := GraphCompile(other, steps[:], bindings[:3])
    testing.expect_value(t, tiny, PlanResult.BINDINGS_FULL)
}

@(test)
test_removing_a_node_removes_its_links_and_tells_about_each :: proc(t: ^testing.T) {
    graph: ^Graph = newGraph()
    defer free(graph)
    source, _, source_out := makeNode(graph, "source", 0, 1)
    middle, middle_in, middle_out := makeNode(graph, "middle", 1, 1)
    sink, sink_in, _ := makeNode(graph, "sink", 1, 0)
    first, _ := GraphConnect(graph, source_out[0], middle_in[0])
    second, _ := GraphConnect(graph, middle_out[0], sink_in[0])
    drain(graph)
    testing.expect(t, GraphNodeRemove(graph, middle))
    testing.expect(t, GraphNode(graph, middle) == nil && GraphPort(graph, middle_in[0]) == nil, "the ports go with the node")
    testing.expect(t, GraphLink(graph, first) == nil && GraphLink(graph, second) == nil)
    testing.expect_value(t, GraphPort(graph, source_out[0]).link_count, 0)
    testing.expect_value(t, GraphPort(graph, sink_in[0]).link_count, 0)
    disconnects, removed: int
    for {
        event, has := GraphPollEvent(graph)
        if !has { break }
        if event.kind == .DISCONNECTED {
            disconnects += 1
            testing.expect_value(t, event.reason, DisconnectReason.NODE_REMOVED)
        }
        if event.kind == .NODE_REMOVED { removed += 1 }
    }
    testing.expect_value(t, disconnects, 2)
    testing.expect_value(t, removed, 1)
    _, _ = source, sink
}

@(test)
test_the_links_of_a_port_are_a_list_in_the_order_they_were_made :: proc(t: ^testing.T) {
    graph: ^Graph = newGraph()
    defer free(graph)
    _, _, out := makeNode(graph, "splitter", 0, 1)
    sinks: [3]PortHandle
    links: [3]LinkHandle
    for i in 0 ..< 3 {
        _, ins, _ := makeNode(graph, "sink", 1, 0)
        sinks[i] = ins[0]
        links[i], _ = GraphConnect(graph, out[0], ins[0])
    }
    walked: [3]LinkHandle
    count: int
    for link := GraphPortFirstLink(graph, out[0]); link != {}; link = GraphLinkNext(graph, link, out[0]) {
        walked[count] = link
        count += 1
    }
    testing.expect_value(t, count, 3)
    testing.expect(t, walked == links)
    // the middle one goes: the list closes up, both ways
    GraphDisconnect(graph, links[1])
    testing.expect_value(t, GraphLinkNext(graph, links[0], out[0]), links[2])
    testing.expect_value(t, GraphLink(graph, links[2]).prev_from, links[0])
    testing.expect_value(t, GraphLinkOther(graph, links[2], out[0]), sinks[2])
    testing.expect_value(t, GraphPort(graph, out[0]).link_count, 2)
    GraphDisconnect(graph, links[0])
    GraphDisconnect(graph, links[2])
    testing.expect(t, GraphPort(graph, out[0]).first_link == {} && GraphPort(graph, out[0]).last_link == {})
}

@(test)
test_a_zip_tie_gathers_links_into_lanes_and_lets_go_of_them :: proc(t: ^testing.T) {
    graph: ^Graph = newGraph()
    defer free(graph)
    _, _, a := makeNode(graph, "a", 0, 3)
    _, b, _ := makeNode(graph, "b", 3, 0)
    links: [3]LinkHandle
    for i in 0 ..< 3 { links[i], _ = GraphConnect(graph, a[i], b[i]) }
    drain(graph)
    tie, ok := GraphTieAdd(graph, {100, 50}, 0, links[:])
    testing.expect(t, ok)
    event, _ := GraphPollEvent(graph)
    testing.expect_value(t, event.kind, GraphEventKind.TIE_ADDED)
    testing.expect_value(t, GraphTie(graph, tie).member_count, 3)
    testing.expect_value(t, GraphTieLane(graph, tie, links[0]), 0)
    testing.expect_value(t, GraphTieLane(graph, tie, links[2]), 2)
    for link in links { testing.expect_value(t, GraphLink(graph, link).tie_count, 1) }
    // a second tie across two of them keeps their order in the first, whatever the order they are given in
    second, _ := GraphTieAdd(graph, {200, 50}, 0, {links[2], links[0]})
    testing.expect_value(t, GraphTieLane(graph, second, links[0]), 0)
    testing.expect_value(t, GraphTieLane(graph, second, links[2]), 1)
    testing.expect_value(t, GraphLink(graph, links[0]).tie_count, 2)
    // one link goes: it leaves its ties, a tie that holds nothing goes with it
    GraphDisconnect(graph, links[1])
    testing.expect_value(t, GraphTie(graph, tie).member_count, 2)
    GraphDisconnect(graph, links[0])
    GraphDisconnect(graph, links[2])
    testing.expect(t, GraphTie(graph, tie) == nil && GraphTie(graph, second) == nil, "no links, no tie")
    testing.expect_value(t, GraphTieCount(graph), 0)
    removed: int
    for {
        e, has := GraphPollEvent(graph)
        if !has { break }
        if e.kind == .TIE_REMOVED { removed += 1 }
    }
    testing.expect_value(t, removed, 2)
}

@(test)
test_the_ties_of_a_link_are_ordered_along_it_and_a_link_is_in_a_few_ties_at_most :: proc(t: ^testing.T) {
    graph: ^Graph = newGraph()
    defer free(graph)
    _, _, a := makeNode(graph, "a", 0, 1)
    _, b, _ := makeNode(graph, "b", 1, 0)
    GraphPort(graph, a[0]).anchor, GraphPort(graph, a[0]).anchor_known = {0, 0}, true
    GraphPort(graph, b[0]).anchor, GraphPort(graph, b[0]).anchor_known = {1000, 0}, true
    link, _ := GraphConnect(graph, a[0], b[0])
    far, _ := GraphTieAdd(graph, {800, 0}, 0, {link})
    near, _ := GraphTieAdd(graph, {200, 0}, 0, {link})
    middle, _ := GraphTieAdd(graph, {500, 0}, 0, {link})
    ties: [GRAPH_LINK_TIES]TieHandle = GraphLink(graph, link).ties
    testing.expect(t, ties[0] == near && ties[1] == middle && ties[2] == far, "from the output to the input, whatever the order they were added in")
    // move the near one beyond the middle one: the order follows after the ties are ordered again
    GraphTie(graph, near).position = {900, 0}
    GraphTieOrderLinks(graph, near)
    testing.expect_value(t, GraphLink(graph, link).ties[2], near)
    testing.expect_value(t, GraphLink(graph, link).ties[0], middle)
    // the fifth tie is refused: a link passes through GRAPH_LINK_TIES ties at most
    _, fourth := GraphTieAdd(graph, {950, 0}, 0, {link})
    testing.expect(t, fourth)
    _, fifth := GraphTieAdd(graph, {960, 0}, 0, {link})
    testing.expect(t, !fifth)
    testing.expect_value(t, GraphLink(graph, link).tie_count, GRAPH_LINK_TIES)
    // removing a tie straightens the link at that place only
    GraphTieRemove(graph, middle)
    testing.expect_value(t, GraphLink(graph, link).tie_count, GRAPH_LINK_TIES - 1)
    testing.expect(t, GraphTie(graph, middle) == nil)
}

@(test)
test_raising_a_node_puts_it_in_front_and_the_numbers_do_not_run_out :: proc(t: ^testing.T) {
    graph: ^Graph = newGraph()
    defer free(graph)
    first, _ := GraphNodeAdd(graph, "first", {})
    second, _ := GraphNodeAdd(graph, "second", {})
    testing.expect(t, GraphNode(graph, second).z > GraphNode(graph, first).z)
    GraphNodeRaise(graph, first)
    testing.expect(t, GraphNode(graph, first).z > GraphNode(graph, second).z)
    // after very many raises the numbers are renumbered and the order is kept
    graph.z_counter = 32000
    GraphNode(graph, first).z = 32000
    GraphNode(graph, second).z = 31000
    GraphNodeRaise(graph, second)
    testing.expect(t, GraphNode(graph, second).z > GraphNode(graph, first).z)
    testing.expect(t, graph.z_counter < 100)
}
