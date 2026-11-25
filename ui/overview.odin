package ui

// The overview strip of an arrangement: the whole project in a thin bar, every clip a small block in the row of its track, the sections (verse, chorus) as a coloured band with
// names, and the window of the timeline view as a frame. Dragging the frame scrolls the view, its edges zoom, a press outside centres the frame there.
//
//     overview: ui.Overview = {timeline = &timeline, view = &view, total = 120, sections = sections[:]}      // kept by the program: the style reads it
//     ui.UiOverview(&ctx, "Overview", &overview)
//
// Only `view.origin` and `view.zoom` are changed; the width of the window is the width the timeline was drawn with (`view.rect.z`), so the timeline is drawn before the strip or one frame earlier.
//
// Sections can be marked by the person when the program gives room for them: `sections_buffer` (the storage, the program's) and `section_count`; then Shift + drag on the strip makes a section
// from where the press began to where the pointer is (snapped to `snap` units when it is above 0), Ctrl + click on a section takes it away. `sections_serial` goes up with every such change and
// `last_section` is the index of the section that was made (-1 after a removal), so the program can ask for a name (`sections_buffer[i].name`, alive until UiRender). Without a buffer the
// strip shows `sections` and edits nothing.
//
// Limits: a section is made or removed, not moved or resized afterwards (remove and mark again), no rename in the strip, sections may overlap (the later one is drawn on top); the frame does not scroll the tracks vertically; every clip is one block (no content); `total` is the program's
//     (TimelineEnd(timeline) plus some room when it is 0); a click on a section does not move the playhead.

import "core:math"

OVERVIEW_EDGE :: f32(6)            // the width of the frame edge that zooms
OVERVIEW_MIN_FRACTION :: f64(0.01)   // the frame is at least this part of the whole

OverviewSection :: struct {
    start: f64,
    length: f64,
    name: string,                   // alive until UiRender
    color: Color,                   // alpha 0: the style's own
}

Overview :: struct {
    timeline: ^Timeline,
    view: ^TimelineView,
    total: f64,                     // the length shown; 0: the end of the timeline
    sections: []OverviewSection,
    sections_buffer: []OverviewSection,     // room for the sections the person marks; when it has a length it is what is shown, `section_count` of it
    section_count: int,
    snap: f64,                      // marked sections start and end on multiples of this (0: free)
    sections_serial: u32,
    last_section: int,
}

// The sections that are shown and edited
OverviewSections :: proc(overview: ^Overview) -> []OverviewSection {
    if len(overview.sections_buffer) > 0 { return overview.sections_buffer[:clamp(overview.section_count, 0, len(overview.sections_buffer))] }
    return overview.sections
}

@(private)
overviewSnap :: proc(overview: ^Overview, time: f64) -> f64 {
    if overview.snap <= 0 { return time }
    return math.round(time / overview.snap) * overview.snap
}

// Ctrl + click: the last section that holds the time goes. True when there was one.
OverviewSectionRemoveAt :: proc(overview: ^Overview, time: f64) -> bool {
    count: int = len(OverviewSections(overview))
    for i := count - 1; i >= 0; i -= 1 {
        section: OverviewSection = overview.sections_buffer[i]
        if time >= section.start && time <= section.start + section.length {
            for k in i ..< count - 1 { overview.sections_buffer[k] = overview.sections_buffer[k + 1] }
            overview.section_count = count - 1
            overview.sections_serial += 1
            overview.last_section = -1
            return true
        }
    }
    return false
}

// Shift + drag: the section `index` (-1: a new one) from `anchor` to `time`. The index of the section, -1 when there is no room or the stretch is empty.
OverviewSectionMark :: proc(overview: ^Overview, index: int, anchor: f64, time: f64) -> int {
    total: f64 = OverviewTotal(overview)
    a, b: f64 = overviewSnap(overview, clamp(anchor, 0, total)), overviewSnap(overview, clamp(time, 0, total))
    start, end: f64 = min(a, b), max(a, b)
    if end - start <= 0 { return index }
    at: int = index
    if at < 0 {
        if overview.section_count >= len(overview.sections_buffer) { return -1 }
        at = overview.section_count
        overview.section_count += 1
        overview.sections_buffer[at] = {name = "", color = {}}
    }
    section: ^OverviewSection = &overview.sections_buffer[at]
    if section.start != start || section.length != end - start || index < 0 {
        section.start, section.length = start, end - start
        overview.sections_serial += 1
        overview.last_section = at
    }
    return at
}

// The length the strip covers
OverviewTotal :: proc(overview: ^Overview) -> f64 {
    total: f64 = overview.total
    if total <= 0 && overview.timeline != nil { total = TimelineEnd(overview.timeline) * 1.05 }
    return max(total, 1e-6)
}

// The window of the view in time: where it starts and how long it is
OverviewWindow :: proc(overview: ^Overview) -> (start: f64, length: f64) {
    view: ^TimelineView = overview.view
    zoom: f32 = view.zoom if view.zoom > 0 else TIMELINE_DEFAULT_ZOOM
    return view.origin, f64(view.rect.z / zoom)
}

