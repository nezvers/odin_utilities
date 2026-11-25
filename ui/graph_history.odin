package ui

import "core:mem"

// Undo and redo of a graph: a ring of snapshots of the nodes, ports, links and zip ties, in storage that the program provides, so nothing grows and the cost is known: a snapshot is
// the size of GraphState (set GRAPH_NODES, GRAPH_PORTS, GRAPH_LINKS and GRAPH_TIES to what the program needs). A snapshot is a copy of the whole state, so the handles of everything
// that an undo brings back are the old ones and every handle a program kept stays right. Same shape as the history of the timeline.
//
//   states: [16]ui.GraphState                                    // or a slice of the heap, made once
//   history: ui.GraphHistory
//   ui.GraphHistoryInit(&history, states[:], &graph)             // the state now is the first one
//   view.history = &history                                      // UiGraph commits when a gesture or an action is finished and takes Ctrl + Z and Ctrl + Y
//
// A program that edits the model itself calls GraphHistoryCommit after an edit (it does nothing when nothing changed: it compares the counter of the changes). The data a program keeps
// for its nodes (behind `user`) is not part of a snapshot: the program hears RESTORED and brings it in line with the nodes that are there.

GraphState :: struct {
    nodes: type_of(Graph{}.nodes),
    ports: type_of(Graph{}.ports),
    links: type_of(Graph{}.links),
    ties: type_of(Graph{}.ties),
    z_counter: i16,
    label: [HISTORY_LABEL_MAX]u8,       // what the step was (history_view.odin)
    label_length: int,
}

GraphHistory :: struct {
    states: []GraphState,
    first: int,                 // where the oldest one is in the ring
    count: int,
    current: int,               // 0 is the oldest, count - 1 the newest
    serial: u64,                // the graph.serial of the state that is current
}

@(private)
graphStateSave :: proc(graph: ^Graph, state: ^GraphState) {
    // byte copies: an assignment of a handle map of this size goes through a temporary on the stack, and the stack of a thread is small
    mem.copy(&state.nodes, &graph.nodes, size_of(state.nodes))
    mem.copy(&state.ports, &graph.ports, size_of(state.ports))
    mem.copy(&state.links, &graph.links, size_of(state.links))
    mem.copy(&state.ties, &graph.ties, size_of(state.ties))
    state.z_counter = graph.z_counter
}

@(private)
graphStateLoad :: proc(graph: ^Graph, state: ^GraphState) {
    mem.copy(&graph.nodes, &state.nodes, size_of(state.nodes))
    mem.copy(&graph.ports, &state.ports, size_of(state.ports))
    mem.copy(&graph.links, &state.links, size_of(state.links))
    mem.copy(&graph.ties, &state.ties, size_of(state.ties))
    graph.z_counter = state.z_counter
}

// Starts a history in `storage` (two states at least: the one now and one to go back to). The state of the graph now is where undo stops.
GraphHistoryInit :: proc(history: ^GraphHistory, storage: []GraphState, graph: ^Graph) {
    assert(len(storage) >= 2)
    history^ = {states = storage}
    graphStateSave(graph, &history.states[0])
    historyLabelSet(&history.states[0].label, &history.states[0].label_length, "Start")
    history.count, history.serial = 1, graph.serial
}

// Makes the state now a step of the history, when something changed since the last one: the steps after the current one (what a redo would bring) are dropped, and when the storage is
// full the oldest step goes. True when a step was made.
GraphHistoryCommit :: proc(history: ^GraphHistory, graph: ^Graph, label: string = "") -> bool {
    if len(history.states) == 0 || graph.serial == history.serial { return false }
    history.count = history.current + 1
    if history.count == len(history.states) {
        history.first = (history.first + 1) % len(history.states)
        history.count -= 1
    }
    made: ^GraphState = &history.states[(history.first + history.count) % len(history.states)]
    graphStateSave(graph, made)
    historyLabelSet(&made.label, &made.label_length, label if label != "" else GraphEventLabel(graph.last_event))
    history.count += 1
    history.current = history.count - 1
    history.serial = graph.serial
    return true
}

GraphHistoryCanUndo :: proc(history: ^GraphHistory) -> bool {
    return history.current > 0
}

GraphHistoryCanRedo :: proc(history: ^GraphHistory) -> bool {
    return history.current + 1 < history.count
}

@(private)
graphHistoryGo :: proc(history: ^GraphHistory, graph: ^Graph, target: int) {
    history.current = target
    graphStateLoad(graph, &history.states[(history.first + target) % len(history.states)])
    graphEmit(graph, {kind = .RESTORED})
    history.serial = graph.serial
}

// Goes back one step. What was changed since the last step and not committed is committed first (so a redo brings it back). False at the oldest step.
GraphHistoryUndo :: proc(history: ^GraphHistory, graph: ^Graph) -> bool {
    GraphHistoryCommit(history, graph)
    if !GraphHistoryCanUndo(history) { return false }
    graphHistoryGo(history, graph, history.current - 1)
    return true
}

GraphHistoryRedo :: proc(history: ^GraphHistory, graph: ^Graph) -> bool {
    if !GraphHistoryCanRedo(history) { return false }
    graphHistoryGo(history, graph, history.current + 1)
    return true
}
