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
