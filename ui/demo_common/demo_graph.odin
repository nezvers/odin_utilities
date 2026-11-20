#+private file
package demo_common

// A node graph of the kind an audio program has: sources, effects, a mixer that takes any number of inputs, an output. Drag from a pin to make a cable and let go
// over a pin it fits (the pins it does not fit dim), drag from a connected input to take its cable, drag a node by its title, drag the empty canvas to pan, drag
// in the minimap to move the view. With the zip tie tool on, a stroke across cables gathers them into a tie (a ribbon with one lane each) and a stroke across a
// tie removes it. The last event of the graph (who connected to what, with the user pointers of the ports) is shown in the toolbar.

import "core:fmt"
import hm "core:container/handle_map"
import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_graph: kit.Demo = {
    name = "graph",
    init = init,
    draw = draw,
    script = script,
}

// What the program keeps next to the nodes: here the name of a channel for every port (the `user` pointer of a port).
Channel :: struct {
    name: string,
    gain: f32,
}

State :: struct {
    app: UiDemo,
    graph: ui.Graph,
    view: ui.GraphView,
    clipboard: ui.GraphClipboard,                       // Ctrl + C, X, V, D
    before_nodes: int,
    before_links: int,
    channels: [16]Channel,
    channel_count: int,
    nodes: [8]ui.NodeHandle,
    node_count: int,
    log: [160]u8,
    log_length: int,
    zip_tool: bool,
    box_tool: bool,
    events: int,
    connected: int,
    disconnected: int,
}

state: State

// A node with its ports: `inputs` then `outputs`, every port has a Channel as its user pointer.
addNode :: proc(name: string, position: ui.Vec2, inputs: []string, outputs: []string, merging: bool = false) -> ui.NodeHandle {
    node, _ := ui.GraphNodeAdd(&state.graph, name, position, color = {})
    for port_name in inputs {
        state.channels[state.channel_count] = {name = port_name}
        flags: ui.PortFlags = {.MERGE} if merging else {}
        ui.GraphPortAdd(&state.graph, node, port_name, .INPUT, 1, flags, &state.channels[state.channel_count])
        state.channel_count += 1
    }
    for port_name in outputs {
        state.channels[state.channel_count] = {name = port_name}
        ui.GraphPortAdd(&state.graph, node, port_name, .OUTPUT, 1, user = &state.channels[state.channel_count])
        state.channel_count += 1
    }
    state.nodes[state.node_count] = node
    state.node_count += 1
    return node
}

firstPort :: proc(node: ui.NodeHandle, kind: ui.PortKind) -> ui.PortHandle {
    port: ^ui.Port = ui.GraphPort(&state.graph, ui.GraphNode(&state.graph, node).first_port)
    for port != nil {
        if port.kind == kind { return port.handle }
        port = ui.GraphPort(&state.graph, port.next_in_node)
    }
    return {}
}

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_demo_init(&state.app)
    ui.GraphInit(&state.graph)
    state.view.clipboard = &state.clipboard
    state.view.reroute_on_double_click = true
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
    osc: ui.NodeHandle = addNode("Oscillator", {40, 50}, {}, {"saw"})
    noise: ui.NodeHandle = addNode("Noise", {40, 210}, {}, {"white"})
    gain: ui.NodeHandle = addNode("Gain", {290, 30}, {"in"}, {"out"})
    filter: ui.NodeHandle = addNode("Filter", {290, 190}, {"in"}, {"out"})
    mixer: ui.NodeHandle = addNode("Mixer", {540, 110}, {"sum"}, {"mix"}, merging = true)
    output: ui.NodeHandle = addNode("Output", {800, 110}, {"left"}, {})
    wave, _ := ui.GraphConnect(&state.graph, firstPort(osc, .OUTPUT), firstPort(gain, .INPUT))
    ui.GraphLinkLabel(&state.graph, wave, "saw 440")
    ui.GraphConnect(&state.graph, firstPort(noise, .OUTPUT), firstPort(filter, .INPUT))
    ui.GraphConnect(&state.graph, firstPort(gain, .OUTPUT), firstPort(mixer, .INPUT))
    ui.GraphConnect(&state.graph, firstPort(filter, .OUTPUT), firstPort(mixer, .INPUT))
    master, _ := ui.GraphConnect(&state.graph, firstPort(mixer, .OUTPUT), firstPort(output, .INPUT))
    ui.GraphLinkLabel(&state.graph, master, "master")
    state.graph.on_event = onEvent
    state.graph.user = &state
    state.log_length = 0
    state.connected, state.disconnected = 0, 0
    for {
        _, has := ui.GraphPollEvent(&state.graph)
        if !has { break }
    }
}

