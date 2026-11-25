package ui

// A history view: the steps of an undo history as a list, the oldest at the top, the current one marked, the steps a redo would bring back dimmed. A click on a step goes there (undo or redo
// as many steps as that takes).
//
//     ui.UiTimelineHistory(&ctx, "History", &history, &timeline)         // or UiGraphHistory(&ctx, "History", &history, &graph)
//
// The steps of the timeline and graph histories have names: what the last event was ("Move clip", "Connect"), or the label a program gives to TimelineHistoryCommit(history, timeline, "Slice").
// A program with a history of its own uses `UiHistoryList` and tells the count, the current step and the name of each.
//
// Limits: a name is at most HISTORY_LABEL_MAX (32) bytes; the names come from the kind of the last event of a step (a step with several events is named by the last); no thumbnails, no branches
//     (a new edit after an undo drops the steps that a redo would bring, as the histories do), no grouping of similar steps.

HISTORY_LABEL_MAX :: 32

@(private)
historyLabelSet :: proc(label: ^[HISTORY_LABEL_MAX]u8, length: ^int, text: string) {
    length^ = min(len(text), HISTORY_LABEL_MAX)
    copy(label[:length^], text)
}

TimelineEventLabel :: proc(kind: TimelineEventKind) -> string {
    switch kind {
    case .NONE: return "Edit"
    case .TRACK_ADDED: return "Add track"
    case .TRACK_REMOVED: return "Remove track"
    case .CLIP_ADDED: return "Add clip"
    case .CLIP_REMOVED: return "Remove clip"
    case .CLIP_MOVED: return "Move clip"
    case .CLIP_RESIZED: return "Resize clip"
    case .PLAYHEAD: return "Move playhead"
    case .LOOP_CHANGED: return "Change loop"
    case .EMPTY_DOUBLE_CLICK, .RULER_DOUBLE_CLICK: return "Edit"
    case .MARKER_ADDED: return "Add marker"
    case .MARKER_REMOVED: return "Remove marker"
    case .MARKER_MOVED: return "Move marker"
    case .POINT_ADDED: return "Add point"
    case .POINT_MOVED: return "Move point"
    case .POINT_REMOVED: return "Remove point"
    case .POINT_SHAPED: return "Shape curve"
    case .TRACK_BENT: return "Bend lane"
    case .RESTORED: return "Restore"
    }
    return "Edit"
}

GraphEventLabel :: proc(kind: GraphEventKind) -> string {
    switch kind {
    case .NONE: return "Edit"
    case .CONNECTED: return "Connect"
    case .DISCONNECTED: return "Disconnect"
    case .NODE_ADDED: return "Add node"
    case .NODE_REMOVED: return "Remove node"
    case .NODE_MOVED: return "Move node"
    case .TIE_ADDED: return "Add tie"
    case .TIE_REMOVED: return "Remove tie"
    case .TIE_CHANGED: return "Change tie"
    case .NODE_COLLAPSED: return "Collapse node"
    case .LINK_LABELED: return "Label cable"
    case .RESTORED: return "Restore"
    case .DROPPED_ON_EMPTY: return "Edit"
    }
    return "Edit"
}

// The name of a step (0 is the oldest)
TimelineHistoryLabel :: proc(history: ^TimelineHistory, index: int) -> string {
    if index < 0 || index >= history.count { return "" }
    state: ^TimelineState = &history.states[(history.first + index) % len(history.states)]
    return string(state.label[:state.label_length])
}

GraphHistoryLabel :: proc(history: ^GraphHistory, index: int) -> string {
    if index < 0 || index >= history.count { return "" }
    state: ^GraphState = &history.states[(history.first + index) % len(history.states)]
    return string(state.label[:state.label_length])
}

// Goes to a step (0 is the oldest): undo or redo as many times as it takes. What was changed since the last step and not committed becomes a step first, at the end (a ring that was full
// loses its oldest then, so the indexes shift by one: read them again). False when there is no such step.
TimelineHistoryJump :: proc(history: ^TimelineHistory, timeline: ^Timeline, index: int) -> bool {
    TimelineHistoryCommit(history, timeline)
    if index < 0 || index >= history.count { return false }
    if index != history.current { timelineHistoryGo(history, timeline, index) }
    return true
}

GraphHistoryJump :: proc(history: ^GraphHistory, graph: ^Graph, index: int) -> bool {
    GraphHistoryCommit(history, graph)
    if index < 0 || index >= history.count { return false }
    if index != history.current { graphHistoryGo(history, graph, index) }
    return true
}

HistoryLabelProc :: proc(user: rawptr, index: int) -> string

// The list. `current` is the step now (0 is the oldest of `count`). Returns the step that was clicked, -1 for none. Ids of the rows are their index under the list's own.
UiHistoryList :: proc(ctx: ^Context, name: string, count: int, current: int, label_of: HistoryLabelProc, user: rawptr, visible_rows: int = 8, size: Size = {}) -> (clicked: int) {
    clicked = -1
    metrics: ^Metrics = &ctx.style.metrics
    row_height: f32 = metrics.control_height * 0.85
    height: f32 = (row_height + 2) * f32(visible_rows) + 8
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    // the current step stays in view when it changes (an undo by the keys, a new step)
    mark: f32 = f32(current) * 4096 + f32(count)
    if mark != state.anim {
        state.anim = mark
        UiScrollSet(ctx, id, max((f32(current) + 1) * (row_height + 2) + 4 - height, 0))
    }
    if UiScroll(ctx, name, widgetSizeOr(size, Fixed(metrics.control_width * 1.4), Fixed(height)), {padding = PaddingAll(4), gap = 2}) {
        for index in 0 ..< count {
            row: Id = IdFromIndex(u32(index), id)
            _ = stateGet(ctx, row)
            interaction: Interaction = widgetBehavior(ctx, row)
            if interaction.clicked { clicked = index }
            flags: Flags = {}
            if index == current { flags += {.SELECTED} }
            if index > current { flags += {.DISABLED} }          // what a redo would bring: dim, still clickable
            ElementOpen(ctx, {
                id = row,
                layout = {size = {Grow(), Fixed(row_height)}},
                hit = {.INTERACTIVE},
                draw = {kind = .SELECTABLE, name = label_of(user, index), font_size = metrics.font_size, flags = flags, value = f32(index)},
            })
            ElementClose(ctx)
        }
    }
    return
}

@(private)
timelineHistoryLabelOf :: proc(user: rawptr, index: int) -> string {
    return TimelineHistoryLabel(cast(^TimelineHistory)user, index)
}

@(private)
graphHistoryLabelOf :: proc(user: rawptr, index: int) -> string {
    return GraphHistoryLabel(cast(^GraphHistory)user, index)
}

// The list of a timeline history, and the jump when a step is clicked: true in the frame it jumped
UiTimelineHistory :: proc(ctx: ^Context, name: string, history: ^TimelineHistory, timeline: ^Timeline, visible_rows: int = 8, size: Size = {}) -> (jumped: bool) {
    clicked: int = UiHistoryList(ctx, name, history.count, history.current, timelineHistoryLabelOf, history, visible_rows, size)
    if clicked >= 0 { jumped = TimelineHistoryJump(history, timeline, clicked) }
    return
}

UiGraphHistory :: proc(ctx: ^Context, name: string, history: ^GraphHistory, graph: ^Graph, visible_rows: int = 8, size: Size = {}) -> (jumped: bool) {
    clicked: int = UiHistoryList(ctx, name, history.count, history.current, graphHistoryLabelOf, history, visible_rows, size)
    if clicked >= 0 { jumped = GraphHistoryJump(history, graph, clicked) }
    return
}
