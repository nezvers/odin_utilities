#+build !js
package ui

import "core:testing"

@(private = "file")
newTimeline :: proc() -> ^Timeline {
    timeline: ^Timeline = new(Timeline)
    TimelineInit(timeline)
    return timeline
}

@(private = "file")
drainTimeline :: proc(timeline: ^Timeline) {
    for {
        _, has := TimelinePollEvent(timeline)
        if !has { break }
    }
}

@(test)
test_a_timeline_tells_what_happens_to_its_clips_with_the_user_pointers :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    channel: int = 1
    loop: int = 2
    program: int = 3
    timeline.user = &program
    drums, ok := TimelineTrackAdd(timeline, "Drums", user = &channel)
    testing.expect(t, ok)
    event, _ := TimelinePollEvent(timeline)
    testing.expect_value(t, event.kind, TimelineEventKind.TRACK_ADDED)
    testing.expect(t, event.track_user == &channel && event.timeline_user == &program)
    clip, added := TimelineClipAdd(timeline, drums, 4, 8, "Loop A", user = &loop)
    testing.expect(t, added)
    event, _ = TimelinePollEvent(timeline)
    testing.expect_value(t, event.kind, TimelineEventKind.CLIP_ADDED)
    testing.expect(t, event.clip_user == &loop && event.track_user == &channel && event.start == 4 && event.length == 8)
    testing.expect_value(t, TimelineClipName(TimelineClipGet(timeline, clip)), "Loop A")
    // moving: one event with where it was
    testing.expect(t, TimelineClipPlace(timeline, clip, drums, 12, 8))
    event, _ = TimelinePollEvent(timeline)
    testing.expect_value(t, event.kind, TimelineEventKind.CLIP_MOVED)
    testing.expect(t, event.start == 12 && event.previous_start == 4 && event.previous_length == 8)
    // a longer clip is resized (and the start may change with it)
    testing.expect(t, TimelineClipPlace(timeline, clip, drums, 10, 10))
    event, _ = TimelinePollEvent(timeline)
    testing.expect_value(t, event.kind, TimelineEventKind.CLIP_RESIZED)
    testing.expect(t, event.start == 10 && event.length == 10 && event.previous_start == 12 && event.previous_length == 8)
    // the same place is nothing
    testing.expect(t, TimelineClipPlace(timeline, clip, drums, 10, 10))
    testing.expect_value(t, timeline.event_count, 0)
    // removing: told once, the handle is refused after
    testing.expect(t, TimelineClipRemove(timeline, clip))
    event, _ = TimelinePollEvent(timeline)
    testing.expect_value(t, event.kind, TimelineEventKind.CLIP_REMOVED)
    testing.expect(t, event.clip_user == &loop)
    testing.expect(t, TimelineClipGet(timeline, clip) == nil && !TimelineClipRemove(timeline, clip))
    testing.expect_value(t, TimelineTrackGet(timeline, drums).clip_count, 0)
}

@(test)
test_the_rules_decide_where_a_clip_may_be :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    timeline.rules = {can_place = TimelineRuleNoOverlap, min_length = 0.5}
    first, _ := TimelineTrackAdd(timeline, "a")
    second, _ := TimelineTrackAdd(timeline, "b")
    a, _ := TimelineClipAdd(timeline, first, 0, 4, "a")
    _, overlapping := TimelineClipAdd(timeline, first, 3, 4, "overlap")
    testing.expect(t, !overlapping, "a clip that overlaps is refused")
    b, fits := TimelineClipAdd(timeline, first, 4, 4, "b")
    testing.expect(t, fits)
    _, too_short := TimelineClipAdd(timeline, first, 8, 0.25, "short")
    testing.expect(t, !too_short)
    drainTimeline(timeline)
    // moving onto the other clip is refused, nothing changes and no event is made
    testing.expect(t, !TimelineClipPlace(timeline, b, first, 2, 4))
    testing.expect_value(t, TimelineClipGet(timeline, b).start, 4)
    testing.expect_value(t, timeline.event_count, 0)
    // another track: free
    testing.expect(t, TimelineClipPlace(timeline, b, second, 2, 4))
    testing.expect_value(t, TimelineClipGet(timeline, b).track, second)
    testing.expect_value(t, TimelineTrackGet(timeline, first).clip_count, 1)
    testing.expect_value(t, TimelineTrackGet(timeline, second).clip_count, 1)
    event, _ := TimelinePollEvent(timeline)
    testing.expect(t, event.previous_track == first && event.track == second)
    // before the start of the timeline: refused
    testing.expect(t, !TimelineClipPlace(timeline, a, first, -1, 4))
}

