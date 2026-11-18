package ui

// The automation of a track as something an audio thread can render: `AutomationCompile` turns the points of a track into a flat plan of segments (plain data, a copy that the audio thread
// keeps while the person edits the timeline), and `AutomationRender` fills a block of samples with the value for the times of the block. Nothing allocates and nothing searches in the block.
//
//   segments: [512]ui.AutomationSegment                                   // points - 1 of them
//   plan, ok := ui.AutomationCompile(&timeline, track, segments[:])       // on the UI thread, when the automation changed
//   cursor: ui.AutomationCursor                                           // the audio thread keeps one per plan
//   ui.AutomationRender(&plan, &cursor, time_of_first_sample, time_per_sample, block[:])
//
// How it is fast (and what it costs in exactness):
//  - the segment is found once per block by a cursor that only moves forward (a jump back, a loop, a seek is found by one binary search), never by a search per sample;
//  - everything a segment needs is computed when the plan is made (the length's inverse, the difference of the values, the coefficient of its shape: no divisions to set up a block);
//  - HOLD, and the stretches before the first point and after the last one, are a fill of one value;
//  - LINEAR is a ramp: one add per sample (forward differencing), started again from an exact value every AUTOMATION_CHUNK samples so that the rounding of f32 cannot add up;
//  - STAIRS, SMOOTH_STAIRS and PULSE have edges that a ramp would smear: exact at every sample (a few ns each); TRIANGLE and WAVE are continuous: a ramp per run, anchored inside of a run for WAVE;
//  - EXP is one multiply a sample (the ratio of neighbours is constant), started again from an exact e^(c x) every AUTOMATION_CHUNK samples, like the linear ramp;
//  - SMOOTH, CURVE, S_CURVE and HERMITE are evaluated exactly only every few samples (the anchors) and ramped linearly between them. The distance between anchors is a part (1 / 125) of the length of the
//    segment, at most AUTOMATION_ANCHOR samples, so the error is the same small part of the change of the value whatever the length: at most about 5e-5 for SMOOTH, more for a strongly bent CURVE
//    (see the test). A segment shorter than 125 samples is evaluated at every sample, exactly. `AutomationRenderExact` is the per-sample reference.

import "core:math"

AUTOMATION_CHUNK :: 64              // samples between two exact starts of a linear ramp
AUTOMATION_ANCHOR :: 64             // at most this many samples between two exact evaluations of a curved segment
AUTOMATION_ANCHOR_PART :: 125       // a segment has at least this many anchor spaces: the error of the ramps between anchors is about (1 / this)^2 of the bend

AutomationSegment :: struct {
    start: f64,                     // in the unit of the timeline
    end: f64,
    inverse_length: f64,            // 1 / (end - start)
    value: f32,                     // the value at the start
    change: f32,                    // the value at the end minus the one at the start
    coefficient: f32,               // CurveCoefficient of the shape (HERMITE: the slope at the start)
    coefficient2: f32,              // HERMITE: the slope at the end
    shape: CurveShape,
}

AutomationPlan :: struct {
    segments: []AutomationSegment,  // in the order of the time
    first_value: f32,               // before the first point
    last_value: f32,                // after the last one
    valid: bool,                    // false: the track has no points (a block is filled with 0)
}

// Where the last block ended: keep one per plan on the audio thread and give it to every block.
AutomationCursor :: struct {
    index: int,
}

// Makes the plan of an automation track into `storage` (as many segments as the track has points, less one). False when the track is not an automation track, or the storage is too small.
AutomationCompile :: proc(timeline: ^Timeline, track: TrackHandle, storage: []AutomationSegment) -> (plan: AutomationPlan, ok: bool) {
    owner: ^TimelineTrack = TimelineTrackGet(timeline, track)
    if owner == nil || owner.kind != .AUTOMATION { return }
    if owner.point_count == 0 { return {valid = false}, true }
    if len(storage) < max(owner.point_count - 1, 0) { return }
    ordered: [TIMELINE_POINTS]PointHandle
    count: int = TimelineTrackPoints(timeline, track, ordered[:])
    first: ^TimelinePoint = TimelinePointGet(timeline, ordered[0])
    last: ^TimelinePoint = TimelinePointGet(timeline, ordered[count - 1])
    plan.first_value, plan.last_value, plan.valid = first.value, last.value, true
    for i in 0 ..< count - 1 {
        a, b: ^TimelinePoint = TimelinePointGet(timeline, ordered[i]), TimelinePointGet(timeline, ordered[i + 1])
        shape: CurveShape = .HOLD if owner.steps else a.shape
        length: f64 = b.time - a.time
        storage[i] = {
            start = a.time, end = b.time, inverse_length = 1 / length if length > 0 else 0, value = a.value, change = b.value - a.value,
            coefficient = clamp(a.tangent_out, 0, TANGENT_LIMIT) if shape == .HERMITE else CurveCoefficient(shape, TimelineSegmentCurve(owner, shape, a.curve, b.value - a.value)), shape = shape,
            coefficient2 = clamp(b.tangent_in, 0, TANGENT_LIMIT) if shape == .HERMITE else 0,
        }
    }
    plan.segments = storage[:count - 1]
    return plan, true
}

