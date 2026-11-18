package ui

// The model of a timeline: tracks (rows) with clips on them (a start and a length in the unit of the program: seconds, beats, samples), the rules that say where a clip may
// be, and the news of every change. It knows nothing of drawing: the widget in timeline_widgets.odin draws it and changes it with the pointer, a program (an audio engine
// that plays the clips, a video editor) reads it. Fixed storage in the Timeline (sizes are `#config`), checked handles (a handle of something that is gone is refused, never
// another thing), nothing allocates.
//
//   timeline: ui.Timeline                                          // big: a global or a heap allocation
//   ui.TimelineInit(&timeline)
//   drums, _ := ui.TimelineTrackAdd(&timeline, "Drums", user = &drum_channel)
//   clip, _ := ui.TimelineClipAdd(&timeline, drums, start = 4, length = 8, name = "Loop A", user = &loop_a)
//   ui.TimelineClipPlace(&timeline, clip, drums, 12, 8)             // the rules decide: false when the clip may not be there
//   for { event := ui.TimelinePollEvent(&timeline) or_break; ... }  // or timeline.on_event, with the context of the program
//
// A program that plays the clips asks for the clips of a track in the order of their start (`TimelineTrackClips`) and keeps its own copy while the person edits.

import hm "core:container/handle_map"

TIMELINE_TRACKS :: #config(TIMELINE_TRACKS, 64)
TIMELINE_CLIPS :: #config(TIMELINE_CLIPS, 4096)
TIMELINE_EVENTS :: #config(TIMELINE_EVENTS, 256)
TIMELINE_NAME_MAX :: 48

TrackHandle :: distinct hm.Handle32
ClipHandle :: distinct hm.Handle32

TrackFlag :: enum u8 {
    MUTED,              // drawn faint, the program does not play it
    LOCKED,             // no clip is moved, resized or put on it by the pointer
}
TrackFlags :: bit_set[TrackFlag; u8]

TimelineTrack :: struct {
    handle: TrackHandle,
    name: [TIMELINE_NAME_MAX]u8,
    name_length: int,
    color: Color,               // alpha 0: the style's own
    user: rawptr,               // of the program: it comes back in the events (a channel, a mixer strip)
    height: f32,                // 0: the height of the style
    flags: TrackFlags,
    clip_count: int,
}

TimelineClip :: struct {
    handle: ClipHandle,
    track: TrackHandle,
    start: f64,
    length: f64,
    name: [TIMELINE_NAME_MAX]u8,
    name_length: int,
    color: Color,
    user: rawptr,               // of the program (an audio file, a pattern)
    selected: bool,
    drag_start: f64,            // where the clip was when a drag began (timeline_widgets.odin)
    drag_length: f64,
    drag_track: int,
}

TimelineEventKind :: enum u8 {
    NONE,
    TRACK_ADDED,
    TRACK_REMOVED,
    CLIP_ADDED,
    CLIP_REMOVED,
    CLIP_MOVED,         // another track or another start, the same length
    CLIP_RESIZED,       // another length (and start, when the left edge was dragged)
    PLAYHEAD,           // the person put the playhead somewhere (`time`)
    EMPTY_DOUBLE_CLICK, // a double click on an empty place of a track (`track`, `time`): a program may make a clip there
}

// What happened, with the user pointers of the clip, its track and the timeline, and what it was before (for an undo).
TimelineEvent :: struct {
    kind: TimelineEventKind,
    clip: ClipHandle,
    track: TrackHandle,
    previous_track: TrackHandle,
    start: f64,
    length: f64,
    previous_start: f64,
    previous_length: f64,
    time: f64,
    clip_user: rawptr,
    track_user: rawptr,
    timeline_user: rawptr,
}

TimelineEventProc :: proc(timeline: ^Timeline, event: ^TimelineEvent)

// Says if a clip may be at a place (the pointer asks while a clip is dragged; the clip keeps its last good place when the answer is no). `clip` is nil for a clip that is being added.
TimelineCanPlaceProc :: proc(timeline: ^Timeline, clip: ^TimelineClip, track: TrackHandle, start: f64, length: f64, user: rawptr) -> bool

TimelineRules :: struct {
    can_place: TimelineCanPlaceProc,        // nil: everywhere
    min_length: f64,                        // the shortest a clip may be (0: any length above 0)
    user: rawptr,
}

Timeline :: struct {
    tracks: hm.Static_Handle_Map(TIMELINE_TRACKS, TimelineTrack, TrackHandle),
    clips: hm.Static_Handle_Map(TIMELINE_CLIPS, TimelineClip, ClipHandle),
    order: [TIMELINE_TRACKS]TrackHandle,    // the tracks from the top
    track_count: int,
    rules: TimelineRules,
    user: rawptr,
    on_event: TimelineEventProc,
    events: [TIMELINE_EVENTS]TimelineEvent,
    event_head: int,
    event_count: int,
    events_lost: int,
    serial: u64,                            // counts the events ever made: a widget sees that something changed by comparing it
}