@(test)
test_the_clips_of_a_track_come_in_the_order_of_their_start_for_the_program_that_plays_them :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    track, _ := TimelineTrackAdd(timeline, "t")
    other, _ := TimelineTrackAdd(timeline, "o")
    late, _ := TimelineClipAdd(timeline, track, 20, 4, "late")
    early, _ := TimelineClipAdd(timeline, track, 2, 4, "early")
    middle, _ := TimelineClipAdd(timeline, track, 10, 4, "middle")
    TimelineClipAdd(timeline, other, 0, 100, "elsewhere")
    out: [8]ClipHandle
    count: int = TimelineTrackClips(timeline, track, out[:])
    testing.expect_value(t, count, 3)
    testing.expect(t, out[0] == early && out[1] == middle && out[2] == late)
    testing.expect_value(t, TimelineClipAt(timeline, track, 11), middle)
    testing.expect_value(t, TimelineClipAt(timeline, track, 7), ClipHandle{})
    testing.expect_value(t, TimelineEnd(timeline), 100)
    testing.expect_value(t, TimelineTrackClips(timeline, track, out[:2]), 2)             // as many as fit
}

@(test)
test_removing_a_track_removes_its_clips_and_tells_about_each :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    first, _ := TimelineTrackAdd(timeline, "first")
    second, _ := TimelineTrackAdd(timeline, "second")
    third, _ := TimelineTrackAdd(timeline, "third")
    TimelineClipAdd(timeline, second, 0, 4, "a")
    TimelineClipAdd(timeline, second, 5, 4, "b")
    kept, _ := TimelineClipAdd(timeline, third, 0, 4, "c")
    drainTimeline(timeline)
    testing.expect(t, TimelineTrackRemove(timeline, second))
    removed_clips, removed_tracks: int
    for {
        event, has := TimelinePollEvent(timeline)
        if !has { break }
        if event.kind == .CLIP_REMOVED { removed_clips += 1 }
        if event.kind == .TRACK_REMOVED { removed_tracks += 1 }
    }
    testing.expect_value(t, removed_clips, 2)
    testing.expect_value(t, removed_tracks, 1)
    testing.expect_value(t, timeline.track_count, 2)
    testing.expect_value(t, TimelineTrackIndex(timeline, third), 1)                      // the tracks below move up
    testing.expect_value(t, TimelineTrackIndex(timeline, second), -1)
    testing.expect_value(t, TimelineClipCount(timeline), 1)
    testing.expect(t, TimelineClipGet(timeline, kept) != nil && first != {})
}

@(test)
test_events_that_nobody_reads_do_not_pile_up_in_a_timeline :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    track, _ := TimelineTrackAdd(timeline, "t")
    for _ in 0 ..< TIMELINE_EVENTS + 10 {
        clip, _ := TimelineClipAdd(timeline, track, 0, 1, "c")
        TimelineClipRemove(timeline, clip)
    }
    testing.expect_value(t, timeline.event_count, TIMELINE_EVENTS)
    testing.expect(t, timeline.events_lost > 0)
}

