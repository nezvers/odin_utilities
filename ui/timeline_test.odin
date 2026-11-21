#+build !js
package ui

import "core:testing"
import su "../simd"

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

@(test)
test_an_automation_track_holds_points_with_events_and_a_value_between_them :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    parameter: int = 5
    cutoff, ok := TimelineAutomationAdd(timeline, "Cutoff", 20, 20000, user = &parameter)
    testing.expect(t, ok)
    clips_track, _ := TimelineTrackAdd(timeline, "Drums")
    testing.expect_value(t, TimelineTrackGet(timeline, cutoff).kind, TrackKind.AUTOMATION)
    _, refused := TimelineAutomationAdd(timeline, "bad", 1, 1)
    testing.expect(t, !refused, "an empty range")
    drainTimeline(timeline)
    a, _ := TimelinePointAdd(timeline, cutoff, 4, 1000)
    event, _ := TimelinePollEvent(timeline)
    testing.expect_value(t, event.kind, TimelineEventKind.POINT_ADDED)
    testing.expect(t, event.point == a && event.track == cutoff && event.track_user == &parameter && event.time == 4 && event.value == 1000)
    b, _ := TimelinePointAdd(timeline, cutoff, 0, 50000)               // above the range: kept within it
    testing.expect_value(t, TimelinePointGet(timeline, b).value, 20000)
    c, _ := TimelinePointAdd(timeline, cutoff, 8, 10)                  // below the range
    testing.expect_value(t, TimelinePointGet(timeline, c).value, 20)
    _, on_clips := TimelinePointAdd(timeline, clips_track, 1, 1)
    testing.expect(t, !on_clips, "points go on automation tracks")
    _, negative := TimelinePointAdd(timeline, cutoff, -1, 100)
    testing.expect(t, !negative)
    _, clip_on_automation := TimelineClipAdd(timeline, cutoff, 1, 1, "no")
    testing.expect(t, !clip_on_automation, "clips go on tracks of clips")
    testing.expect_value(t, TimelineTrackGet(timeline, cutoff).point_count, 3)
    // in the order of the time, for the program that plays them
    out: [8]PointHandle
    count: int = TimelineTrackPoints(timeline, cutoff, out[:])
    testing.expect(t, count == 3 && out[0] == b && out[1] == a && out[2] == c)
    // the value: before the first point the first one, after the last the last one, in between a line
    value, found := TimelineAutomationValue(timeline, cutoff, -3)
    testing.expect(t, found && value == 20000)
    value, _ = TimelineAutomationValue(timeline, cutoff, 2)             // half way from 20000 (time 0) to 1000 (time 4)
    testing.expect(t, abs(value - 10500) < 0.5)
    value, _ = TimelineAutomationValue(timeline, cutoff, 6)             // half way from 1000 to 20
    testing.expect(t, abs(value - 510) < 0.5)
    value, _ = TimelineAutomationValue(timeline, cutoff, 100)
    testing.expect_value(t, value, 20)
    value, _ = TimelineAutomationValue(timeline, cutoff, 4)             // exactly on a point
    testing.expect_value(t, value, 1000)
    TimelineTrackGet(timeline, cutoff).steps = true
    value, _ = TimelineAutomationValue(timeline, cutoff, 6)
    testing.expect_value(t, value, 1000)                                // held until the next point
    _, none := TimelineAutomationValue(timeline, clips_track, 1)
    testing.expect(t, !none)
    // moving: told with where it was
    drainTimeline(timeline)
    testing.expect(t, TimelinePointMove(timeline, a, 5, 2000))
    event, _ = TimelinePollEvent(timeline)
    testing.expect_value(t, event.kind, TimelineEventKind.POINT_MOVED)
    testing.expect(t, event.time == 5 && event.value == 2000 && event.previous_start == 4 && event.previous_value == 1000)
    testing.expect(t, TimelinePointMove(timeline, a, 5, 2000) && timeline.event_count == 0, "the same place is nothing")
    testing.expect(t, !TimelinePointMove(timeline, a, -1, 2000))
    testing.expect_value(t, TimelineEnd(timeline), 8)
    // removing: told once, the handle is refused after
    testing.expect(t, TimelinePointRemove(timeline, a))
    event, _ = TimelinePollEvent(timeline)
    testing.expect(t, event.kind == .POINT_REMOVED && event.track_user == &parameter)
    testing.expect(t, TimelinePointGet(timeline, a) == nil && !TimelinePointRemove(timeline, a))
    // a track that is removed takes its points, each one is told
    drainTimeline(timeline)
    testing.expect(t, TimelineTrackRemove(timeline, cutoff))
    removed: int
    for {
        e, has := TimelinePollEvent(timeline)
        if !has { break }
        if e.kind == .POINT_REMOVED { removed += 1 }
    }
    testing.expect_value(t, removed, 2)
    testing.expect_value(t, TimelinePointCount(timeline), 0)
}