// The index of the segment that holds a time (the last one that starts at or before it), -1 before the first. One binary search.
@(private)
automationSeek :: proc(plan: ^AutomationPlan, time: f64) -> int {
    low, high: int = 0, len(plan.segments)
    for low < high {
        middle: int = (low + high) / 2
        if plan.segments[middle].start <= time { low = middle + 1 } else { high = middle }
    }
    return low - 1
}

@(private)
automationValueIn :: proc(segment: ^AutomationSegment, time: f64) -> f32 {
    x: f32 = f32(clamp((time - segment.start) * segment.inverse_length, 0, 1))
    return segment.value + segment.change * CurveEvalCoefficient(segment.shape, segment.coefficient, x, segment.coefficient2)
}

// The value at one time (a binary search and one evaluation): for a program that wants a value now, and the reference of the tests.
AutomationValueAt :: proc(plan: ^AutomationPlan, time: f64) -> f32 {
    if !plan.valid { return 0 }
    index: int = automationSeek(plan, time)
    if index < 0 { return plan.first_value }
    if index >= len(plan.segments) || time >= plan.segments[index].end {
        return plan.last_value if index >= len(plan.segments) - 1 else automationValueIn(&plan.segments[index], time)
    }
    return automationValueIn(&plan.segments[index], time)
}

// The reference: the exact value of every sample, found by a search for each one. Slow, for tests and for comparing.
AutomationRenderExact :: proc(plan: ^AutomationPlan, time: f64, step: f64, out: []f32) {
    for i in 0 ..< len(out) { out[i] = AutomationValueAt(plan, time + f64(i) * step) }
}

@(private)
fill :: proc(out: []f32, value: f32) {
    for i in 0 ..< len(out) { out[i] = value }
}

// A ramp from `from` to `to` over the samples of `out` (the value of the sample after the last one is `to`).
@(private)
ramp :: proc(out: []f32, from: f32, to: f32) {
    delta: f32 = (to - from) / f32(len(out))
    value: f32 = from
    for i in 0 ..< len(out) {
        out[i] = value
        value += delta
    }
}

// One segment's samples: `out[0]` is at `time` (inside of the segment), `step` is the time of a sample.
@(private)
automationSegmentFill :: proc(segment: ^AutomationSegment, time: f64, step: f64, out: []f32) {
    shape: CurveShape = segment.shape
    if shape == .EXP && abs(segment.coefficient) < CURVE_EXP_LINEAR { shape = .LINEAR }
    switch shape {
    case .HOLD:
        fill(out, segment.value)
    case .EXP:
        // e^(c x) by one multiply a sample (the ratio of two neighbours is constant), started again from an exact exponential every AUTOMATION_CHUNK samples: the rounding of f32 cannot add up
        c: f32 = segment.coefficient
        scale: f32 = segment.change / (math.exp(c) - 1)
        delta_x: f64 = step * segment.inverse_length
        ratio: f32 = math.exp(c * f32(delta_x))
        for start := 0; start < len(out); start += AUTOMATION_CHUNK {
            count: int = min(AUTOMATION_CHUNK, len(out) - start)
            x: f64 = (time - segment.start) * segment.inverse_length + f64(start) * delta_x
            growth: f32 = math.exp(c * f32(clamp(x, 0, 1)))
            for i in 0 ..< count {
                out[start + i] = segment.value + (growth - 1) * scale
                growth *= ratio
            }
        }
    case .LINEAR:
        // forward differencing: one add a sample, from an exact value at the start of every chunk
        delta_x: f64 = step * segment.inverse_length
        delta: f32 = segment.change * f32(delta_x)
        for start := 0; start < len(out); start += AUTOMATION_CHUNK {
            count: int = min(AUTOMATION_CHUNK, len(out) - start)
            x: f64 = (time - segment.start) * segment.inverse_length + f64(start) * delta_x
            value: f32 = segment.value + segment.change * f32(clamp(x, 0, 1))
            for i in 0 ..< count {
                out[start + i] = value
                value += delta
            }
        }
    case .TRIANGLE, .WAVE:
        // continuous: every run (up or down) is a ramp, between exact values at its ends; WAVE is eased inside of a run, so it is anchored like the other curves
        x0: f64 = (time - segment.start) * segment.inverse_length
        delta_x: f64 = step * segment.inverse_length
        runs: f64 = 2 * abs(f64(segment.coefficient)) - 1
        run_samples: f64 = 1 / (runs * delta_x)
        spacing: int = 1 if segment.shape == .TRIANGLE else clamp(int(run_samples / AUTOMATION_ANCHOR_PART), 1, AUTOMATION_ANCHOR)
        evaluate :: proc(segment: ^AutomationSegment, x: f64) -> f32 {
            return segment.value + segment.change * CurveEvalCoefficient(segment.shape, segment.coefficient, f32(clamp(x, 0, 1)), segment.coefficient2)
        }
        i: int
        for i < len(out) {
            x: f64 = x0 + f64(i) * delta_x
            run_end: f64 = (math.floor(x * runs) + 1) / runs
            left: int = clamp(int(math.ceil((run_end - x) / delta_x)), 1, len(out) - i)
            if segment.shape == .TRIANGLE {
                ramp(out[i:i + left], evaluate(segment, x), evaluate(segment, min(x + f64(left) * delta_x, run_end)))
            } else if spacing == 1 {
                for k in 0 ..< left { out[i + k] = evaluate(segment, x + f64(k) * delta_x) }
            } else {
                anchor: f32 = evaluate(segment, x)
                for start := 0; start < left; start += spacing {
                    count: int = min(spacing, left - start)
                    next: f32 = evaluate(segment, min(x + f64(start + count) * delta_x, run_end))
                    ramp(out[i + start:i + start + count], anchor, next)
                    anchor = next
                }
            }
            i += left
        }
    case .STAIRS, .SMOOTH_STAIRS, .PULSE:
        // the edges of these are exact to the sample (a ramp between anchors would smear a step): one evaluation per sample
        x0: f64 = (time - segment.start) * segment.inverse_length
        delta_x: f64 = step * segment.inverse_length
        for i in 0 ..< len(out) {
            out[i] = segment.value + segment.change * CurveEvalCoefficient(segment.shape, segment.coefficient, f32(clamp(x0 + f64(i) * delta_x, 0, 1)), segment.coefficient2)
        }
    case .SMOOTH, .CURVE, .S_CURVE, .HERMITE:
        samples_in_segment: f64 = (segment.end - segment.start) / step
        spacing: int = clamp(int(samples_in_segment / AUTOMATION_ANCHOR_PART), 1, AUTOMATION_ANCHOR)
        x0: f64 = (time - segment.start) * segment.inverse_length
        delta_x: f64 = step * segment.inverse_length
        evaluate :: proc(segment: ^AutomationSegment, x: f64) -> f32 {
            return segment.value + segment.change * CurveEvalCoefficient(segment.shape, segment.coefficient, f32(clamp(x, 0, 1)), segment.coefficient2)
        }
        if spacing == 1 {
            for i in 0 ..< len(out) { out[i] = evaluate(segment, x0 + f64(i) * delta_x) }
            return
        }
        anchor: f32 = evaluate(segment, x0)
        for start := 0; start < len(out); start += spacing {
            count: int = min(spacing, len(out) - start)
            next: f32 = evaluate(segment, x0 + f64(start + count) * delta_x)
            ramp(out[start:start + count], anchor, next)
            anchor = next
        }
    }
}