@(test)
test_markers_are_told_with_their_user_pointer_and_cleared_with_the_selection :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    section: int = 7
    marker, ok := TimelineMarkerAdd(timeline, 8, "Drop", user = &section)
    testing.expect(t, ok)
    event, _ := TimelinePollEvent(timeline)
    testing.expect_value(t, event.kind, TimelineEventKind.MARKER_ADDED)
    testing.expect(t, event.marker == marker && event.marker_user == &section && event.time == 8)
    testing.expect_value(t, TimelineMarkerName(TimelineMarkerGet(timeline, marker)), "Drop")
    testing.expect(t, TimelineMarkerMove(timeline, marker, 12))
    event, _ = TimelinePollEvent(timeline)
    testing.expect_value(t, event.kind, TimelineEventKind.MARKER_MOVED)
    testing.expect(t, event.time == 12 && event.previous_start == 8)
    testing.expect(t, TimelineMarkerMove(timeline, marker, 12) && timeline.event_count == 0, "the same time is nothing")
    testing.expect(t, !TimelineMarkerMove(timeline, marker, -1), "not before the start")
    _, negative := TimelineMarkerAdd(timeline, -2, "before")
    testing.expect(t, !negative)
    TimelineMarkerGet(timeline, marker).selected = true
    TimelineSelectClear(timeline)
    testing.expect(t, !TimelineMarkerGet(timeline, marker).selected, "clearing the selection clears the markers too")
    testing.expect(t, TimelineMarkerRemove(timeline, marker))
    event, _ = TimelinePollEvent(timeline)
    testing.expect_value(t, event.kind, TimelineEventKind.MARKER_REMOVED)
    testing.expect(t, event.marker_user == &section, "the user pointer comes with the removal too")
    testing.expect(t, TimelineMarkerGet(timeline, marker) == nil && !TimelineMarkerRemove(timeline, marker))
    testing.expect_value(t, TimelineMarkerCount(timeline), 0)
}

@(test)
test_copied_clips_are_pasted_at_a_time_on_the_same_tracks_with_the_rules_and_a_source_in_the_event :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    first, _ := TimelineTrackAdd(timeline, "one")
    second, _ := TimelineTrackAdd(timeline, "two")
    TimelineTrackAdd(timeline, "three")
    a_data: int = 1
    b_data: int = 2
    a, _ := TimelineClipAdd(timeline, first, 2, 2, "A", user = &a_data)
    b, _ := TimelineClipAdd(timeline, second, 3, 2, "B", user = &b_data)
    TimelineClipSelect(timeline, a)
    TimelineClipSelect(timeline, b)
    testing.expect_value(t, TimelineCopy(timeline), 2)
    drainTimeline(timeline)
    testing.expect_value(t, TimelinePaste(timeline, 10), 2)
    pasted: [2]TimelineEvent
    count: int
    for {
        event, has := TimelinePollEvent(timeline)
        if !has { break }
        if event.kind == .CLIP_ADDED && count < 2 {
            pasted[count] = event
            count += 1
        }
    }
    testing.expect_value(t, count, 2)
    testing.expect(t, pasted[0].start == 10 && pasted[0].track == first && pasted[0].copied_from == a && pasted[0].clip_user == &a_data, "the earliest at the time, on its own track, with where it came from")
    testing.expect(t, pasted[1].start == 11 && pasted[1].track == second && pasted[1].copied_from == b && pasted[1].clip_user == &b_data, "the other one the same distance later, one track down")
    testing.expect_value(t, TimelineClipCount(timeline), 4)
    testing.expect(t, !TimelineClipGet(timeline, a).selected && !TimelineClipGet(timeline, b).selected, "the copies are selected, the originals are not")
    testing.expect_value(t, TimelineSelectedCount(timeline), 2)
    testing.expect_value(t, TimelineClipName(TimelineClipGet(timeline, pasted[0].clip)), "A")
    // on another track: the top one goes there, the one below it to the next, a track that is not there takes none
    TimelineSelectClear(timeline)
    testing.expect_value(t, TimelinePaste(timeline, 20, 1), 2)
    testing.expect_value(t, TimelineClipGet(timeline, TimelineClipAt(timeline, second, 20)).length, 2)
    testing.expect(t, TimelineClipAt(timeline, TimelineTrackGet(timeline, timeline.order[2]).handle, 21) != {})
    testing.expect_value(t, TimelinePaste(timeline, 30, 2), 1)          // the second would be on a fourth track
    // the rules: where it may not be, nothing is made and the selection stays
    timeline.rules.can_place = TimelineRuleNoOverlap
    selected: int = TimelineSelectedCount(timeline)
    testing.expect_value(t, TimelinePaste(timeline, 10), 0)
    testing.expect_value(t, TimelineSelectedCount(timeline), selected)
    // nothing copied: nothing pasted
    other: ^Timeline = newTimeline()
    defer free(other)
    testing.expect_value(t, TimelinePaste(other, 0), 0)
    testing.expect_value(t, TimelineCopy(other), 0)
}