@(private = "file")
maxError :: proc(plan: ^AutomationPlan, time: f64, step: f64, count: int, block: int) -> (worst: f32, mismatches: int) {
    cursor: AutomationCursor
    rendered: []f32 = make([]f32, count)
    exact: []f32 = make([]f32, count)
    defer delete(rendered)
    defer delete(exact)
    for start := 0; start < count; start += block {
        size: int = min(block, count - start)
        AutomationRender(plan, &cursor, time + f64(start) * step, step, rendered[start:start + size])
    }
    AutomationRenderExact(plan, time, step, exact)
    for i in 0 ..< count {
        worst = max(worst, abs(rendered[i] - exact[i]))
        if abs(rendered[i] - exact[i]) > 1e-6 { mismatches += 1 }
    }
    return
}

@(test)
test_a_plan_is_the_points_of_a_track_as_flat_segments_with_what_a_block_needs :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    lane, _ := TimelineAutomationAdd(timeline, "p", 0, 10)
    TimelinePointAdd(timeline, lane, 8, 10)
    a, _ := TimelinePointAdd(timeline, lane, 2, 2)
    TimelinePointAdd(timeline, lane, 4, 6)
    TimelinePointShape(timeline, a, .CURVE, 0.5)
    storage: [8]AutomationSegment
    plan, ok := AutomationCompile(timeline, lane, storage[:])
    testing.expect(t, ok && plan.valid)
    testing.expect_value(t, len(plan.segments), 2)
    testing.expect(t, plan.first_value == 2 && plan.last_value == 10, "before the first point and after the last one")
    first: AutomationSegment = plan.segments[0]
    testing.expect(t, first.start == 2 && first.end == 4 && first.inverse_length == 0.5 && first.value == 2 && first.change == 4 && first.shape == .CURVE)
    testing.expect(t, abs(first.coefficient - CurveCoefficient(.CURVE, 0.5)) < 1e-6)
    testing.expect(t, plan.segments[1].start == 4 && plan.segments[1].end == 8 && plan.segments[1].shape == .LINEAR)
    small: [1]AutomationSegment
    _, small_ok := AutomationCompile(timeline, lane, small[:])
    testing.expect(t, !small_ok, "too small a storage")
    clips_track, _ := TimelineTrackAdd(timeline, "clips")
    _, clips_ok := AutomationCompile(timeline, clips_track, storage[:])
    testing.expect(t, !clips_ok, "a track of clips")
    empty_lane, _ := TimelineAutomationAdd(timeline, "empty", 0, 1)
    empty, empty_ok := AutomationCompile(timeline, empty_lane, storage[:])
    testing.expect(t, empty_ok && !empty.valid)
    cursor: AutomationCursor
    block: [4]f32 = {9, 9, 9, 9}
    AutomationRender(&empty, &cursor, 0, 1, block[:])
    testing.expect(t, block == {0, 0, 0, 0}, "no points: silence")
}

@(test)
test_a_block_is_the_same_as_the_exact_value_of_every_sample_within_a_small_error :: proc(t: ^testing.T) {
    shapes: [6]CurveShape = {.LINEAR, .HOLD, .SMOOTH, .CURVE, .S_CURVE, .EXP}
    storage: [4]AutomationSegment
    for shape in shapes {
        timeline: ^Timeline = newTimeline()
        lane, _ := TimelineAutomationAdd(timeline, "p", 0, 1)
        a, _ := TimelinePointAdd(timeline, lane, 1, 0.2)
        TimelinePointAdd(timeline, lane, 2, 0.9)
        TimelinePointShape(timeline, a, shape, 0.6)
        plan, _ := AutomationCompile(timeline, lane, storage[:])
        // from 0.5 to 2.5: the lead, the segment of one unit (48000 samples), the tail; in blocks of 512 and of 77 samples
        error_512, wrong_512 := maxError(&plan, 0.5, 1.0 / 48000, 96000, 512)
        error_77, wrong_77 := maxError(&plan, 0.5, 1.0 / 48000, 96000, 77)
        if shape == .HOLD {
            // a step: the time of a sample is found as the time of its block plus its place in it, the reference computes it in one go, the rounding differs by a hair: the step may
            // be one sample off at its edge, nowhere else
            testing.expectf(t, wrong_512 <= 1 && wrong_77 <= 1, "HOLD: %d (blocks of 512) and %d (of 77) samples are not the reference", wrong_512, wrong_77)
        } else {
            limit: f32 = 2e-6 if shape == .LINEAR else 2e-4
            testing.expectf(t, error_512 <= limit && error_77 <= limit, "%v: error %v (blocks of 512) and %v (of 77), limit %v", shape, error_512, error_77, limit)
        }
        free(timeline)
    }
}