@(private)
overviewSetWindow :: proc(overview: ^Overview, wanted_start: f64, wanted_length: f64) -> bool {
    total: f64 = OverviewTotal(overview)
    view: ^TimelineView = overview.view
    length: f64 = clamp(wanted_length, total * OVERVIEW_MIN_FRACTION, total)
    start: f64 = clamp(wanted_start, 0, max(total - length, 0))
    zoom: f32 = f32(f64(view.rect.z) / length)
    old: f32 = view.zoom if view.zoom > 0 else TIMELINE_DEFAULT_ZOOM
    if start == view.origin && abs(zoom - old) < 1e-4 { return false }
    view.origin, view.zoom = start, zoom
    return true
}

// `changed` when the window moved or zoomed. Style kind OVERVIEW: value and ratio the window as fractions of the whole (left and right), actual the playhead fraction, user the ^Overview.
UiOverview :: proc(ctx: ^Context, name: string, overview: ^Overview, size: Size = {}, disabled: bool = false) -> (changed: bool) {
    assert(overview != nil && overview.view != nil && overview.timeline != nil)
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id, disabled)
    metrics: ^Metrics = &ctx.style.metrics
    total: f64 = OverviewTotal(overview)
    start, length: f64 = OverviewWindow(overview)
    rect: Rect = state.rect
    if !disabled && interaction.pressed && rect.z > 0 && overview.view.rect.z > 0 {
        at: f64 = f64((ctx.input.mouse_position.x - rect.x) / rect.z) * total
        editing: bool = len(overview.sections_buffer) > 0
        if ctx.input.mouse_pressed { state.cursor = 0 }
        if editing && ctx.input.mouse_pressed && .CTRL in ctx.input.modifiers {
            state.cursor = 5                                    // a Ctrl click only removes
            OverviewSectionRemoveAt(overview, at)
        } else if editing && ctx.input.mouse_pressed && .SHIFT in ctx.input.modifiers {
            state.cursor, state.drag.x, state.anim = 4, f32(at), -1           // marking: `drag.x` is where it began, `anim` the section that follows the pointer
        }
        if state.cursor >= 4 {
            if ctx.input.mouse_down && state.cursor == 4 {
                // a stretch of a few pixels is a click, not a section
                if abs(at - f64(state.drag.x)) > f64(OVERVIEW_EDGE / rect.z) * total || state.anim >= 0 {
                    state.anim = f32(OverviewSectionMark(overview, int(state.anim), f64(state.drag.x), at))
                }
            }
        } else if ctx.input.mouse_pressed {
            edge: f64 = f64(OVERVIEW_EDGE / rect.z) * total
            switch {
            case abs(at - start) <= edge: state.cursor = 1
            case abs(at - (start + length)) <= edge: state.cursor = 2
            case at > start && at < start + length: state.cursor, state.drag.x = 0, f32(at - start)
            case: state.cursor, state.drag.x = 0, f32(length * 0.5)       // outside: the frame comes to the pointer
            }
        }
        if state.cursor < 4 && (ctx.input.mouse_pressed || ctx.input.mouse_down) {
            switch state.cursor {
            case 1: changed = overviewSetWindow(overview, at, start + length - at)
            case 2: changed = overviewSetWindow(overview, start, at - start)
            case: changed = overviewSetWindow(overview, at - f64(state.drag.x), length)
            }
        }
    }
    start, length = OverviewWindow(overview)
    flags: Flags = {.DISABLED} if disabled else {}
    ElementOpen(ctx, {
        id = id,
        layout = {size = widgetSizeOr(size, Grow(), Fixed(metrics.control_height * 1.5))},
        hit = {} if disabled else {.INTERACTIVE},
        cursor = .HAND,
        draw = {
            kind = .OVERVIEW, name = IdSplitName(name), value = f32(start / total), ratio = f32(min((start + length) / total, 1)),
            actual = f32(clamp(overview.view.playhead / total, 0, 1)), user = overview, font_size = metrics.font_size, flags = flags,
        },
    })
    ElementClose(ctx)
    return
}

// Every clip as a rectangle inside `rect`, rows by track: for the style (and the tests)
OverviewClipRect :: proc(overview: ^Overview, rect: Rect, clip: ^TimelineClip) -> (block: Rect, ok: bool) {
    timeline: ^Timeline = overview.timeline
    row: int = TimelineTrackIndex(timeline, clip.track)
    if row < 0 || timeline.track_count == 0 { return }
    total: f64 = OverviewTotal(overview)
    row_height: f32 = rect.w / f32(timeline.track_count)
    x0: f32 = rect.x + f32(clip.start / total) * rect.z
    x1: f32 = rect.x + f32(min((clip.start + clip.length) / total, 1)) * rect.z
    return {x0, rect.y + f32(row) * row_height, max(x1 - x0, 1), max(row_height - 1, 1)}, true
}