// How many samples from `first` on (of a block of `length` with the first sample at `time`) are before `limit`: the same test that AutomationValueAt makes for a sample (the time of the
// sample is time + index * step), so the renderer and the reference put a sample in the same segment even where the rounding of the times is not exact.
@(private)
samplesBefore :: proc(time: f64, step: f64, first: int, length: int, limit: f64) -> int {
    count: int = clamp(int(math.ceil((limit - (time + f64(first) * step)) / step)), 0, length - first)
    for count > 0 && time + f64(first + count - 1) * step >= limit { count -= 1 }
    for first + count < length && time + f64(first + count) * step < limit { count += 1 }
    return count
}

// Fills `out` with the automation for the times `time`, `time + step`, ... : the block of the audio thread. `cursor` is where the last block ended (a time that is not where it
// ended, a loop, a seek, is found again by a binary search). A step of 0 or less gives the value of `time` for every sample.
AutomationRender :: proc(plan: ^AutomationPlan, cursor: ^AutomationCursor, time: f64, step: f64, out: []f32) {
    if len(out) == 0 { return }
    if !plan.valid {
        fill(out, 0)
        return
    }
    count: int = len(plan.segments)
    if count == 0 || step <= 0 {
        fill(out, AutomationValueAt(plan, time))
        return
    }
    // the segment of the first sample: the one the cursor is on, the next ones, or a new search when the time went back or far ahead
    index: int = cursor.index
    if index < 0 || index >= count || time < plan.segments[index].start {
        index = max(automationSeek(plan, time), 0)
    } else {
        for index < count - 1 && time >= plan.segments[index].end { index += 1 }
    }
    i: int
    for i < len(out) {
        now: f64 = time + f64(i) * step
        segment: ^AutomationSegment = &plan.segments[index]
        if now < segment.start {
            // before the first point
            samples: int = max(samplesBefore(time, step, i, len(out), segment.start), 1)
            fill(out[i:i + samples], plan.first_value)
            i += samples
            continue
        }
        if now >= segment.end {
            if index < count - 1 {
                index += 1
                continue
            }
            fill(out[i:], plan.last_value)                 // after the last point
            i = len(out)
            break
        }
        samples: int = max(samplesBefore(time, step, i, len(out), segment.end), 1)
        automationSegmentFill(segment, now, step, out[i:i + samples])
        i += samples
        if time + f64(i) * step >= segment.end && index < count - 1 { index += 1 }
    }
    cursor.index = index
}