@(test)
test_a_strong_bend_costs_a_larger_but_still_small_error_and_a_short_segment_is_exact :: proc(t: ^testing.T) {
    storage: [4]AutomationSegment
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    lane, _ := TimelineAutomationAdd(timeline, "p", 0, 1)
    a, _ := TimelinePointAdd(timeline, lane, 0, 0)
    TimelinePointAdd(timeline, lane, 1, 1)
    TimelinePointShape(timeline, a, .CURVE, 0.95)
    plan, _ := AutomationCompile(timeline, lane, storage[:])
    strong, _ := maxError(&plan, 0, 1.0 / 48000, 48000, 256)
    testing.expectf(t, strong < 3e-3, "a strong bend over a second: error %v", strong)
    // 96 samples long: below 125 anchor spaces, so every sample is evaluated: exact up to f32
    short_timeline: ^Timeline = newTimeline()
    defer free(short_timeline)
    short_lane, _ := TimelineAutomationAdd(short_timeline, "s", 0, 1)
    s1, _ := TimelinePointAdd(short_timeline, short_lane, 0, 0)
    TimelinePointAdd(short_timeline, short_lane, 0.002, 1)
    TimelinePointShape(short_timeline, s1, .CURVE, 0.95)
    short_plan, _ := AutomationCompile(short_timeline, short_lane, storage[:])
    short_error, _ := maxError(&short_plan, 0, 1.0 / 48000, 200, 64)
    testing.expect(t, short_error < 1e-6)
}

@(test)
test_the_cursor_follows_the_blocks_and_finds_its_place_again_after_a_jump :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    lane, _ := TimelineAutomationAdd(timeline, "p", 0, 100)
    for i in 0 ..< 10 { TimelinePointAdd(timeline, lane, f64(i), f32(i * 10)) }
    storage: [16]AutomationSegment
    plan, _ := AutomationCompile(timeline, lane, storage[:])
    cursor: AutomationCursor
    block: [8]f32
    // a block that crosses from the first segment into the second: 0.5 .. 1.375 in 8 steps
    AutomationRender(&plan, &cursor, 0.5, 0.125, block[:])
    testing.expect_value(t, cursor.index, 1)
    testing.expect(t, abs(block[0] - 5) < 1e-4 && abs(block[7] - 13.75) < 1e-3, "a ramp across the border between two segments")
    AutomationRender(&plan, &cursor, 1.5, 0.125, block[:])
    testing.expect_value(t, cursor.index, 2)                             // the cursor is where the next block starts (2.5)
    testing.expect(t, abs(block[0] - 15) < 1e-4)
    // back to the start (a loop): found again
    AutomationRender(&plan, &cursor, 0, 0.125, block[:])
    testing.expect_value(t, cursor.index, 1)                             // the block ended at 1.0: the next one starts in the second segment
    testing.expect(t, block[0] == 0 && abs(block[1] - 1.25) < 1e-4)
    // far ahead (a seek), past the end: the last value
    AutomationRender(&plan, &cursor, 100, 0.125, block[:])
    testing.expect(t, block == {90, 90, 90, 90, 90, 90, 90, 90})
    AutomationRender(&plan, &cursor, -5, 0.125, block[:])
    testing.expect(t, block == {0, 0, 0, 0, 0, 0, 0, 0}, "before the first point: its value")
    // a block that starts before the first point and runs into it
    AutomationRender(&plan, &cursor, -0.5, 0.25, block[:])
    testing.expect(t, block[0] == 0 && block[1] == 0 && abs(block[3] - 2.5) < 1e-4)
    // a step of 0: one value
    AutomationRender(&plan, &cursor, 2.5, 0, block[:])
    testing.expect(t, block[0] == 25 && block[7] == 25)
    AutomationRender(&plan, &cursor, 0, 1, block[:0])
}