TimelineInit :: proc(timeline: ^Timeline, user: rawptr = nil) {
    timeline^ = {}
    timeline.user = user
}

// The clip of a handle, nil when it is gone.
TimelineClipGet :: proc(timeline: ^Timeline, handle: ClipHandle) -> ^TimelineClip {
    if handle == {} { return nil }
    item, ok := hm.get(&timeline.clips, handle)
    return item if ok else nil
}

// The track of a handle, nil when it is gone.
TimelineTrackGet :: proc(timeline: ^Timeline, handle: TrackHandle) -> ^TimelineTrack {
    if handle == {} { return nil }
    item, ok := hm.get(&timeline.tracks, handle)
    return item if ok else nil
}

TimelineTrackName :: proc(track: ^TimelineTrack) -> string {
    return string(track.name[:track.name_length])
}

TimelineClipName :: proc(clip: ^TimelineClip) -> string {
    return string(clip.name[:clip.name_length])
}

TimelineClipCount :: proc(timeline: ^Timeline) -> int {
    return int(hm.len(timeline.clips))
}

@(private)
timelineName :: proc(buffer: []u8, length: ^int, text: string) {
    count: int = min(len(text), len(buffer))
    copy(buffer[:count], text[:count])
    length^ = count
}

@(private)
timelineEmit :: proc(timeline: ^Timeline, event: TimelineEvent) {
    stored: TimelineEvent = event
    timeline.serial += 1
    stored.timeline_user = timeline.user
    if clip := TimelineClipGet(timeline, event.clip); clip != nil { stored.clip_user = clip.user }
    if track := TimelineTrackGet(timeline, event.track); track != nil { stored.track_user = track.user }
    if timeline.event_count == len(timeline.events) {
        timeline.event_head = (timeline.event_head + 1) % len(timeline.events)
        timeline.event_count -= 1
        timeline.events_lost += 1
    }
    timeline.events[(timeline.event_head + timeline.event_count) % len(timeline.events)] = stored
    timeline.event_count += 1
    if timeline.on_event != nil { timeline.on_event(timeline, &stored) }
}

// The oldest event nobody has read.
TimelinePollEvent :: proc(timeline: ^Timeline) -> (event: TimelineEvent, ok: bool) {
    if timeline.event_count == 0 { return }
    event = timeline.events[timeline.event_head]
    timeline.event_head = (timeline.event_head + 1) % len(timeline.events)
    timeline.event_count -= 1
    return event, true
}

// A track at the bottom. `height` 0: the height of the style.
TimelineTrackAdd :: proc(timeline: ^Timeline, name: string, height: f32 = 0, user: rawptr = nil, color: Color = {}) -> (handle: TrackHandle, ok: bool) {
    if timeline.track_count >= len(timeline.order) { return }
    track: TimelineTrack = {height = height, user = user, color = color}
    timelineName(track.name[:], &track.name_length, name)
    handle, ok = hm.add(&timeline.tracks, track)
    if !ok { return }
    timeline.order[timeline.track_count] = handle
    timeline.track_count += 1
    timelineEmit(timeline, {kind = .TRACK_ADDED, track = handle})
    return
}

// The place of a track from the top, -1 when it is gone.
TimelineTrackIndex :: proc(timeline: ^Timeline, handle: TrackHandle) -> int {
    for i in 0 ..< timeline.track_count {
        if timeline.order[i] == handle { return i }
    }
    return -1
}

// Removes a track and its clips (every clip is told about).
TimelineTrackRemove :: proc(timeline: ^Timeline, handle: TrackHandle) -> bool {
    index: int = TimelineTrackIndex(timeline, handle)
    if index < 0 { return false }
    for removed := true; removed; {
        removed = false
        it := hm.iterator_make(&timeline.clips)
        for clip, clip_handle in hm.iterate(&it) {
            if clip.track == handle {
                TimelineClipRemove(timeline, clip_handle)
                removed = true
                break
            }
        }
    }
    timelineEmit(timeline, {kind = .TRACK_REMOVED, track = handle})
    for i in index ..< timeline.track_count - 1 { timeline.order[i] = timeline.order[i + 1] }
    timeline.track_count -= 1
    timeline.order[timeline.track_count] = {}
    hm.remove(&timeline.tracks, handle)
    return true
}

// A clip on a track. False when the track is gone, the length is not above the minimum, the storage is full or the rules say no.
TimelineClipAdd :: proc(timeline: ^Timeline, track: TrackHandle, start: f64, length: f64, name: string, user: rawptr = nil, color: Color = {}) -> (handle: ClipHandle, ok: bool) {
    owner: ^TimelineTrack = TimelineTrackGet(timeline, track)
    if owner == nil || length <= 0 || length < timeline.rules.min_length { return }
    if timeline.rules.can_place != nil && !timeline.rules.can_place(timeline, nil, track, start, length, timeline.rules.user) { return }
    clip: TimelineClip = {track = track, start = start, length = length, user = user, color = color}
    timelineName(clip.name[:], &clip.name_length, name)
    handle, ok = hm.add(&timeline.clips, clip)
    if !ok { return }
    owner.clip_count += 1
    timelineEmit(timeline, {kind = .CLIP_ADDED, clip = handle, track = track, start = start, length = length})
    return
}