// The program is told at once (this is the user context of the event: the channel names come from the `user` pointers of the ports).
onEvent :: proc(graph: ^ui.Graph, event: ^ui.GraphEvent) {
    s: ^State = cast(^State)graph.user
    s.events += 1
    from, to: string
    if channel := cast(^Channel)event.from_user; channel != nil { from = channel.name }
    if channel := cast(^Channel)event.to_user; channel != nil { to = channel.name }
    #partial switch event.kind {
    case .CONNECTED:
        s.connected += 1
        s.log_length = len(fmt.bprintf(s.log[:], "connected %s -> %s", from, to))
    case .DISCONNECTED:
        s.disconnected += 1
        s.log_length = len(fmt.bprintf(s.log[:], "disconnected %s -> %s (%v)", from, to, event.reason))
    case .TIE_ADDED:
        s.log_length = len(fmt.bprintf(s.log[:], "zip tie added"))
    case .TIE_REMOVED:
        s.log_length = len(fmt.bprintf(s.log[:], "zip tie removed"))
    }
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "graph demo", {size = {ui.Fixed(1000), ui.Fixed(600)}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(8), gap = 8}) {
        if ui.UiPanel(c, "toolbar", {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 12, align = {y = .CENTER}}, blocks_pointer = false) {
            if ui.UiToggle(c, "Zip tie tool", &state.zip_tool) {
                state.box_tool = false
                state.view.tool = .TIES if state.zip_tool else .SELECT
            }
            if ui.UiButton(c, "Fit view") { ui.GraphViewFit(&state.graph, &state.view) }
            if ui.UiToggle(c, "Box select", &state.box_tool) {
                state.zip_tool = false
                state.view.tool = .BOX if state.box_tool else .SELECT
            }
            ui.UiLabel(c, string(state.log[:state.log_length]))
        }
        if ui.UiPanel(c, "body", {size = {ui.Grow(), ui.Grow()}, direction = .LEFT_TO_RIGHT, gap = 8}, blocks_pointer = false) {
            if ui.UiGraph(c, "canvas", &state.graph, &state.view) {
                order: [16]ui.NodeHandle
                count: int = ui.GraphNodesByDepth(&state.graph, order[:], &state.view)      // the nodes outside of the view are not declared
                for node in order[:count] {
                    if ui.UiGraphNode(c, &state.graph, node) {
                        port: ^ui.Port = ui.GraphPort(&state.graph, ui.GraphNode(&state.graph, node).first_port)
                        for port != nil {
                            ui.UiGraphPin(c, &state.graph, port.handle)
                            port = ui.GraphPort(&state.graph, port.next_in_node)
                        }
                    }
                }
            }
            ui.UiGraphMinimap(c, "map", &state.graph, &state.view, {ui.Fixed(180), ui.Fixed(120)})
        }
    }
    ui_demo_end(&state.app)
}