@(test)
test_the_value_of_an_automation_follows_the_shape_of_the_point_before_it :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    lane, _ := TimelineAutomationAdd(timeline, "p", 0, 100)
    a, _ := TimelinePointAdd(timeline, lane, 0, 0)
    TimelinePointAdd(timeline, lane, 10, 100)
    value, _ := TimelineAutomationValue(timeline, lane, 2.5)
    testing.expect_value(t, value, 25)                                   // linear
    drainTimeline(timeline)
    testing.expect(t, TimelinePointShape(timeline, a, .SMOOTH))
    event, _ := TimelinePollEvent(timeline)
    testing.expect(t, event.kind == .POINT_SHAPED && event.shape == .SMOOTH && event.previous_shape == .LINEAR && event.track == lane)
    value, _ = TimelineAutomationValue(timeline, lane, 2.5)
    testing.expect(t, abs(value - 15.625) < 0.001, "smoothstep at a quarter")
    testing.expect(t, TimelinePointShape(timeline, a, .CURVE, 0.6) && TimelinePointGet(timeline, a).curve == 0.6)
    value, _ = TimelineAutomationValue(timeline, lane, 5)
    testing.expect(t, abs(value - 80) < 0.01, "the curve passes through the shape number at the middle")
    testing.expect(t, TimelinePointShape(timeline, a, .CURVE, 5) && TimelinePointGet(timeline, a).curve == CURVE_LIMIT, "the bend is limited")
    testing.expect(t, TimelinePointShape(timeline, a, .HOLD))
    value, _ = TimelineAutomationValue(timeline, lane, 9.9)
    testing.expect_value(t, value, 0)
    testing.expect(t, TimelinePointShape(timeline, a, .SMOOTH))
    TimelineTrackGet(timeline, lane).steps = true
    value, _ = TimelineAutomationValue(timeline, lane, 9.9)
    testing.expect_value(t, value, 0)                                    // the track says hold: whatever the points say
    drainTimeline(timeline)
    testing.expect(t, TimelinePointShape(timeline, a, .SMOOTH) && timeline.event_count == 0, "the same shape is nothing")
}

@(test)
test_a_stretch_scales_the_times_from_one_end_and_ramps_the_heights :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    lane, _ := TimelineAutomationAdd(timeline, "p", 0, 100)
    a, _ := TimelinePointAdd(timeline, lane, 2, 10)
    b, _ := TimelinePointAdd(timeline, lane, 4, 10)
    c, _ := TimelinePointAdd(timeline, lane, 6, 10)
    other, _ := TimelinePointAdd(timeline, lane, 9, 50)
    for handle in ([3]PointHandle{a, b, c}) { TimelinePointGet(timeline, handle).selected = true }
    TimelinePointsSnapshot(timeline)
    drainTimeline(timeline)
    testing.expect_value(t, TimelinePointsStretch(timeline, 2, 2, 1), 3)                      // twice as wide from the left end, same heights
    testing.expect_value(t, TimelinePointGet(timeline, a).time, 2)
    testing.expect_value(t, TimelinePointGet(timeline, b).time, 6)
    testing.expect_value(t, TimelinePointGet(timeline, c).time, 10)
    testing.expect_value(t, TimelinePointGet(timeline, b).value, 10)
    testing.expect_value(t, TimelinePointGet(timeline, other).time, 9)                         // not selected: untouched
    // from the snapshot, not from where they are now: the same call again gives the same result
    TimelinePointsStretch(timeline, 2, 2, 1)
    testing.expect_value(t, TimelinePointGet(timeline, c).time, 10)
    // a rising wedge: the factor is 1 at the anchor (left) and 3 at the right end
    TimelinePointsStretch(timeline, 2, 1, 3)
    testing.expect_value(t, TimelinePointGet(timeline, a).value, 10)
    testing.expect_value(t, TimelinePointGet(timeline, b).value, 20)
    testing.expect_value(t, TimelinePointGet(timeline, c).value, 30)
    // anchored at the right end the ramp starts there; the values stay in the range and the times at 0 or above
    TimelinePointsStretch(timeline, 6, 1, 20)
    testing.expect_value(t, TimelinePointGet(timeline, c).value, 10)
    testing.expect_value(t, TimelinePointGet(timeline, a).value, 100)
    TimelinePointsStretch(timeline, 6, 3, 1)
    testing.expect_value(t, TimelinePointGet(timeline, a).time, 0)                            // 6 + (2 - 6) * 3 = -6: at 0
}


