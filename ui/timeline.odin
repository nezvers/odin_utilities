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
TIMELINE_MARKERS :: #config(TIMELINE_MARKERS, 256)
TIMELINE_POINTS :: #config(TIMELINE_POINTS, 8192)           // the points of all the automation lanes together
TIMELINE_COPIES :: #config(TIMELINE_COPIES, 256)             // the clips one copy can hold
TIMELINE_POINT_COPIES :: #config(TIMELINE_POINT_COPIES, 1024)  // the points one copy can hold
TIMELINE_NAME_MAX :: 48

TrackHandle :: distinct hm.Handle32
ClipHandle :: distinct hm.Handle32
MarkerHandle :: distinct hm.Handle32
PointHandle :: distinct hm.Handle32

TrackFlag :: enum u8 {
    MUTED,              // drawn faint, the program does not play it
    LOCKED,             // no clip is moved, resized or put on it by the pointer
}
TrackFlags :: bit_set[TrackFlag; u8]

// What a track holds: clips, or the points of an automation (a value that changes in time: a volume, a filter).
TrackKind :: enum u8 {
    CLIPS,
    AUTOMATION,
}

TimelineTrack :: struct {
    handle: TrackHandle,
    kind: TrackKind,
    value_min: f32,             // an automation track: the lowest and the highest value of its points, the bottom and the top of its lane
    value_max: f32,
    steps: bool,                // an automation track: the value is held until the next point (else it goes straight to it)
    bend_rise: f32,             // an automation track: added to the `curve` of every CURVE, S_CURVE and EXP segment that goes up (-1 .. 1), a macro for the feel of all the curves of the lane
    bend_fall: f32,             // and the same for the segments that go down: a snappy attack with a long release is bend_rise above 0 and bend_fall below
    point_count: int,
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
    drag_selected: bool,        // was it selected when a box was started (Shift keeps those)
    drag_start: f64,            // where the clip was when a drag began (timeline_widgets.odin)
    drag_length: f64,
    drag_track: int,
}

// A named point of time: a flag on the ruler with a line down through the tracks.
// A point of an automation track: at a time, with a value in the range of the track.
TimelinePoint :: struct {
    handle: PointHandle,
    track: TrackHandle,
    time: f64,
    value: f32,
    shape: CurveShape,          // the shape of the curve from this point to the next one (a point has none after it: the last value is held)
    curve: f32,                 // -1 .. 1: how bent CURVE and S_CURVE are (see timeline_curve.odin)
    tangent_in: f32,            // HERMITE: the slope with which the curve arrives at this point and leaves it (0 .. TANGENT_LIMIT, as a part of the slope of the straight line): 0 and 0 is a smooth step
    tangent_out: f32,
    selected: bool,
    drag_selected: bool,
    drag_time: f64,             // where it was when a drag began (timeline_widgets.odin)
    drag_value: f32,
    drag_curve: f32,
}