// Screen positions (the canvas is at (8, 44), the nodes are at their position inside of it, a pin 16 pixels from the side of its node):
// the output of Gain (472, 144), of Filter (472, 304), the input of Gain (314, 118), of Filter (314, 278), of the Mixer (564, 198), Noise (222, 298)
script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return ui.GraphNodeCount(&state.graph) == 6 && ui.GraphLinkCount(&state.graph) == 5
    }, "the graph starts with six nodes and five cables"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        port: ^ui.Port = ui.GraphPort(&state.graph, firstPort(state.nodes[2], .INPUT))
        return port.anchor_known && abs(port.anchor.x - 306) < 1.5 && abs(port.anchor.y - 74) < 1.5
    }, "the pins know where they are (canvas coordinates) after the first frame"),
    kit.Capture("graph"),
    // a new cable from the output of Noise to the merging input of the Mixer: it takes any number of cables
    kit.MoveTo({222, 298}),
    kit.Wait(3),
    kit.Drag({222, 298}, {564, 198}, 12),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return ui.GraphLinkCount(&state.graph) == 6 && state.connected == 1
    }, "dragging from a pin to a pin made a cable and told the program"),
    // from the output of Gain to the input of Gain: the rules refuse (the same node)
    kit.MoveTo({472, 144}),
    kit.Wait(3),
    kit.Drag({472, 144}, {314, 118}, 12),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.GraphLinkCount(&state.graph) == 6 }, "a cable to its own node is refused"),
    // taking the new cable from the Mixer input and letting it go over nothing removes it
    kit.MoveTo({564, 198}),
    kit.Wait(3),
    kit.Drag({564, 198}, {600, 480}, 12),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return ui.GraphLinkCount(&state.graph) == 5 && state.disconnected == 1
    }, "a cable that is taken and dropped on the empty canvas is removed"),
    // the empty canvas pans
    kit.MoveTo({400, 500}),
    kit.Wait(3),
    kit.Drag({400, 500}, {350, 470}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return abs(state.view.origin.x - 50) < 1 && abs(state.view.origin.y - 30) < 1
    }, "dragging the empty canvas moved the view"),
    kit.Drag({350, 470}, {400, 500}, 8),
    kit.Wait(3),
    // a node by its title
    kit.MoveTo({100, 268}),
    kit.Wait(3),
    kit.Drag({100, 268}, {120, 268}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        node: ^ui.Node = ui.GraphNode(&state.graph, state.nodes[1])
        return abs(node.position.x - 60) < 1 && abs(node.position.y - 210) < 1
    }, "dragging a title moved the node"),
    // the zip tie tool: a stroke across the two cables into the Mixer gathers them
    kit.Click({40, 22}),
    kit.Wait(3),
    kit.MoveTo({518, 100}),
    kit.Wait(3),
    kit.Drag({518, 100}, {518, 340}, 10),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if ui.GraphTieCount(&state.graph) != 1 { return false }
        it := hm.iterator_make(&state.graph.ties)
        tie, _, _ := hm.iterate(&it)
        return tie.member_count == 2
    }, "a stroke across two cables made a zip tie with both"),
    kit.Capture("graph_tie"),
    // a stroke across the tie removes it
    kit.MoveTo({480, 215}),
    kit.Wait(3),
    kit.Drag({480, 215}, {560, 215}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.GraphTieCount(&state.graph) == 0 && ui.GraphLinkCount(&state.graph) == 5 }, "a stroke across the tie removed it, the cables stay"),
    // the minimap: pressing near its right edge moves the view to the Output node
    kit.Click({40, 22}),
    kit.Wait(3),
    // the box tool: a rectangle selects the nodes it touches, a title that is dragged moves all of them
    kit.Click({262, 22}),
    kit.Wait(3),
    kit.MoveTo({20, 60}),
    kit.Wait(3),
    kit.Drag({20, 60}, {290, 330}, 10),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return ui.GraphSelectedCount(&state.graph) == 2 && ui.GraphNode(&state.graph, state.nodes[0]).selected && ui.GraphNode(&state.graph, state.nodes[1]).selected
    }, "the box selected the two nodes it touches"),
    kit.Capture("graph_box"),
    kit.MoveTo({100, 108}),
    kit.Wait(3),
    kit.Drag({100, 108}, {130, 128}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        a: ^ui.Node = ui.GraphNode(&state.graph, state.nodes[0])
        b: ^ui.Node = ui.GraphNode(&state.graph, state.nodes[1])
        return abs(a.position.x - 70) < 1 && abs(a.position.y - 70) < 1 && abs(b.position.x - 90) < 1 && abs(b.position.y - 230) < 1
    }, "dragging the title of a selected node moved both nodes by the same amount"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        port: ^ui.Port = ui.GraphPort(&state.graph, firstPort(state.nodes[0], .OUTPUT))
        return abs(port.anchor.x - (70 + 174)) < 1.5      // the pin followed it
    }, "the pins moved with the nodes"),
    kit.Click({262, 22}),
    kit.Wait(3),
    kit.Click({985, 100}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.view.origin.x > 400 }, "pressing in the minimap moved the view there"),
    // the wheel over the empty canvas zooms around the pointer: three notches out show the whole graph, the Output node too
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        state.view.origin, state.view.zoom = {}, 0
        return true
    }, "back to the start"),
    kit.Wait(3),
    kit.MoveTo({400, 500}),
    kit.Wait(3),
    kit.Scroll(-3),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(ui.GraphViewZoom(&state.view) - 0.7513) < 0.001 }, "the wheel zoomed out"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        output: ^ui.Node = ui.GraphNode(&state.graph, state.nodes[5])
        return ui.GraphNodeVisible(&state.view, output)
    }, "the Output node is in the view now"),
    kit.Capture("graph_zoom"),
    kit.Wait(1),
    // Ctrl + D: a copy of the selected nodes with the links between them, put next to them and selected
    kit.Click({400, 500}),                                // the canvas has the focus (an empty place of it)
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        ui.GraphSelectClear(&state.graph)
        ui.GraphNodeSelect(&state.graph, state.nodes[0])
        ui.GraphNodeSelect(&state.graph, state.nodes[2])
        state.before_nodes, state.before_links = ui.GraphNodeCount(&state.graph), ui.GraphLinkCount(&state.graph)
        return true
    }, "select the oscillator and the gain it feeds"),
    kit.Wait(2),
    kit.KeyDownStep(.LEFT_CTRL),
    kit.Wait(1),
    kit.Tap(.D),
    kit.Wait(2),
    kit.KeyUpStep(.LEFT_CTRL),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return ui.GraphNodeCount(&state.graph) == state.before_nodes + 2 && ui.GraphLinkCount(&state.graph) >= state.before_links + 1 && ui.GraphSelectedCount(&state.graph) == 2
    }, "Ctrl + D copied the two nodes and the link between them"),
    // a node collapsed to its title, and a reroute point on the cable to the Output node
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        ui.GraphNodeCollapse(&state.graph, state.nodes[3])
        mixer_out: ^ui.Port = ui.GraphPort(&state.graph, ui.GraphNode(&state.graph, state.nodes[4]).last_port)
        ui.GraphRerouteAdd(&state.graph, mixer_out.first_link, {690, 190})
        return true
    }, "the Filter node is collapsed and the cable from the Mixer has a reroute point"),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.GraphNode(&state.graph, state.nodes[3]).collapsed && ui.GraphNodeCount(&state.graph) == state.before_nodes + 3 }, "the reroute point is a node"),
    kit.Capture("graph_reroute"),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