@(test)
test_undo_and_redo_bring_back_the_states_with_the_same_handles :: proc(t: ^testing.T) {
    timeline: ^Timeline = new(Timeline)
    history: ^TimelineHistory = new(TimelineHistory)
    states: []TimelineState = make([]TimelineState, 4)
    defer { free(timeline); free(history); delete(states) }
    TimelineInit(timeline)
    track, _ := TimelineTrackAdd(timeline, "a")
    TimelineHistoryInit(history, states, timeline)
    testing.expect(t, !TimelineHistoryCommit(history, timeline), "nothing changed")
    clip, _ := TimelineClipAdd(timeline, track, 1, 2, "x")
    testing.expect(t, TimelineHistoryCommit(history, timeline))
    TimelineClipPlace(timeline, clip, track, 5, 2)
    testing.expect(t, TimelineHistoryCommit(history, timeline))
    TimelineClipRemove(timeline, clip)
    testing.expect(t, TimelineHistoryCommit(history, timeline))
    testing.expect_value(t, TimelineClipCount(timeline), 0)
    testing.expect(t, TimelineHistoryUndo(history, timeline))
    testing.expect_value(t, TimelineClipGet(timeline, clip).start, 5)                 // the same handle
    event: TimelineEvent
    for {
        e, has := TimelinePollEvent(timeline)
        if !has { break }
        event = e
    }
    testing.expect_value(t, event.kind, TimelineEventKind.RESTORED)
    testing.expect(t, TimelineHistoryUndo(history, timeline))
    testing.expect_value(t, TimelineClipGet(timeline, clip).start, 1)
    testing.expect(t, TimelineHistoryUndo(history, timeline))
    testing.expect_value(t, TimelineClipCount(timeline), 0)
    testing.expect(t, !TimelineHistoryUndo(history, timeline), "the oldest step")
    testing.expect(t, TimelineHistoryRedo(history, timeline) && TimelineHistoryRedo(history, timeline) && TimelineHistoryRedo(history, timeline))
    testing.expect_value(t, TimelineClipCount(timeline), 0)
    testing.expect(t, !TimelineHistoryRedo(history, timeline))
    // an edit after an undo drops the redo steps
    TimelineHistoryUndo(history, timeline)
    TimelineClipPlace(timeline, clip, track, 9, 2)
    testing.expect(t, TimelineHistoryCommit(history, timeline) && !TimelineHistoryCanRedo(history))
    // an edit that was not committed is not lost by an undo: a redo brings it back
    TimelineClipPlace(timeline, clip, track, 11, 2)
    testing.expect(t, TimelineHistoryUndo(history, timeline))
    testing.expect_value(t, TimelineClipGet(timeline, clip).start, 9)
    testing.expect(t, TimelineHistoryRedo(history, timeline))
    testing.expect_value(t, TimelineClipGet(timeline, clip).start, 11)
}

@(test)
test_the_history_forgets_the_oldest_step_when_it_is_full :: proc(t: ^testing.T) {
    timeline: ^Timeline = new(Timeline)
    history: ^TimelineHistory = new(TimelineHistory)
    states: []TimelineState = make([]TimelineState, 3)
    defer { free(timeline); free(history); delete(states) }
    TimelineInit(timeline)
    track, _ := TimelineTrackAdd(timeline, "a")
    clip, _ := TimelineClipAdd(timeline, track, 0, 1, "x")
    TimelineHistoryInit(history, states, timeline)
    for i in 1 ..= 5 {
        TimelineClipPlace(timeline, clip, track, f64(i), 1)
        TimelineHistoryCommit(history, timeline)
    }
    testing.expect(t, TimelineHistoryUndo(history, timeline) && TimelineHistoryUndo(history, timeline))
    testing.expect_value(t, TimelineClipGet(timeline, clip).start, 3)                 // 5 4 3 are what the three states kept
    testing.expect(t, !TimelineHistoryUndo(history, timeline))
}