TimelineMarker :: struct {
    handle: MarkerHandle,
    time: f64,
    name: [TIMELINE_NAME_MAX]u8,
    name_length: int,
    color: Color,               // alpha 0: the style's own
    user: rawptr,
    selected: bool,
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
    LOOP_CHANGED,       // the person made or changed the loop range (`start`, `length`)
    EMPTY_DOUBLE_CLICK, // a double click on an empty place of a track (`track`, `time`): a program may make a clip there
    RULER_DOUBLE_CLICK, // a double click on the ruler (`time`): a program may put a marker there
    MARKER_ADDED,
    MARKER_REMOVED,
    MARKER_MOVED,       // `time` is the new time, `previous_start` the old one
    POINT_ADDED,        // an automation point: `point`, `track`, `time`, `value`
    POINT_MOVED,        // the new `time` and `value`, and `previous_start` and `previous_value`
    POINT_REMOVED,
    POINT_SHAPED,       // the curve after a point changed: `shape` and `curve` (and what they were)
    TRACK_BENT,         // the bend macro of an automation track changed: `value` is the new bend of the rising segments, `curve` of the falling ones
    RESTORED,           // an undo or a redo replaced everything (see timeline_history.odin): read the timeline again, the handles of things that came back are the old ones
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
    marker: MarkerHandle,
    marker_user: rawptr,
    point: PointHandle,
    value: f32,
    previous_value: f32,
    shape: CurveShape,
    previous_shape: CurveShape,
    curve: f32,
    previous_curve: f32,
    tangent_in: f32,            // POINT_SHAPED: the tangents after and before
    tangent_out: f32,
    previous_tangent_in: f32,
    previous_tangent_out: f32,
    copied_from: ClipHandle,    // CLIP_ADDED by a paste: the clip it is a copy of (the handle may be gone when it was cut): a program that keeps data for a clip makes its own copy of it now
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

// One clip of the copy: where it was, relative to the earliest start and the top track of the copied clips.
@(private)
TimelineCopyEntry :: struct {
    source: ClipHandle,
    track_offset: int,
    start_offset: f64,
    length: f64,
    name: [TIMELINE_NAME_MAX]u8,
    name_length: int,
    color: Color,
    user: rawptr,
}

// One point of the copy: where it was, relative to the earliest time and the top lane of the copied points.
@(private)
TimelinePointCopy :: struct {
    track_offset: int,
    time_offset: f64,
    value: f32,
    shape: CurveShape,
    curve: f32,
    tangent_in: f32,
    tangent_out: f32,
}

Timeline :: struct {
    tracks: hm.Static_Handle_Map(TIMELINE_TRACKS, TimelineTrack, TrackHandle),
    clips: hm.Static_Handle_Map(TIMELINE_CLIPS, TimelineClip, ClipHandle),
    markers: hm.Static_Handle_Map(TIMELINE_MARKERS, TimelineMarker, MarkerHandle),
    points: hm.Static_Handle_Map(TIMELINE_POINTS, TimelinePoint, PointHandle),
    order: [TIMELINE_TRACKS]TrackHandle,    // the tracks from the top
    track_count: int,
    rules: TimelineRules,
    user: rawptr,
    copies: [TIMELINE_COPIES]TimelineCopyEntry,        // the copied clips (TimelineCopy)
    copy_count: int,
    point_copies: [TIMELINE_POINT_COPIES]TimelinePointCopy,   // the copied points (TimelineCopyPoints)
    point_copy_count: int,
    point_copy_top_track: int,
    copy_is_points: bool,       // what was copied last: points (a paste puts points back) or clips
    copy_top_track: int,        // the place of the top track of the copied clips when they were copied
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
    if marker := TimelineMarkerGet(timeline, event.marker); marker != nil { stored.marker_user = marker.user }
    if point := TimelinePointGet(timeline, event.point); point != nil && stored.track == {} {
        stored.track = point.track
        if track := TimelineTrackGet(timeline, point.track); track != nil { stored.track_user = track.user }
    }
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
    for removed := true; removed; {
        removed = false
        points := hm.iterator_make(&timeline.points)
        for point, point_handle in hm.iterate(&points) {
            if point.track == handle {
                TimelinePointRemove(timeline, point_handle)
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
    if owner == nil || owner.kind != .CLIPS || length <= 0 || length < timeline.rules.min_length { return }
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
    if clip == nil || owner == nil || owner.kind != .CLIPS || length <= 0 || length < timeline.rules.min_length || start < 0 { return false }
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

// Nothing is selected: no clip, no marker, no point.
TimelineSelectClear :: proc(timeline: ^Timeline) {
    it := hm.iterator_make(&timeline.clips)
    for clip, _ in hm.iterate(&it) { clip.selected = false }
    markers := hm.iterator_make(&timeline.markers)
    for marker, _ in hm.iterate(&markers) { marker.selected = false }
    points := hm.iterator_make(&timeline.points)
    for point, _ in hm.iterate(&points) { point.selected = false }
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
    points := hm.iterator_make(&timeline.points)
    for point, _ in hm.iterate(&points) { end = max(end, point.time) }
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

// ------------------------------------------------------------------------------------------------------------------------
// Markers

TimelineMarkerGet :: proc(timeline: ^Timeline, handle: MarkerHandle) -> ^TimelineMarker {
    if handle == {} { return nil }
    item, ok := hm.get(&timeline.markers, handle)
    return item if ok else nil
}

TimelineMarkerName :: proc(marker: ^TimelineMarker) -> string {
    return string(marker.name[:marker.name_length])
}

TimelineMarkerCount :: proc(timeline: ^Timeline) -> int {
    return int(hm.len(timeline.markers))
}

TimelineMarkerAdd :: proc(timeline: ^Timeline, time: f64, name: string, user: rawptr = nil, color: Color = {}) -> (handle: MarkerHandle, ok: bool) {
    if time < 0 { return }
    marker: TimelineMarker = {time = time, user = user, color = color}
    timelineName(marker.name[:], &marker.name_length, name)
    handle, ok = hm.add(&timeline.markers, marker)
    if !ok { return }
    timelineEmit(timeline, {kind = .MARKER_ADDED, marker = handle, time = time})
    return
}

// Moves a marker (not before the start). False when it is gone or the time is below 0.
TimelineMarkerMove :: proc(timeline: ^Timeline, handle: MarkerHandle, time: f64) -> bool {
    marker: ^TimelineMarker = TimelineMarkerGet(timeline, handle)
    if marker == nil || time < 0 { return false }
    if marker.time == time { return true }
    previous: f64 = marker.time
    marker.time = time
    timelineEmit(timeline, {kind = .MARKER_MOVED, marker = handle, time = time, previous_start = previous})
    return true
}

TimelineMarkerRemove :: proc(timeline: ^Timeline, handle: MarkerHandle) -> bool {
    marker: ^TimelineMarker = TimelineMarkerGet(timeline, handle)
    if marker == nil { return false }
    timelineEmit(timeline, {kind = .MARKER_REMOVED, marker = handle, time = marker.time})
    hm.remove(&timeline.markers, handle)
    return true
}

// ------------------------------------------------------------------------------------------------------------------------
// Copy and paste

// Copies the selected clips (as many as TIMELINE_COPIES) into the copy of the timeline, in place of what was there. How many.
TimelineCopy :: proc(timeline: ^Timeline) -> int {
    timeline.copy_count = 0
    earliest: f64 = f64(INFINITE)
    top: int = timeline.track_count
    it := hm.iterator_make(&timeline.clips)
    for clip, _ in hm.iterate(&it) {
        if !clip.selected { continue }
        earliest = min(earliest, clip.start)
        top = min(top, TimelineTrackIndex(timeline, clip.track))
    }
    timeline.copy_top_track = top
    it = hm.iterator_make(&timeline.clips)
    for clip, handle in hm.iterate(&it) {
        if !clip.selected || timeline.copy_count >= len(timeline.copies) { continue }
        entry: ^TimelineCopyEntry = &timeline.copies[timeline.copy_count]
        entry^ = {source = handle, track_offset = TimelineTrackIndex(timeline, clip.track) - top, start_offset = clip.start - earliest, length = clip.length, color = clip.color, user = clip.user}
        entry.name, entry.name_length = clip.name, clip.name_length
        timeline.copy_count += 1
    }
    return timeline.copy_count
}

// Puts the copied clips back: the earliest one at `time`, the top one on the track at `track` (an index from the top; -1: where it was), the others around them as they were. The pasted clips
// are selected, the others are not. The rules decide for each one (a clip that may not be there is left out; a track that is not there takes none). How many were made.
TimelinePaste :: proc(timeline: ^Timeline, time: f64, track: int = -1) -> int {
    if timeline.copy_count == 0 { return 0 }
    base: int = timeline.copy_top_track if track < 0 else track
    pasted: [TIMELINE_COPIES]ClipHandle
    count: int
    for i in 0 ..< timeline.copy_count {
        entry: ^TimelineCopyEntry = &timeline.copies[i]
        index: int = base + entry.track_offset
        if index < 0 || index >= timeline.track_count { continue }
        start: f64 = max(time + entry.start_offset, 0)
        target: TrackHandle = timeline.order[index]
        owner: ^TimelineTrack = TimelineTrackGet(timeline, target)
        if owner == nil || owner.kind != .CLIPS || entry.length < timeline.rules.min_length { continue }
        if timeline.rules.can_place != nil && !timeline.rules.can_place(timeline, nil, target, start, entry.length, timeline.rules.user) { continue }
        clip: TimelineClip = {track = target, start = start, length = entry.length, user = entry.user, color = entry.color}
        clip.name, clip.name_length = entry.name, entry.name_length
        handle, ok := hm.add(&timeline.clips, clip)
        if !ok { break }
        owner.clip_count += 1
        pasted[count] = handle
        count += 1
        timelineEmit(timeline, {kind = .CLIP_ADDED, clip = handle, track = target, start = start, length = entry.length, copied_from = entry.source})
    }
    if count > 0 {
        TimelineSelectClear(timeline)
        for i in 0 ..< count { TimelineClipSelect(timeline, pasted[i]) }
    }
    return count
}

// ------------------------------------------------------------------------------------------------------------------------
// Automation: tracks of points

// A track that holds the points of an automation (not clips): a value from `minimum` to `maximum` that changes in time. Its `user` pointer is what the program connects it to (a parameter).
TimelineAutomationAdd :: proc(timeline: ^Timeline, name: string, minimum: f32 = 0, maximum: f32 = 1, height: f32 = 0, user: rawptr = nil, color: Color = {}) -> (handle: TrackHandle, ok: bool) {
    if maximum <= minimum { return }
    handle, ok = TimelineTrackAdd(timeline, name, height, user, color)
    if !ok { return }
    track: ^TimelineTrack = TimelineTrackGet(timeline, handle)
    track.kind, track.value_min, track.value_max = .AUTOMATION, minimum, maximum
    return
}

TimelinePointGet :: proc(timeline: ^Timeline, handle: PointHandle) -> ^TimelinePoint {
    if handle == {} { return nil }
    item, ok := hm.get(&timeline.points, handle)
    return item if ok else nil
}

TimelinePointCount :: proc(timeline: ^Timeline) -> int {
    return int(hm.len(timeline.points))
}

// A point on an automation track (the value is kept within the range of the track). False when the track is not an automation track, the time is below 0 or the storage is full.
TimelinePointAdd :: proc(timeline: ^Timeline, track: TrackHandle, time: f64, value: f32) -> (handle: PointHandle, ok: bool) {
    owner: ^TimelineTrack = TimelineTrackGet(timeline, track)
    if owner == nil || owner.kind != .AUTOMATION || time < 0 { return }
    point: TimelinePoint = {track = track, time = time, value = clamp(value, owner.value_min, owner.value_max)}
    handle, ok = hm.add(&timeline.points, point)
    if !ok { return }
    owner.point_count += 1
    timelineEmit(timeline, {kind = .POINT_ADDED, point = handle, track = track, time = time, value = point.value})
    return
}

// Moves a point (time not below 0, the value kept within the range). One event with where it was.
TimelinePointMove :: proc(timeline: ^Timeline, handle: PointHandle, time: f64, value: f32) -> bool {
    point: ^TimelinePoint = TimelinePointGet(timeline, handle)
    if point == nil || time < 0 { return false }
    owner: ^TimelineTrack = TimelineTrackGet(timeline, point.track)
    clamped: f32 = clamp(value, owner.value_min, owner.value_max)
    if point.time == time && point.value == clamped { return true }
    event: TimelineEvent = {kind = .POINT_MOVED, point = handle, track = point.track, time = time, value = clamped, previous_start = point.time, previous_value = point.value}
    point.time, point.value = time, clamped
    timelineEmit(timeline, event)
    return true
}

// Sets the shape of the curve that leaves a point. One event with what it was. False when the point is gone.
TimelinePointShape :: proc(timeline: ^Timeline, handle: PointHandle, shape: CurveShape, curve: f32 = 0) -> bool {
    point: ^TimelinePoint = TimelinePointGet(timeline, handle)
    if point == nil { return false }
    clamped: f32 = clamp(curve, -CURVE_LIMIT, CURVE_LIMIT)
    if point.shape == shape && point.curve == clamped { return true }
    event: TimelineEvent = {kind = .POINT_SHAPED, point = handle, track = point.track, time = point.time, value = point.value, shape = shape, previous_shape = point.shape, curve = clamped, previous_curve = point.curve}
    point.shape, point.curve = shape, clamped
    timelineEmit(timeline, event)
    return true
}

// The `curve` a segment really has: the one of its point and the bend macro of its track, for the shapes that have a bend (`change` is the value of the next point minus this one).
TimelineSegmentCurve :: proc(track: ^TimelineTrack, shape: CurveShape, curve: f32, change: f32) -> f32 {
    if shape != .CURVE && shape != .S_CURVE && shape != .EXP { return curve }
    return clamp(curve + (track.bend_rise if change >= 0 else track.bend_fall), -CURVE_LIMIT, CURVE_LIMIT)
}

// Sets the bend macro of an automation track (see TimelineTrack). One event. False for a track that is not an automation track.
TimelineTrackBend :: proc(timeline: ^Timeline, handle: TrackHandle, rise: f32, fall: f32) -> bool {
    owner: ^TimelineTrack = TimelineTrackGet(timeline, handle)
    if owner == nil || owner.kind != .AUTOMATION { return false }
    rise_clamped, fall_clamped: f32 = clamp(rise, -1, 1), clamp(fall, -1, 1)
    if owner.bend_rise == rise_clamped && owner.bend_fall == fall_clamped { return true }
    owner.bend_rise, owner.bend_fall = rise_clamped, fall_clamped
    timelineEmit(timeline, {kind = .TRACK_BENT, track = handle, value = rise_clamped, curve = fall_clamped})
    return true
}

// Sets the slopes of the HERMITE curve at a point (kept within 0 .. TANGENT_LIMIT): the one it arrives with from the point before and the one it leaves with to the next. One POINT_SHAPED event.
TimelinePointTangents :: proc(timeline: ^Timeline, handle: PointHandle, tangent_in: f32, tangent_out: f32) -> bool {
    point: ^TimelinePoint = TimelinePointGet(timeline, handle)
    if point == nil { return false }
    tin, tout: f32 = clamp(tangent_in, 0, TANGENT_LIMIT), clamp(tangent_out, 0, TANGENT_LIMIT)
    if point.tangent_in == tin && point.tangent_out == tout { return true }
    event: TimelineEvent = {
        kind = .POINT_SHAPED, point = handle, track = point.track, time = point.time, value = point.value, shape = point.shape, previous_shape = point.shape, curve = point.curve, previous_curve = point.curve,
        tangent_in = tin, tangent_out = tout, previous_tangent_in = point.tangent_in, previous_tangent_out = point.tangent_out,
    }
    point.tangent_in, point.tangent_out = tin, tout
    timelineEmit(timeline, event)
    return true
}

TimelinePointRemove :: proc(timeline: ^Timeline, handle: PointHandle) -> bool {
    point: ^TimelinePoint = TimelinePointGet(timeline, handle)
    if point == nil { return false }
    if owner := TimelineTrackGet(timeline, point.track); owner != nil { owner.point_count -= 1 }
    timelineEmit(timeline, {kind = .POINT_REMOVED, point = handle, track = point.track, time = point.time, value = point.value})
    hm.remove(&timeline.points, handle)
    return true
}

// Remembers where the selected points are: the start of a stretch (TimelinePointsStretch always works from this, so a drag does not add up errors).
TimelinePointsSnapshot :: proc(timeline: ^Timeline) {
    it := hm.iterator_make(&timeline.points)
    for point, _ in hm.iterate(&it) { point.drag_time, point.drag_value = point.time, point.value }
}

// Stretches the selected points from the snapshot (TimelinePointsSnapshot): the times grow by `time_scale` away from `anchor`, and the distance of the values from the bottom of their
// lane by a factor that is 1 at the end of the selection that is at `anchor` and `end_factor` at the other end, a ramp between them: 1 for both leaves the values, above 1 makes a rising wedge toward
// the far end. Times stay at 0 or above, the values within the range. Events like any move. How many points moved.
TimelinePointsStretch :: proc(timeline: ^Timeline, anchor: f64, time_scale: f64, end_factor: f32) -> (moved: int) {
    first, last: f64 = f64(INFINITE), -1
    it := hm.iterator_make(&timeline.points)
    for point, _ in hm.iterate(&it) {
        if !point.selected { continue }
        first, last = min(first, point.drag_time), max(last, point.drag_time)
    }
    if last < 0 { return }
    from_left: bool = anchor <= first                       // the anchor is the left end: the far end is the right one
    span: f64 = max(last - first, 1e-9)
    it = hm.iterator_make(&timeline.points)
    for point, handle in hm.iterate(&it) {
        if !point.selected { continue }
        owner: ^TimelineTrack = TimelineTrackGet(timeline, point.track)
        along: f64 = (point.drag_time - first) / span if from_left else (last - point.drag_time) / span
        factor: f32 = 1 + (end_factor - 1) * f32(along)
        value: f32 = owner.value_min + (point.drag_value - owner.value_min) * max(factor, 0)
        if TimelinePointMove(timeline, handle, max(anchor + (point.drag_time - anchor) * max(time_scale, 0), 0), value) { moved += 1 }
    }
    return
}

TimelineSelectedPoints :: proc(timeline: ^Timeline) -> (count: int) {
    it := hm.iterator_make(&timeline.points)
    for point, _ in hm.iterate(&it) {
        if point.selected { count += 1 }
    }
    return
}

// The points of a track in the order of their time, into `out` (as many as fit): how many. For the program that plays the automation.
TimelineTrackPoints :: proc(timeline: ^Timeline, track: TrackHandle, out: []PointHandle) -> int {
    count: int
    it := hm.iterator_make(&timeline.points)
    for point, handle in hm.iterate(&it) {
        if point.track != track || count >= len(out) { continue }
        position: int = count
        for position > 0 && TimelinePointGet(timeline, out[position - 1]).time > point.time {
            out[position] = out[position - 1]
            position -= 1
        }
        out[position] = handle
        count += 1
    }
    return count
}

// The value of an automation track at a time: the first value before the first point, the last one after the last, in between a straight line from one point to the next
// (or the value of the earlier point until the next one when the track `steps`). False for a track that has no points or is not an automation track.
TimelineAutomationValue :: proc(timeline: ^Timeline, track: TrackHandle, time: f64) -> (value: f32, found: bool) {
    owner: ^TimelineTrack = TimelineTrackGet(timeline, track)
    if owner == nil || owner.kind != .AUTOMATION { return }
    before, after: ^TimelinePoint
    it := hm.iterator_make(&timeline.points)
    for point, _ in hm.iterate(&it) {
        if point.track != track { continue }
        if point.time <= time && (before == nil || point.time >= before.time) { before = point }
        if point.time > time && (after == nil || point.time < after.time) { after = point }
    }
    switch {
    case before == nil && after == nil: return 0, false
    case before == nil: return after.value, true
    case after == nil: return before.value, true
    }
    shape: CurveShape = .HOLD if owner.steps else before.shape
    fraction: f32 = f32((time - before.time) / (after.time - before.time))
    if shape == .HERMITE {
        return before.value + (after.value - before.value) * CurveEvalTangents(clamp(before.tangent_out, 0, TANGENT_LIMIT), clamp(after.tangent_in, 0, TANGENT_LIMIT), fraction), true
    }
    return before.value + (after.value - before.value) * CurveEval(shape, TimelineSegmentCurve(owner, shape, before.curve, after.value - before.value), fraction), true
}
