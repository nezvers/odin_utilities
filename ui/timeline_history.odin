package ui

import "core:mem"

// Undo and redo of a timeline: a ring of snapshots of what the person edits (tracks, clips, markers, points, the selection), in storage that the program provides, so nothing grows
// and the cost is known: a snapshot is the size of TimelineState (the handle maps, about 100 bytes per possible clip or point: set TIMELINE_CLIPS and TIMELINE_POINTS to what the
// program needs). A snapshot is a copy of the whole state, so the handles of everything that an undo brings back are the old ones and every handle a program kept stays right.
//
//   states: [32]ui.TimelineState                                  // or a slice of the heap, made once
//   history: ui.TimelineHistory
//   ui.TimelineHistoryInit(&history, states[:], &timeline)        // the state now is the first one
//   view.history = &history                                       // UiTimeline commits when a gesture or an action is finished and takes Ctrl + Z and Ctrl + Y
//
// A program that edits the model itself calls TimelineHistoryCommit after an edit (it does nothing when nothing changed: it compares the counter of the events).

TimelineState :: struct {
    tracks: type_of(Timeline{}.tracks),
    clips: type_of(Timeline{}.clips),
    markers: type_of(Timeline{}.markers),
    points: type_of(Timeline{}.points),
    order: [TIMELINE_TRACKS]TrackHandle,
    track_count: int,
    label: [HISTORY_LABEL_MAX]u8,       // what the step was (history_view.odin)
    label_length: int,
}

TimelineHistory :: struct {
    states: []TimelineState,
    first: int,                 // where the oldest one is in the ring
    count: int,
    current: int,               // 0 is the oldest, count - 1 the newest
    serial: u64,                // the timeline.serial of the state that is current
}

@(private)
timelineStateSave :: proc(timeline: ^Timeline, state: ^TimelineState) {
    // byte copies: an assignment of a handle map of this size goes through a temporary on the stack, and the stack of a thread is small
    mem.copy(&state.tracks, &timeline.tracks, size_of(state.tracks))
    mem.copy(&state.clips, &timeline.clips, size_of(state.clips))
    mem.copy(&state.markers, &timeline.markers, size_of(state.markers))
    mem.copy(&state.points, &timeline.points, size_of(state.points))
    state.order, state.track_count = timeline.order, timeline.track_count
}

@(private)
timelineStateLoad :: proc(timeline: ^Timeline, state: ^TimelineState) {
    mem.copy(&timeline.tracks, &state.tracks, size_of(state.tracks))
    mem.copy(&timeline.clips, &state.clips, size_of(state.clips))
    mem.copy(&timeline.markers, &state.markers, size_of(state.markers))
    mem.copy(&timeline.points, &state.points, size_of(state.points))
    timeline.order, timeline.track_count = state.order, state.track_count
}

// Starts a history in `storage` (two states at least: the one now and one to go back to). The state of the timeline now is where undo stops.
TimelineHistoryInit :: proc(history: ^TimelineHistory, storage: []TimelineState, timeline: ^Timeline) {
    assert(len(storage) >= 2)
    history^ = {states = storage}
    timelineStateSave(timeline, &history.states[0])
    historyLabelSet(&history.states[0].label, &history.states[0].label_length, "Start")
    history.count, history.serial = 1, timeline.serial
}

// Makes the state now a step of the history, when something changed since the last one: the steps after the current one (what a redo would bring) are dropped, and when the storage is
// full the oldest step goes. True when a step was made.
TimelineHistoryCommit :: proc(history: ^TimelineHistory, timeline: ^Timeline, label: string = "") -> bool {
    if len(history.states) == 0 || timeline.serial == history.serial { return false }
    history.count = history.current + 1
    if history.count == len(history.states) {
        history.first = (history.first + 1) % len(history.states)
        history.count -= 1
    }
    made: ^TimelineState = &history.states[(history.first + history.count) % len(history.states)]
    timelineStateSave(timeline, made)
    historyLabelSet(&made.label, &made.label_length, label if label != "" else TimelineEventLabel(timeline.last_event))
    history.count += 1
    history.current = history.count - 1
    history.serial = timeline.serial
    return true
}

TimelineHistoryCanUndo :: proc(history: ^TimelineHistory) -> bool {
    return history.current > 0
}

TimelineHistoryCanRedo :: proc(history: ^TimelineHistory) -> bool {
    return history.current + 1 < history.count
}

@(private)
timelineHistoryGo :: proc(history: ^TimelineHistory, timeline: ^Timeline, target: int) {
    history.current = target
    timelineStateLoad(timeline, &history.states[(history.first + target) % len(history.states)])
    timelineEmit(timeline, {kind = .RESTORED})
    history.serial = timeline.serial
}

// Goes back one step. What was changed since the last step and not committed is committed first (so a redo brings it back). False at the oldest step.
TimelineHistoryUndo :: proc(history: ^TimelineHistory, timeline: ^Timeline) -> bool {
    TimelineHistoryCommit(history, timeline)
    if !TimelineHistoryCanUndo(history) { return false }
    timelineHistoryGo(history, timeline, history.current - 1)
    return true
}

TimelineHistoryRedo :: proc(history: ^TimelineHistory, timeline: ^Timeline) -> bool {
    if !TimelineHistoryCanRedo(history) { return false }
    timelineHistoryGo(history, timeline, history.current + 1)
    return true
}