TimelineClipRemove :: proc(timeline: ^Timeline, handle: ClipHandle) -> bool {
    clip: ^TimelineClip = TimelineClipGet(timeline, handle)
    if clip == nil { return false }
    event: TimelineEvent = {kind = .CLIP_REMOVED, clip = handle, track = clip.track, start = clip.start, length = clip.length}
    owner: ^TimelineTrack = TimelineTrackGet(timeline, clip.track)
    if owner != nil { owner.clip_count -= 1 }
    timelineEmit(timeline, event)
    hm.remove(&timeline.clips, handle)
    return true
}

// Puts a clip on a track at a start with a length, if the rules allow it (and the track exists and the length is long enough). One event: CLIP_MOVED when the length is the same, else CLIP_RESIZED.
// False and nothing changed when it may not be there.
TimelineClipPlace :: proc(timeline: ^Timeline, handle: ClipHandle, track: TrackHandle, start: f64, length: f64) -> bool {
    clip: ^TimelineClip = TimelineClipGet(timeline, handle)
    owner: ^TimelineTrack = TimelineTrackGet(timeline, track)
    if clip == nil || owner == nil || length <= 0 || length < timeline.rules.min_length || start < 0 { return false }
    if clip.track == track && clip.start == start && clip.length == length { return true }
    if timeline.rules.can_place != nil && !timeline.rules.can_place(timeline, clip, track, start, length, timeline.rules.user) { return false }
    event: TimelineEvent = {
        kind = .CLIP_RESIZED if length != clip.length else .CLIP_MOVED, clip = handle, track = track, previous_track = clip.track,
        start = start, length = length, previous_start = clip.start, previous_length = clip.length,
    }
    if clip.track != track {
        if previous := TimelineTrackGet(timeline, clip.track); previous != nil { previous.clip_count -= 1 }
        owner.clip_count += 1
        clip.track = track
    }
    clip.start, clip.length = start, length
    timelineEmit(timeline, event)
    return true
}

TimelineClipSelect :: proc(timeline: ^Timeline, handle: ClipHandle, selected: bool = true) {
    if clip := TimelineClipGet(timeline, handle); clip != nil { clip.selected = selected }
}

TimelineSelectClear :: proc(timeline: ^Timeline) {
    it := hm.iterator_make(&timeline.clips)
    for clip, _ in hm.iterate(&it) { clip.selected = false }
}

TimelineSelectedCount :: proc(timeline: ^Timeline) -> (count: int) {
    it := hm.iterator_make(&timeline.clips)
    for clip, _ in hm.iterate(&it) {
        if clip.selected { count += 1 }
    }
    return
}

// The end of the last clip: where the timeline stops.
TimelineEnd :: proc(timeline: ^Timeline) -> (end: f64) {
    it := hm.iterator_make(&timeline.clips)
    for clip, _ in hm.iterate(&it) { end = max(end, clip.start + clip.length) }
    return
}

// The clips of a track in the order of their start, into `out` (as many as fit): how many. For the program that plays them.
TimelineTrackClips :: proc(timeline: ^Timeline, track: TrackHandle, out: []ClipHandle) -> int {
    count: int
    it := hm.iterator_make(&timeline.clips)
    for clip, handle in hm.iterate(&it) {
        if clip.track != track || count >= len(out) { continue }
        position: int = count
        for position > 0 && TimelineClipGet(timeline, out[position - 1]).start > clip.start {
            out[position] = out[position - 1]
            position -= 1
        }
        out[position] = handle
        count += 1
    }
    return count
}

// The clip that holds a time on a track (the one that starts last when they overlap), none when there is none.
TimelineClipAt :: proc(timeline: ^Timeline, track: TrackHandle, time: f64) -> (found: ClipHandle) {
    latest: f64 = -1
    it := hm.iterator_make(&timeline.clips)
    for clip, handle in hm.iterate(&it) {
        if clip.track == track && time >= clip.start && time < clip.start + clip.length && clip.start > latest {
            latest = clip.start
            found = handle
        }
    }
    return
}

// A rule for `TimelineRules.can_place`: clips of a track do not overlap.
TimelineRuleNoOverlap :: proc(timeline: ^Timeline, clip: ^TimelineClip, track: TrackHandle, start: f64, length: f64, user: rawptr) -> bool {
    it := hm.iterator_make(&timeline.clips)
    for other, _ in hm.iterate(&it) {
        if other.track != track || other == clip { continue }
        if start < other.start + other.length && other.start < start + length { return false }
    }
    return true
}