@(test)
test_the_selection_of_points_flips_mirrors_rotates_and_repeats :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    lane, _ := TimelineAutomationAdd(timeline, "p", 0, 100)
    a, _ := TimelinePointAdd(timeline, lane, 1, 10)
    b, _ := TimelinePointAdd(timeline, lane, 2, 40)
    c, _ := TimelinePointAdd(timeline, lane, 4, 90)
    outside, _ := TimelinePointAdd(timeline, lane, 8, 50)
    for handle in ([3]PointHandle{a, b, c}) { TimelinePointGet(timeline, handle).selected = true }
    TimelinePointShape(timeline, a, .CURVE, 0.5)
    TimelinePointShape(timeline, b, .PULSE, 0.0)
    // flip: values upside down in the range 0 .. 100
    testing.expect_value(t, TimelinePointsFlip(timeline), 3)
    testing.expect_value(t, TimelinePointGet(timeline, a).value, 90)
    testing.expect_value(t, TimelinePointGet(timeline, c).value, 10)
    testing.expect_value(t, TimelinePointGet(timeline, outside).value, 50)
    TimelinePointsFlip(timeline)
    testing.expect_value(t, TimelinePointGet(timeline, a).value, 10)                          // twice is nothing
    // mirror: 1, 2, 4 become 4, 3, 1; the curves of the segments go to the left point of the mirrored segment, reversed
    testing.expect_value(t, TimelinePointsMirror(timeline), 3)
    testing.expect_value(t, TimelinePointGet(timeline, a).time, 4)
    testing.expect_value(t, TimelinePointGet(timeline, b).time, 3)
    testing.expect_value(t, TimelinePointGet(timeline, c).time, 1)
    testing.expect_value(t, TimelinePointGet(timeline, b).shape, CurveShape.CURVE)             // the segment a..b: now b..a
    testing.expect_value(t, TimelinePointGet(timeline, b).curve, -0.5)                         // eased out, now eased in
    testing.expect_value(t, TimelinePointGet(timeline, c).shape, CurveShape.PULSE)
    testing.expect(t, TimelinePointGet(timeline, c).curve < 0, "the pulse starts high backwards")
    testing.expect_value(t, TimelinePointGet(timeline, outside).time, 8)
    // rotate by 2 inside 0 .. 5: 4 -> 1 (wraps), 3 -> 0 ... no: 3 + 2 = 5 -> 0, 1 + 2 = 3
    testing.expect_value(t, TimelinePointsRotate(timeline, 0, 5, 2), 3)
    testing.expect_value(t, TimelinePointGet(timeline, a).time, 1)
    testing.expect_value(t, TimelinePointGet(timeline, b).time, 0)
    testing.expect_value(t, TimelinePointGet(timeline, c).time, 3)
    testing.expect_value(t, TimelinePointsRotate(timeline, 0, 5, -1), 3)
    testing.expect_value(t, TimelinePointGet(timeline, b).time, 4)                             // 0 - 1 wraps to 4
    // repeat: the three again after their span (from 0 to 3 now: 3 + 3 ...), the copies are the selection
    before: int = TimelinePointCount(timeline)
    testing.expect_value(t, TimelinePointsRepeat(timeline), 3)
    testing.expect_value(t, TimelinePointCount(timeline), before + 3)
    testing.expect_value(t, TimelineSelectedPoints(timeline), 3)
    testing.expect(t, !TimelinePointGet(timeline, a).selected)
}

@(test)
test_the_bend_of_a_track_adds_to_the_curve_of_rising_and_falling_segments :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    lane, _ := TimelineAutomationAdd(timeline, "p", 0, 100)
    up, _ := TimelinePointAdd(timeline, lane, 0, 0)
    down, _ := TimelinePointAdd(timeline, lane, 10, 100)
    TimelinePointAdd(timeline, lane, 20, 0)
    TimelinePointShape(timeline, up, .CURVE, 0)
    TimelinePointShape(timeline, down, .CURVE, 0)
    value, _ := TimelineAutomationValue(timeline, lane, 5)
    testing.expect_value(t, value, 50)                                       // no bend: a line
    drainTimeline(timeline)
    testing.expect(t, TimelineTrackBend(timeline, lane, 0.6, -0.6))
    event, _ := TimelinePollEvent(timeline)
    testing.expect(t, event.kind == .TRACK_BENT && event.track == lane && event.value == 0.6 && event.curve == -0.6)
    value, _ = TimelineAutomationValue(timeline, lane, 5)
    testing.expect(t, abs(value - 80) < 0.01, "the rising segment is fast first")
    value, _ = TimelineAutomationValue(timeline, lane, 15)
    testing.expect(t, abs(value - 80) < 0.01, "the falling one has the opposite bend: it holds the high value longer (80, a line would be 50)")
    // the plan has it in its coefficients, the renderer is not slower
    storage: [4]AutomationSegment
    plan, ok := AutomationCompile(timeline, lane, storage[:])
    testing.expect(t, ok && abs(AutomationValueAt(&plan, 5) - 80) < 0.01)
    // other shapes do not bend; the same bend is nothing
    TimelinePointShape(timeline, up, .SMOOTH)
    value, _ = TimelineAutomationValue(timeline, lane, 5)
    testing.expect_value(t, value, 50)
    drainTimeline(timeline)
    testing.expect(t, TimelineTrackBend(timeline, lane, 0.6, -0.6) && timeline.event_count == 0)
    testing.expect(t, !TimelineTrackBend(timeline, TrackHandle{}, 0, 0))
}

