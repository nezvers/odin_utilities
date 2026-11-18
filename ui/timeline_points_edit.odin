package ui

// Edits of the selected points of automation lanes as a whole: the pattern tools (invert, reverse, rotate, repeat). Each one works on the selected points of every lane at once and
// goes through the same procs as a hand edit (events, limits), so an undo (timeline_history.odin) and the program that follows the events see nothing new.

import "core:math"
import hm "core:container/handle_map"

// The selected points of a track in the order of their time, into `out`: how many.
@(private)
timelineSelectedOfTrack :: proc(timeline: ^Timeline, track: TrackHandle, out: []PointHandle) -> int {
    count: int
    it := hm.iterator_make(&timeline.points)
    for point, handle in hm.iterate(&it) {
        if point.track != track || !point.selected || count >= len(out) { continue }
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

// Turns the values of the selected points upside down within the range of their lane (the highest becomes the lowest). Returns how many points changed.
TimelinePointsFlip :: proc(timeline: ^Timeline) -> (changed: int) {
    it := hm.iterator_make(&timeline.points)
    for point, handle in hm.iterate(&it) {
        if !point.selected { continue }
        owner: ^TimelineTrack = TimelineTrackGet(timeline, point.track)
        before: f32 = point.value
        TimelinePointMove(timeline, handle, point.time, owner.value_min + owner.value_max - point.value)
        if point.value != before { changed += 1 }
    }
    return
}

// Plays the selected points backwards: the first becomes the last (the times are mirrored within the span of the selection of each lane). The curve of a segment between two selected
// points goes with it, reversed: a bias that eased out eases in, a pulse starts at the other value. Returns how many points moved.
TimelinePointsMirror :: proc(timeline: ^Timeline) -> (moved: int) {
    ordered: [TIMELINE_POINTS]PointHandle
    for i in 0 ..< timeline.track_count {
        track: TrackHandle = timeline.order[i]
        count: int = timelineSelectedOfTrack(timeline, track, ordered[:])
        if count < 2 { continue }
        first: f64 = TimelinePointGet(timeline, ordered[0]).time
        last: f64 = TimelinePointGet(timeline, ordered[count - 1]).time
        // the segments first: they are read before any point is moved
        Segment :: struct { shape: CurveShape, curve: f32 }
        shapes: [TIMELINE_POINTS]Segment
        for k in 0 ..< count - 1 {
            point: ^TimelinePoint = TimelinePointGet(timeline, ordered[k])
            curve: f32 = point.curve
            // a bias that eased out eases in backwards; a pulse starts at the other value (the sign of its curve says which one, so a curve of 0 becomes a hair below 0)
            if point.shape == .CURVE { curve = -curve }
            if point.shape == .PULSE { curve = -curve if curve != 0 else -0.0001 }
            shapes[k] = {point.shape, curve}
        }
        for k in 0 ..< count {
            point: ^TimelinePoint = TimelinePointGet(timeline, ordered[k])
            if TimelinePointMove(timeline, ordered[k], first + last - point.time, point.value) { moved += 1 }
        }
        // the segment that was between k and k + 1 is now between the old k + 1 (now on the left) and the old k
        for k in 0 ..< count - 1 {
            TimelinePointShape(timeline, ordered[k + 1], shapes[k].shape, shapes[k].curve)
        }
    }
    return
}

// Moves the selected points by `amount` in time, around: what leaves at `to` comes back at `from` (the pattern rotates inside of [from, to)). The points that are outside of the range
// do not move. Returns how many points moved.
TimelinePointsRotate :: proc(timeline: ^Timeline, from: f64, to: f64, amount: f64) -> (moved: int) {
    if to <= from { return }
    length: f64 = to - from
    it := hm.iterator_make(&timeline.points)
    for point, handle in hm.iterate(&it) {
        if !point.selected || point.time < from || point.time >= to { continue }
        wrapped: f64 = math.mod(point.time - from + amount, length)
        if wrapped < 0 { wrapped += length }
        if TimelinePointMove(timeline, handle, from + wrapped, point.value) { moved += 1 }
    }
    return
}

// Repeats the selected points: a copy of them after the last one of each lane, as far from it as the span of the selection is long (at least `minimum_span`, so one point still
// repeats), with their curves. The copies are the selection afterwards. Returns how many points were added (fewer when the storage is full).
TimelinePointsRepeat :: proc(timeline: ^Timeline, minimum_span: f64 = 1) -> (added: int) {
    ordered: [TIMELINE_POINTS]PointHandle
    for i in 0 ..< timeline.track_count {
        track: TrackHandle = timeline.order[i]
        count: int = timelineSelectedOfTrack(timeline, track, ordered[:])
        if count == 0 { continue }
        first: f64 = TimelinePointGet(timeline, ordered[0]).time
        span: f64 = max(TimelinePointGet(timeline, ordered[count - 1]).time - first, minimum_span)
        for k in 0 ..< count {
            source: TimelinePoint = TimelinePointGet(timeline, ordered[k])^
            created, ok := TimelinePointAdd(timeline, track, source.time + span, source.value)
            if !ok { return }
            TimelinePointShape(timeline, created, source.shape, source.curve)
            TimelinePointGet(timeline, created).selected = true
            TimelinePointGet(timeline, ordered[k]).selected = false
            added += 1
        }
    }
    return
}