@(test)
test_the_blocks_of_the_shapes_that_repeat_follow_the_exact_value :: proc(t: ^testing.T) {
    storage: [4]AutomationSegment
    for shape in ([5]CurveShape{.STAIRS, .SMOOTH_STAIRS, .PULSE, .TRIANGLE, .WAVE}) {
        timeline: ^Timeline = newTimeline()
        lane, _ := TimelineAutomationAdd(timeline, "p", 0, 1)
        a, _ := TimelinePointAdd(timeline, lane, 1, 0.2)
        TimelinePointAdd(timeline, lane, 2, 0.9)
        TimelinePointShape(timeline, a, shape, 0.5)                          // 8 steps, cycles or so
        plan, _ := AutomationCompile(timeline, lane, storage[:])
        for block in ([3]int{512, 77, 1000}) {
            worst, wrong := maxError(&plan, 0.5, 1.0 / 48000, 96000, block)
            if shape == .TRIANGLE || shape == .WAVE {
                testing.expectf(t, worst <= 5e-4, "%v blocks of %d: error %v (a sample at a corner may be on the other side: about one sample of slope)", shape, block, worst)
            } else {
                // edges: the sample at an edge may be on the other side (a hair of rounding), at most one per edge
                testing.expectf(t, wrong <= 2 * 8 + 2, "%v blocks of %d: %d samples differ", shape, block, wrong)
            }
        }
        free(timeline)
    }
}

@(test)
test_points_are_copied_cut_and_pasted_with_their_curves :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    top, _ := TimelineAutomationAdd(timeline, "a", 0, 100)
    low, _ := TimelineAutomationAdd(timeline, "b", 0, 10)
    a, _ := TimelinePointAdd(timeline, top, 2, 40)
    b, _ := TimelinePointAdd(timeline, top, 4, 80)
    TimelinePointAdd(timeline, top, 9, 5)                                 // not selected
    TimelinePointShape(timeline, a, .EXP, 0.5)
    TimelinePointGet(timeline, a).selected, TimelinePointGet(timeline, b).selected = true, true
    testing.expect_value(t, TimelineCopyPoints(timeline), 2)
    testing.expect(t, timeline.copy_is_points)
    // pasted at 10 on the same lane: the earliest at 10, the other 2 later, the curve with it; the pasted ones are the selection
    testing.expect_value(t, TimelinePastePoints(timeline, 10), 2)
    testing.expect_value(t, TimelinePointCount(timeline), 5)
    testing.expect_value(t, TimelineSelectedPoints(timeline), 2)
    testing.expect(t, !TimelinePointGet(timeline, a).selected)
    out: [8]PointHandle
    testing.expect_value(t, TimelineTrackPoints(timeline, top, out[:]), 5)
    testing.expect(t, TimelinePointGet(timeline, out[3]).time == 10 && TimelinePointGet(timeline, out[3]).shape == .EXP && TimelinePointGet(timeline, out[3]).curve == 0.5)
    testing.expect(t, TimelinePointGet(timeline, out[4]).time == 12 && TimelinePointGet(timeline, out[4]).value == 80)
    // on the lane below (the range is 10: the values are limited to it)
    testing.expect_value(t, TimelinePastePoints(timeline, 0, 1), 2)
    testing.expect_value(t, TimelineTrackPoints(timeline, low, out[:]), 2)
    testing.expect(t, TimelinePointGet(timeline, out[0]).value == 10 && TimelinePointGet(timeline, out[1]).value == 10)
    // cut: removes the selected points
    testing.expect_value(t, TimelinePointsRemove(timeline), 2)
    testing.expect_value(t, TimelinePointCount(timeline), 5)
}

@(test)
test_the_tangents_of_the_points_shape_a_hermite_segment_and_are_events :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    lane, _ := TimelineAutomationAdd(timeline, "p", 0, 100)
    a, _ := TimelinePointAdd(timeline, lane, 0, 0)
    b, _ := TimelinePointAdd(timeline, lane, 10, 100)
    testing.expect(t, TimelinePointShape(timeline, a, .HERMITE))
    value, _ := TimelineAutomationValue(timeline, lane, 2.5)
    testing.expect(t, abs(value - 15.625) < 0.001, "no tangents: the smooth step")
    drainTimeline(timeline)
    testing.expect(t, TimelinePointTangents(timeline, a, 0, 2))
    event, _ := TimelinePollEvent(timeline)
    testing.expect(t, event.kind == .POINT_SHAPED && event.point == a && event.tangent_out == 2 && event.previous_tangent_out == 0)
    testing.expect(t, TimelinePointTangents(timeline, b, 0.5, 0))
    value, _ = TimelineAutomationValue(timeline, lane, 5)
    testing.expect(t, abs(value - 100 * CurveEvalTangents(2, 0.5, 0.5)) < 0.001, "the tangent out of the first point and the tangent in of the second")
    testing.expect(t, TimelinePointTangents(timeline, a, 9, -3))
    testing.expect_value(t, TimelinePointGet(timeline, a).tangent_in, TANGENT_LIMIT)
    testing.expect_value(t, TimelinePointGet(timeline, a).tangent_out, 0)
    drainTimeline(timeline)
    testing.expect(t, TimelinePointTangents(timeline, a, TANGENT_LIMIT, 0) && timeline.event_count == 0, "the same is nothing")
    // the plan and the block renderer follow the same cubic
    TimelinePointTangents(timeline, a, 0, 2)
    storage: [4]AutomationSegment
    plan, ok := AutomationCompile(timeline, lane, storage[:])
    testing.expect(t, ok && abs(AutomationValueAt(&plan, 5) - 100 * CurveEvalTangents(2, 0.5, 0.5)) < 0.01)
    worst, _ := maxError(&plan, 0, 1.0 / 48000, 48000 * 10, 512)
    testing.expectf(t, worst <= 2e-2, "the block is the exact value within %v (of a range of 100)", worst)
    // mirrored: the slopes swap ends
    TimelinePointGet(timeline, a).selected, TimelinePointGet(timeline, b).selected = true, true
    TimelinePointsMirror(timeline)
    testing.expect_value(t, TimelinePointGet(timeline, b).tangent_out, 0.5)
    testing.expect_value(t, TimelinePointGet(timeline, a).tangent_in, 2)
}

@(test)
test_a_clip_stretch_works_from_the_snapshot_and_keeps_clips_that_may_not_be_there :: proc(t: ^testing.T) {
    timeline: ^Timeline = newTimeline()
    defer free(timeline)
    timeline.rules.min_length = 0.5
    track, _ := TimelineTrackAdd(timeline, "a")
    a, _ := TimelineClipAdd(timeline, track, 0, 1, "a")
    b, _ := TimelineClipAdd(timeline, track, 2, 2, "b")
    TimelineClipGet(timeline, a).selected, TimelineClipGet(timeline, b).selected = true, true
    TimelineClipsSnapshot(timeline)
    testing.expect_value(t, TimelineClipsStretch(timeline, 0, 2), 2)
    testing.expect_value(t, TimelineClipGet(timeline, b).start, 4)
    testing.expect_value(t, TimelineClipGet(timeline, b).length, 4)
    TimelineClipsStretch(timeline, 0, 2)                                           // again: the same, not 8
    testing.expect_value(t, TimelineClipGet(timeline, b).start, 4)
    // a scale that makes a clip shorter than the least: that clip does not take it, the other one does
    testing.expect_value(t, TimelineClipsStretch(timeline, 0, 0.4), 1)
    testing.expect(t, abs(TimelineClipGet(timeline, b).start - 0.8) < 1e-9 && abs(TimelineClipGet(timeline, b).length - 0.8) < 1e-9)
    testing.expect_value(t, TimelineClipGet(timeline, a).length, 2)                 // it keeps the last place it had
}

@(test)
test_every_level_of_the_ramp_and_the_exponential_kernels_gives_the_same_samples :: proc(t: ^testing.T) {
    for level in su.Level {
        if level > su.CpuBest() || su.LevelFamily(level) != su.LevelFamily(su.CpuBest()) { continue }
        kernels: AutomationKernels = AutomationKernelsOf(level)
        testing.expect(t, kernels.ramp != nil && kernels.exp_run != nil, "a kernel for every level")
        for length in ([?]int{0, 1, 7, 8, 9, 15, 16, 17, 63, 64, 100, 256}) {
            expected, got: [300]f32
            rampBase(expected[:length], 0.25, 0.003)
            kernels.ramp(got[:length], 0.25, 0.003)
            testing.expectf(t, expected == got, "%v: the ramp of %d samples", level, length)
            expected, got = {}, {}
            expBase(expected[:length], 1.3, 1.01, -0.2, 0.7)
            kernels.exp_run(got[:length], 1.3, 1.01, -0.2, 0.7)
            for kind in ([?]AutomationStepKind{.STAIRS, .SMOOTH_STAIRS, .PULSE}) {
                expected, got = {}, {}
                stepsBase(expected[:length], 0.013, 0.0071, kind, 7, true, 1, 3)
                kernels.steps(got[:length], 0.013, 0.0071, kind, 7, true, 1, 3)
                testing.expectf(t, expected == got, "%v: %v of %d samples", level, kind, length)
            }
            for i in 0 ..< length {
                testing.expectf(t, abs(expected[i] - got[i]) <= 1e-5 * max(abs(expected[i]), 1), "%v: the exponential at %d of %d: %v and %v", level, i, length, expected[i], got[i])
            }
        }
    }
}
