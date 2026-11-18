package ui

// A timeline on screen: a ruler, the tracks as lanes, the clips on them and the playhead. The model (timeline.odin) is the program's; the widget draws it and changes it with the
// pointer, the changes come back as events.
//
//     UiTimeline(&ctx, "Arrangement", &timeline, &view, {Grow(), Fixed(260)})
//
// The pointer: a press on the ruler puts the playhead there (and drags it); a press on a clip selects it (Shift adds or removes it) and drags it, with every selected clip, to another
// start or another track; the edges of a clip (`TimelineStyle.edge` pixels) resize it; a press on an empty lane pans (and clears the selection), a double click on an empty lane is an event
// for the program to make a clip; the wheel zooms the time around the pointer (Shift + wheel pans); Delete removes the selected clips. Where a clip may be is decided by the rules of the
// timeline; `view.snap` rounds starts and ends. Clips and lanes are drawn from the model by the style, only the ones in view, so thousands of clips cost the ones on screen.

import "core:math"
import hm "core:container/handle_map"

UI_MAX_TIMELINES :: 4
TIMELINE_ZOOM_MIN :: f32(0.001)             // pixels per unit
TIMELINE_ZOOM_MAX :: f32(100000)
TIMELINE_ZOOM_STEP :: f32(1.15)             // per notch of the wheel
TIMELINE_DEFAULT_ZOOM :: f32(100)
TIMELINE_TRACK_ZOOM_MIN :: f32(0.4)
TIMELINE_TRACK_ZOOM_MAX :: f32(3)

@(private)
TIMELINE_BEND_STEP :: f32(0.1)       // how much a notch of the wheel with Alt bends a lane
TIMELINE_BEND_PIXELS :: f32(60)      // how far the pointer goes to bend a lane from 0 to 1 by the control at its corner

TimelineGesture :: enum u8 {
    NONE,
    PLAYHEAD,
    MOVE,
    RESIZE_LEFT,
    RESIZE_RIGHT,
    PAN,
    BOX,
    LOOP_NEW,
    LOOP_START,
    LOOP_END,
    MARKER,
    POINTS,
    CURVE,
    STRETCH,
    BEND,
}

// What a drag on an empty lane does (Ctrl makes it a box whatever the tool is).
TimelineTool :: enum u8 {
    PAN,                // it pans the view
    BOX,                // it draws a rectangle that selects the clips it touches
}

// What the widget keeps for the program: where it looks, the playhead, the snap. Plain data, so a program can save it with the project.
TimelineView :: struct {
    origin: f64,                // the time at the left edge
    zoom: f32,                  // pixels per unit of time (0 is TIMELINE_DEFAULT_ZOOM)
    scroll: f32,                // how far the tracks are scrolled up, in pixels
    playhead: f64,              // the program moves it while it plays; the pointer moves it on the ruler
    snap: f64,                  // starts and ends are rounded to a multiple of this (0: no snapping)
    value_snap: f32,            // the values of automation points are rounded to a multiple of this, in the unit of the lane (0: no snapping)
    tool: TimelineTool,
    loop_start: f64,            // the loop range: Shift + a drag on the ruler makes one, its edges are dragged; the program plays inside of it when `loop_enabled`
    loop_end: f64,
    loop_enabled: bool,
    track_zoom: f32,            // the heights of the tracks are multiplied by this (0 is 1): Ctrl + the wheel changes it, around the pointer
    snap_to_edges: bool,        // starts and ends also snap to the edges of other clips, the markers and the playhead when they are within `snap_pixels`
    snap_pixels: f32,           // 0: 8
    rect: Rect,                 // where the widget is on the screen (as drawn in the last frame)
    hover_clip: ClipHandle,
    hover_marker: MarkerHandle,
    hover_point: PointHandle,
    gesture_point: PointHandle,
    hover_handle: PointHandle,          // the point whose segment has the handle that is under the pointer
    hover_handle_end: bool,             // HERMITE: it is the second handle of the segment (at its end)
    hover_bend: TrackHandle,            // the lane whose bend control is under the pointer, and which half of it
    hover_bend_fall: bool,
    gesture_bend: TrackHandle,
    gesture_bend_fall: bool,
    bend_start: f32,                    // the bend when the drag began
    rotate_period: f64,                 // the length of the pattern that Alt and the arrows rotate (without a loop), kept from one rotation to the next
    rotate_serial: u64,                 // timeline.serial after the last rotation: another edit makes the length be measured again
    gesture_handle: PointHandle,
    gesture_handle_end: bool,
    history: ^TimelineHistory,          // set: finished edits become steps and Ctrl + Z, Ctrl + Y go through them (timeline_history.odin)
    stretch_anchor: f64,                // Alt and a drag of the first or last selected point stretches the selection: the time that stays
    stretch_far: f64,                   // and the time of the end that is dragged, when it began
    grab_y: f32,
    gesture_marker: MarkerHandle,
    hover_track: int,           // the track under the pointer, -1: none
    // gesture state
    gesture: TimelineGesture,
    gesture_clip: ClipHandle,
    grab_time: f64,
    grab_track: int,
    loop_anchor: f64,
    box_time: f64,              // the corners of the box: a time and a distance from the top of the lanes (before the scroll)
    box_y: f32,
    box_time_to: f64,
    box_y_to: f32,
    last_mouse: Vec2,
}

TimelineFrame :: struct {
    timeline: ^Timeline,
    view: ^TimelineView,
    style: TimelineStyle,
}

// The vertical zoom of a view (1 when it was left at 0).
TimelineViewTrackZoom :: proc(view: ^TimelineView) -> f32 {
    return clamp(view.track_zoom, TIMELINE_TRACK_ZOOM_MIN, TIMELINE_TRACK_ZOOM_MAX) if view.track_zoom > 0 else 1
}

TimelineViewZoom :: proc(view: ^TimelineView) -> f32 {
    return clamp(view.zoom, TIMELINE_ZOOM_MIN, TIMELINE_ZOOM_MAX) if view.zoom > 0 else TIMELINE_DEFAULT_ZOOM
}

// The x on the screen of a time, and the time at an x of the screen.
TimelineX :: proc(view: ^TimelineView, time: f64) -> f32 {
    return view.rect.x + f32((time - view.origin) * f64(TimelineViewZoom(view)))
}

TimelineTime :: proc(view: ^TimelineView, x: f32) -> f64 {
    return view.origin + f64(x - view.rect.x) / f64(TimelineViewZoom(view))
}

// The distance between the major ticks of a ruler (1, 2 or 5 times a power of ten of the unit) so that they are at least `min_pixels` apart.
TimelineRulerStep :: proc(zoom: f32, min_pixels: f32 = 80) -> f64 {
    target: f64 = f64(min_pixels) / f64(max(zoom, TIMELINE_ZOOM_MIN))
    magnitude: f64 = math.pow(10, math.floor(math.log10(target)))
    for factor in ([3]f64{1, 2, 5}) {
        if factor * magnitude >= target { return factor * magnitude }
    }
    return 10 * magnitude
}

// The small control of the bend macro in the top right corner of a lane.
@(private)
timelineBendRect :: proc(lane: Rect) -> Rect {
    return {lane.x + lane.z - 38, lane.y + 4, 32, 16}
}

@(private)
timelineSnapValue :: proc(view: ^TimelineView, value: f32) -> f32 {
    if view.value_snap <= 0 { return value }
    return math.round(value / view.value_snap) * view.value_snap
}

@(private)
timelineSnap :: proc(view: ^TimelineView, time: f64) -> f64 {
    if view.snap <= 0 { return time }
    return math.round(time / view.snap) * view.snap
}

// The nearest edge (a clip start or end, a marker, the playhead) to a time, when it is within the snap distance. Selected clips and markers are skipped when they are the ones being moved.
@(private)
timelineEdgeNear :: proc(timeline: ^Timeline, view: ^TimelineView, time: f64, skip_selected: bool) -> (edge: f64, found: bool) {
    pixels: f32 = view.snap_pixels if view.snap_pixels > 0 else 8
    best: f64 = f64(pixels) / f64(TimelineViewZoom(view))
    consider :: proc(candidate: f64, time: f64, best: ^f64, edge: ^f64, found: ^bool) {
        if abs(candidate - time) <= best^ {
            best^ = abs(candidate - time)
            edge^, found^ = candidate, true
        }
    }
    it := hm.iterator_make(&timeline.clips)
    for clip, _ in hm.iterate(&it) {
        if skip_selected && clip.selected { continue }
        consider(clip.start, time, &best, &edge, &found)
        consider(clip.start + clip.length, time, &best, &edge, &found)
    }
    markers := hm.iterator_make(&timeline.markers)
    for marker, _ in hm.iterate(&markers) {
        if skip_selected && marker.selected { continue }
        consider(marker.time, time, &best, &edge, &found)
    }
    if view.gesture != .PLAYHEAD { consider(view.playhead, time, &best, &edge, &found) }
    return
}

// A time snapped to the edges when that is on, else to the grid.
@(private)
timelineSnapTime :: proc(timeline: ^Timeline, view: ^TimelineView, time: f64, skip_selected: bool) -> f64 {
    if view.snap_to_edges {
        if edge, found := timelineEdgeNear(timeline, view, time, skip_selected); found { return edge }
    }
    return timelineSnap(view, time)
}

// The top and the height of a track from the top of the lanes (before the scroll).
@(private)
timelineTrackRow :: proc(timeline: ^Timeline, style: ^TimelineStyle, index: int) -> (top: f32, height: f32) {
    for i in 0 ..< timeline.track_count {
        track: ^TimelineTrack = TimelineTrackGet(timeline, timeline.order[i])
        height = (track.height if track != nil && track.height > 0 else style.track_height) * (style.track_scale if style.track_scale > 0 else 1)
        if i == index { return }
        top += height
    }
    return top, 0
}

@(private)
timelineTotalHeight :: proc(timeline: ^Timeline, style: ^TimelineStyle) -> f32 {
    top, _ := timelineTrackRow(timeline, style, timeline.track_count)
    return top
}

// The track at a distance from the top of the lanes (before the scroll), -1 when there is none.
@(private)
timelineTrackAt :: proc(timeline: ^Timeline, style: ^TimelineStyle, y: f32) -> int {
    if y < 0 { return -1 }
    top: f32
    for i in 0 ..< timeline.track_count {
        track: ^TimelineTrack = TimelineTrackGet(timeline, timeline.order[i])
        height: f32 = (track.height if track != nil && track.height > 0 else style.track_height) * (style.track_scale if style.track_scale > 0 else 1)
        if y < top + height { return i }
        top += height
    }
    return -1
}

// The part of an automation lane (its rectangle on the screen) that a value can be at.
@(private)
timelineLaneInner :: proc(lane: Rect) -> Rect {
    return {lane.x, lane.y + TIMELINE_LANE_MARGIN, lane.z, max(lane.w - 2 * TIMELINE_LANE_MARGIN, 1)}
}

// Where a point is on the screen, and how far its y is from the lane.
@(private)
timelinePointScreen :: proc(timeline: ^Timeline, view: ^TimelineView, style: ^TimelineStyle, point: ^TimelinePoint) -> Vec2 {
    track: ^TimelineTrack = TimelineTrackGet(timeline, point.track)
    index: int = TimelineTrackIndex(timeline, point.track)
    top, height := timelineTrackRow(timeline, style, index)
    inner: Rect = timelineLaneInner({view.rect.x, view.rect.y + style.ruler_height + top - view.scroll, view.rect.z, height})
    fraction: f32 = (point.value - track.value_min) / (track.value_max - track.value_min)
    return {TimelineX(view, point.time), inner.y + inner.w * (1 - fraction)}
}

// The point nearest to a point of the screen within the radius (a selected point wins over one under it), none for none. Only the lanes that are in view are looked at.
@(private)
timelinePickPoint :: proc(timeline: ^Timeline, view: ^TimelineView, style: ^TimelineStyle, mouse: Vec2) -> (found: PointHandle) {
    best: f32 = style.point_radius * style.point_radius
    best_selected: bool
    it := hm.iterator_make(&timeline.points)
    for point, handle in hm.iterate(&it) {
        position: Vec2 = timelinePointScreen(timeline, view, style, point)
        delta: Vec2 = position - mouse
        distance: f32 = delta.x * delta.x + delta.y * delta.y
        if distance <= best && (distance < best || point.selected && !best_selected) {
            best = distance
            best_selected = point.selected
            found = handle
        }
    }
    return
}

// The point whose segment has its bending handle under the pointer (a segment that is held has none).
@(private)
timelinePickHandle :: proc(timeline: ^Timeline, view: ^TimelineView, style: ^TimelineStyle, mouse: Vec2) -> (found: PointHandle, end: bool) {
    points: [TIMELINE_CURVE_POINTS]CurveEntry
    radius: f32 = style.point_radius
    for i in 0 ..< timeline.track_count {
        track: ^TimelineTrack = TimelineTrackGet(timeline, timeline.order[i])
        if track.kind != .AUTOMATION { continue }
        top, height := timelineTrackRow(timeline, style, i)
        lane: Rect = {view.rect.x, view.rect.y + style.ruler_height + top - view.scroll, view.rect.z, height}
        if mouse.y < lane.y || mouse.y > lane.y + lane.w { continue }
        count: int = timelineLanePoints(timeline, view, style, track, lane, points[:])
        for k in 0 ..< count - 1 {
            a, b: CurveEntry = points[k], points[k + 1]
            if !CurveHasHandle(a.shape) || a.last_in_view { continue }
            positions, handles := CurveHandles(a.shape, a.curve, {a.tangent_out, a.next_tangent_in}, {a.x, a.y}, {b.x, b.y})
            for h in 0 ..< handles {
                delta: Vec2 = positions[h] - mouse
                if delta.x * delta.x + delta.y * delta.y <= radius * radius { found, end = a.point, h == 1 }
            }
        }
    }
    return
}

// The value at a height of the screen on an automation lane, for the lane of a track.
@(private)
timelineValueAt :: proc(timeline: ^Timeline, view: ^TimelineView, style: ^TimelineStyle, track: ^TimelineTrack, index: int, y: f32) -> f32 {
    top, height := timelineTrackRow(timeline, style, index)
    inner: Rect = timelineLaneInner({view.rect.x, view.rect.y + style.ruler_height + top - view.scroll, view.rect.z, height})
    fraction: f32 = clamp(1 - (y - inner.y) / inner.w, 0, 1)
    return track.value_min + fraction * (track.value_max - track.value_min)
}

// The rectangle of a clip on the screen.
TimelineClipRect :: proc(timeline: ^Timeline, view: ^TimelineView, style: ^TimelineStyle, clip: ^TimelineClip) -> Rect {
    index: int = TimelineTrackIndex(timeline, clip.track)
    top, height := timelineTrackRow(timeline, style, index)
    x0: f32 = TimelineX(view, clip.start)
    x1: f32 = TimelineX(view, clip.start + clip.length)
    y: f32 = view.rect.y + style.ruler_height + top - view.scroll
    return {x0, y + 2, max(x1 - x0, 1), max(height - 4, 1)}
}

// The box that is being dragged, on the screen.
@(private)
timelineBoxRect :: proc(view: ^TimelineView, style: ^TimelineStyle) -> Rect {
    x0, x1: f32 = TimelineX(view, view.box_time), TimelineX(view, view.box_time_to)
    top: f32 = view.rect.y + style.ruler_height - view.scroll
    y0, y1: f32 = top + view.box_y, top + view.box_y_to
    return {min(x0, x1), min(y0, y1), abs(x1 - x0), abs(y1 - y0)}
}

TimelineZone :: enum u8 {
    BODY,
    LEFT_EDGE,
    RIGHT_EDGE,
}

// The clip under a point of the screen and which part of it (a selected clip is above the others). None for a point that is on no clip.
@(private)
timelinePick :: proc(timeline: ^Timeline, view: ^TimelineView, style: ^TimelineStyle, point: Vec2) -> (found: ClipHandle, zone: TimelineZone) {
    best_selected: bool
    it := hm.iterator_make(&timeline.clips)
    for clip, handle in hm.iterate(&it) {
        rect: Rect = TimelineClipRect(timeline, view, style, clip)
        if !RectContains(rect, point) { continue }
        if found != {} && best_selected && !clip.selected { continue }
        found = handle
        best_selected = clip.selected
        zone = .BODY
        if rect.z >= style.edge * 3 {
            if point.x - rect.x <= style.edge { zone = .LEFT_EDGE }
            if rect.x + rect.z - point.x <= style.edge { zone = .RIGHT_EDGE }
        }
    }
    return
}

// The timeline widget. True when the person changed something this frame (an event was made).
UiTimeline :: proc(ctx: ^Context, name: string, timeline: ^Timeline, view: ^TimelineView, size: Size = {}) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    style: TimelineStyle = TimelineStyleResolved(ctx.style)
    style.track_scale = TimelineViewTrackZoom(view)
    view.rect = state.rect
    mouse: Vec2 = ctx.input.mouse_position
    shift: bool = .SHIFT in ctx.input.modifiers
    serial_before: u64 = timeline.serial
    delta: Vec2 = mouse - view.last_mouse
    view.last_mouse = mouse
    lanes_top: f32 = view.rect.y + style.ruler_height

    if ctx.hover == id && ctx.input.wheel.y != 0 && view.gesture == .NONE && ctx.disabled_depth == 0 {
        before: f32 = TimelineViewZoom(view)
        if .CTRL in ctx.input.modifiers {
            // Ctrl: the tracks get taller or shorter around the pointer (the track under it stays under it)
            track_before: f32 = TimelineViewTrackZoom(view)
            track_after: f32 = clamp(track_before * math.pow(TIMELINE_ZOOM_STEP, ctx.input.wheel.y), TIMELINE_TRACK_ZOOM_MIN, TIMELINE_TRACK_ZOOM_MAX)
            under: f32 = mouse.y - (view.rect.y + style.ruler_height) + view.scroll
            if under > 0 { view.scroll += under * (track_after / track_before - 1) }
            view.track_zoom = track_after
            style.track_scale = track_after
        } else if .ALT in ctx.input.modifiers {
            // Alt: the bend macro of the automation lane under the pointer (below), nothing else
        } else if shift {
            view.origin -= f64(ctx.input.wheel.y * 60 / before)
        } else {
            after: f32 = clamp(before * math.pow(TIMELINE_ZOOM_STEP, ctx.input.wheel.y), TIMELINE_ZOOM_MIN, TIMELINE_ZOOM_MAX)
            view.origin += f64(mouse.x - view.rect.x) * (1 / f64(before) - 1 / f64(after))
            view.zoom = after
        }
    }
    zoom: f32 = TimelineViewZoom(view)
    view.origin = max(view.origin, 0)
    visible_height: f32 = max(view.rect.w - style.ruler_height, 0)
    view.scroll = clamp(view.scroll, 0, max(timelineTotalHeight(timeline, &style) - visible_height, 0))

    time: f64 = TimelineTime(view, mouse.x)
    row: int = timelineTrackAt(timeline, &style, mouse.y - lanes_top + view.scroll)
    hovering: bool = ctx.hover == id && ctx.disabled_depth == 0 && view.gesture == .NONE
    if hovering && ctx.input.wheel.y != 0 && .ALT in ctx.input.modifiers && mouse.y >= lanes_top && row >= 0 {
        // the wheel with Alt over an automation lane bends all its curves (up: the segments that rise, with Shift: the ones that fall)
        lane: ^TimelineTrack = TimelineTrackGet(timeline, timeline.order[row])
        if lane.kind == .AUTOMATION {
            step: f32 = ctx.input.wheel.y * TIMELINE_BEND_STEP
            TimelineTrackBend(timeline, lane.handle, lane.bend_rise + (0 if shift else step), lane.bend_fall + (step if shift else 0))
        }
    }
    view.hover_clip, view.hover_track = {}, -1
    zone: TimelineZone
    if hovering && mouse.y >= lanes_top {
        view.hover_clip, zone = timelinePick(timeline, view, &style, mouse)
        view.hover_track = row
    }
    min_length: f64 = max(timeline.rules.min_length, 4 / f64(zoom))
    view.hover_point = {}
    view.hover_handle, view.hover_handle_end = {}, false
    view.hover_bend = {}
    if hovering && mouse.y >= lanes_top && row >= 0 {
        lane_track: ^TimelineTrack = TimelineTrackGet(timeline, timeline.order[row])
        top, height := timelineTrackRow(timeline, &style, row)
        lane_rect: Rect = {view.rect.x, view.rect.y + style.ruler_height + top - view.scroll, view.rect.z, height}
        if lane_track.kind == .AUTOMATION && RectContains(timelineBendRect(lane_rect), mouse) {
            view.hover_bend = lane_track.handle
            view.hover_bend_fall = mouse.x > timelineBendRect(lane_rect).x + 16
        }
    }
    if hovering && mouse.y >= lanes_top {
        view.hover_point = timelinePickPoint(timeline, view, &style, mouse)
        if view.hover_point == {} { view.hover_handle, view.hover_handle_end = timelinePickHandle(timeline, view, &style, mouse) }
    }
    // the marker whose flag is under the pointer (on the ruler, in the upper half of it)
    view.hover_marker = {}
    if (hovering || view.gesture == .NONE) && ctx.hover == id && mouse.y >= view.rect.y && mouse.y < view.rect.y + style.ruler_height * 0.5 {
        markers := hm.iterator_make(&timeline.markers)
        for marker, handle in hm.iterate(&markers) {
            x: f32 = TimelineX(view, marker.time)
            if mouse.x >= x - 3 && mouse.x <= x + style.marker_width { view.hover_marker = handle }
        }
    }

    if interaction.pressed && ctx.input.mouse_pressed && view.gesture == .NONE {
        ctrl: bool = .CTRL in ctx.input.modifiers
        switch {
        case view.hover_bend != {}:
            lane: ^TimelineTrack = TimelineTrackGet(timeline, view.hover_bend)
            view.gesture, view.gesture_bend, view.gesture_bend_fall = .BEND, view.hover_bend, view.hover_bend_fall
            view.grab_y, view.bend_start = mouse.y, lane.bend_fall if view.hover_bend_fall else lane.bend_rise
        case view.hover_marker != {}:
            marker: ^TimelineMarker = TimelineMarkerGet(timeline, view.hover_marker)
            if shift {
                marker.selected = !marker.selected
            } else if !marker.selected {
                TimelineSelectClear(timeline)
                marker.selected = true
            }
            if marker.selected {
                view.gesture, view.gesture_marker = .MARKER, view.hover_marker
            }
        case mouse.y < lanes_top:
            if interaction.double_clicked {
                timelineEmit(timeline, {kind = .RULER_DOUBLE_CLICK, time = max(timelineSnapTime(timeline, view, time, false), 0)})
            }
            near_start: f32 = abs(TimelineX(view, view.loop_start) - mouse.x)
            near_end: f32 = abs(TimelineX(view, view.loop_end) - mouse.x)
            switch {
            case view.loop_enabled && min(near_start, near_end) <= style.edge:
                view.gesture = .LOOP_START if near_start <= near_end else .LOOP_END
            case shift:
                view.gesture = .LOOP_NEW
                view.loop_anchor = max(timelineSnapTime(timeline, view, time, false), 0)
            case:
                view.gesture = .PLAYHEAD
            }
        case view.hover_point != {}:
            point: ^TimelinePoint = TimelinePointGet(timeline, view.hover_point)
            if ctrl {
                // Ctrl and a click: the next shape for the curve that leaves the point
                TimelineSelectClear(timeline)
                point.selected = true
                TimelinePointShape(timeline, view.hover_point, CurveShapeNext(point.shape), point.curve)
            } else if shift {
                point.selected = !point.selected
            } else if !point.selected {
                TimelineSelectClear(timeline)
                point.selected = true
            }
            if point.selected && !ctrl {
                view.gesture, view.gesture_point = .POINTS, view.hover_point
                view.grab_time, view.grab_y = time, mouse.y
                TimelinePointsSnapshot(timeline)
                // Alt on an end of a selection of several: the selection is stretched from the other end instead of moved
                if .ALT in ctx.input.modifiers && !shift {
                    first, last: f64 = f64(INFINITE), -1
                    count: int
                    points := hm.iterator_make(&timeline.points)
                    for other, _ in hm.iterate(&points) {
                        if other.selected { first, last, count = min(first, other.time), max(last, other.time), count + 1 }
                    }
                    if count >= 2 && last > first && (point.time == first || point.time == last) {
                        view.gesture = .STRETCH
                        view.stretch_anchor, view.stretch_far = (last if point.time == first else first), point.time
                    }
                }
            }
        case view.hover_handle != {}:
            view.gesture, view.gesture_handle, view.gesture_handle_end = .CURVE, view.hover_handle, view.hover_handle_end
        case row >= 0 && TimelineTrackGet(timeline, timeline.order[row]).kind == .AUTOMATION && interaction.double_clicked && !ctrl && view.tool != .BOX:
            // a double click on an automation lane puts a point there
            lane: ^TimelineTrack = TimelineTrackGet(timeline, timeline.order[row])
            added, ok := TimelinePointAdd(timeline, lane.handle, max(timelineSnapTime(timeline, view, time, false), 0), timelineSnapValue(view, timelineValueAt(timeline, view, &style, lane, row, mouse.y)))
            if ok {
                TimelineSelectClear(timeline)
                TimelinePointGet(timeline, added).selected = true
            }
        case view.hover_clip != {}:
            clip: ^TimelineClip = TimelineClipGet(timeline, view.hover_clip)
            locked: bool = TimelineTrackGet(timeline, clip.track).flags >= {.LOCKED}
            if shift {
                clip.selected = !clip.selected
            } else if !clip.selected {
                TimelineSelectClear(timeline)
                clip.selected = true
            }
            if clip.selected && !locked {
                view.gesture_clip = view.hover_clip
                view.grab_time, view.grab_track = time, row
                switch zone {
                case .BODY: view.gesture = .MOVE
                case .LEFT_EDGE: view.gesture = .RESIZE_LEFT
                case .RIGHT_EDGE: view.gesture = .RESIZE_RIGHT
                }
                it := hm.iterator_make(&timeline.clips)
                for other, _ in hm.iterate(&it) {
                    other.drag_start, other.drag_length = other.start, other.length
                    other.drag_track = TimelineTrackIndex(timeline, other.track)
                }
            }
        case view.tool == .BOX || ctrl:
            view.gesture = .BOX
            view.box_time, view.box_y = time, mouse.y - lanes_top + view.scroll
            view.box_time_to, view.box_y_to = view.box_time, view.box_y
            it := hm.iterator_make(&timeline.clips)
            for other, _ in hm.iterate(&it) {
                if !shift { other.selected = false }
                other.drag_selected = other.selected
            }
            points := hm.iterator_make(&timeline.points)
            for other, _ in hm.iterate(&points) {
                if !shift { other.selected = false }
                other.drag_selected = other.selected
            }
        case:
            view.gesture = .PAN
            if !shift { TimelineSelectClear(timeline) }
            if interaction.double_clicked && row >= 0 {
                timelineEmit(timeline, {kind = .EMPTY_DOUBLE_CLICK, track = timeline.order[row], time = max(timelineSnapTime(timeline, view, time, false), 0)})
            }
        }
    }

    if view.gesture != .NONE {
        if (ctx.input.mouse_down || ctx.input.mouse_released) && !ctx.input.mouse_pressed {
            clip: ^TimelineClip = TimelineClipGet(timeline, view.gesture_clip)
            switch view.gesture {
            case .PLAYHEAD:
                moved: f64 = max(timelineSnapTime(timeline, view, time, false), 0)
                if moved != view.playhead {
                    view.playhead = moved
                    timelineEmit(timeline, {kind = .PLAYHEAD, time = moved})
                }
            case .BOX:
                view.box_time_to, view.box_y_to = time, mouse.y - lanes_top + view.scroll
                box: Rect = timelineBoxRect(view, &style)
                it := hm.iterator_make(&timeline.clips)
                for other, _ in hm.iterate(&it) {
                    other.selected = other.drag_selected || RectOverlaps(TimelineClipRect(timeline, view, &style, other), box)
                }
                points := hm.iterator_make(&timeline.points)
                for other, _ in hm.iterate(&points) {
                    other.selected = other.drag_selected || RectContains(box, timelinePointScreen(timeline, view, &style, other))
                }
            case .LOOP_NEW:
                a, b: f64 = view.loop_anchor, max(timelineSnapTime(timeline, view, time, false), 0)
                start, end: f64 = min(a, b), max(a, b)
                if end - start >= min_length && (start != view.loop_start || end != view.loop_end || !view.loop_enabled) {
                    view.loop_start, view.loop_end, view.loop_enabled = start, end, true
                    timelineEmit(timeline, {kind = .LOOP_CHANGED, start = start, length = end - start})
                }
            case .LOOP_START:
                start: f64 = clamp(timelineSnapTime(timeline, view, time, false), 0, view.loop_end - min_length)
                if start != view.loop_start {
                    view.loop_start = start
                    timelineEmit(timeline, {kind = .LOOP_CHANGED, start = start, length = view.loop_end - start})
                }
            case .LOOP_END:
                end: f64 = max(timelineSnapTime(timeline, view, time, false), view.loop_start + min_length)
                if end != view.loop_end {
                    view.loop_end = end
                    timelineEmit(timeline, {kind = .LOOP_CHANGED, start = view.loop_start, length = end - view.loop_start})
                }
            case .CURVE:
                if owner := TimelinePointGet(timeline, view.gesture_handle); owner != nil {
                    track: ^TimelineTrack = TimelineTrackGet(timeline, owner.track)
                    index: int = TimelineTrackIndex(timeline, owner.track)
                    top, height := timelineTrackRow(timeline, &style, index)
                    lane: Rect = {view.rect.x, view.rect.y + style.ruler_height + top - view.scroll, view.rect.z, height}
                    points: [TIMELINE_CURVE_POINTS]CurveEntry
                    count: int = timelineLanePoints(timeline, view, &style, track, lane, points[:])
                    for k in 0 ..< count - 1 {
                        if points[k].point != view.gesture_handle || points[k + 1].y == points[k].y { continue }
                        if points[k].shape == .HERMITE {
                            // a control point of the Bezier curve: its height says the slope (a third of the way, so three times the rise over the change of the value)
                            change: f32 = points[k + 1].y - points[k].y
                            if !view.gesture_handle_end {
                                TimelinePointTangents(timeline, view.gesture_handle, owner.tangent_in, (mouse.y - points[k].y) * 3 / change)
                            } else if next := TimelinePointGet(timeline, points[k + 1].point); next != nil {
                                TimelinePointTangents(timeline, points[k + 1].point, (points[k + 1].y - mouse.y) * 3 / change, next.tangent_out)
                            }
                            continue
                        }
                        // the part of the way from this value to the next that the handle is at; a segment that was straight or smooth becomes a bias when it is bent
                        covered: f32 = clamp((mouse.y - points[k].y) / (points[k + 1].y - points[k].y), 0.02, 0.98)
                        shape: CurveShape = owner.shape if owner.shape == .S_CURVE || owner.shape == .EXP || CurveIsCounted(owner.shape) else .CURVE
                        // the sign of a count is the variant (a pulse that starts high): the handle sets the number only
                        sign: f32 = -1 if CurveIsCounted(shape) && owner.curve < 0 else 1
                        TimelinePointShape(timeline, view.gesture_handle, shape, sign * CurveFromHandle(shape, covered) - (points[k].bend if !CurveIsCounted(shape) else 0))
                    }
                }
            case .BEND:
                if lane := TimelineTrackGet(timeline, view.gesture_bend); lane != nil {
                    bend: f32 = view.bend_start + (view.grab_y - mouse.y) / TIMELINE_BEND_PIXELS
                    if view.gesture_bend_fall {
                        TimelineTrackBend(timeline, view.gesture_bend, lane.bend_rise, bend)
                    } else {
                        TimelineTrackBend(timeline, view.gesture_bend, bend, lane.bend_fall)
                    }
                }
            case .STRETCH:
                if primary := TimelinePointGet(timeline, view.gesture_point); primary != nil {
                    // sideways: the distance from the end that stays; up: the far end of the selection is taller (the factor is 1 at the end that stays)
                    scale: f64 = (time - view.stretch_anchor) / (view.grab_time - view.stretch_anchor) if view.grab_time != view.stretch_anchor else 1
                    row_index: int = TimelineTrackIndex(timeline, primary.track)
                    _, lane_height := timelineTrackRow(timeline, &style, row_index)
                    end_factor: f32 = 1 - 2 * (mouse.y - view.grab_y) / max(lane_height - 2 * TIMELINE_LANE_MARGIN, 1)
                    TimelinePointsStretch(timeline, view.stretch_anchor, scale, end_factor)
                }
            case .POINTS:
                if primary := TimelinePointGet(timeline, view.gesture_point); primary != nil {
                    shift_time: f64 = timelineSnapTime(timeline, view, primary.drag_time + (time - view.grab_time), true) - primary.drag_time
                    earliest: f64 = f64(INFINITE)
                    points := hm.iterator_make(&timeline.points)
                    for other, _ in hm.iterate(&points) {
                        if other.selected { earliest = min(earliest, other.drag_time) }
                    }
                    shift_time = max(shift_time, -earliest)
                    // the same part of the height of a lane for every point (each lane has its own range of values)
                    row_index: int = TimelineTrackIndex(timeline, primary.track)
                    _, lane_height := timelineTrackRow(timeline, &style, row_index)
                    fraction: f32 = -(mouse.y - view.grab_y) / max(lane_height - 2 * TIMELINE_LANE_MARGIN, 1)
                    if view.value_snap > 0 {
                        // the grabbed point lands on the grid, the others keep their distance to it (as a part of the height of their lane)
                        range: f32 = TimelineTrackGet(timeline, primary.track).value_max - TimelineTrackGet(timeline, primary.track).value_min
                        fraction = (timelineSnapValue(view, primary.drag_value + fraction * range) - primary.drag_value) / range
                    }
                    points = hm.iterator_make(&timeline.points)
                    for other, handle in hm.iterate(&points) {
                        if !other.selected { continue }
                        owner: ^TimelineTrack = TimelineTrackGet(timeline, other.track)
                        TimelinePointMove(timeline, handle, other.drag_time + shift_time, other.drag_value + fraction * (owner.value_max - owner.value_min))
                    }
                }
            case .MARKER:
                if marker := TimelineMarkerGet(timeline, view.gesture_marker); marker != nil {
                    TimelineMarkerMove(timeline, view.gesture_marker, max(timelineSnapTime(timeline, view, time, true), 0))
                }
            case .PAN:
                view.origin = max(view.origin - f64(delta.x / zoom), 0)
                view.scroll = clamp(view.scroll - delta.y, 0, max(timelineTotalHeight(timeline, &style) - visible_height, 0))
            case .MOVE:
                if clip != nil {
                    raw: f64 = clip.drag_start + (time - view.grab_time)
                    target_start: f64 = timelineSnap(view, raw)
                    if view.snap_to_edges {
                        // the start or the end of the clip, whichever is nearer to an edge
                        near_start, found_start := timelineEdgeNear(timeline, view, raw, true)
                        near_end, found_end := timelineEdgeNear(timeline, view, raw + clip.length, true)
                        distance_start: f64 = abs(near_start - raw) if found_start else f64(INFINITE)
                        distance_end: f64 = abs(near_end - (raw + clip.length)) if found_end else f64(INFINITE)
                        if found_start && distance_start <= distance_end {
                            target_start = near_start
                        } else if found_end {
                            target_start = near_end - clip.length
                        }
                    }
                    shift_time: f64 = target_start - clip.drag_start
                    earliest: f64 = f64(INFINITE)
                    it := hm.iterator_make(&timeline.clips)
                    for other, _ in hm.iterate(&it) {
                        if other.selected { earliest = min(earliest, other.drag_start) }
                    }
                    shift_time = max(shift_time, -earliest)
                    track_shift: int = (row - view.grab_track) if row >= 0 else 0
                    it = hm.iterator_make(&timeline.clips)
                    for other, handle in hm.iterate(&it) {
                        if !other.selected { continue }
                        target: int = clamp(other.drag_track + track_shift, 0, timeline.track_count - 1)
                        destination: TrackHandle = timeline.order[target]
                        if TimelineTrackGet(timeline, destination).flags >= {.LOCKED} { destination = other.track }
                        TimelineClipPlace(timeline, handle, destination, other.drag_start + shift_time, other.length)
                    }
                }
            case .RESIZE_RIGHT:
                if clip != nil {
                    end: f64 = max(timelineSnapTime(timeline, view, time, true), clip.start + min_length)
                    TimelineClipPlace(timeline, view.gesture_clip, clip.track, clip.start, end - clip.start)
                }
            case .RESIZE_LEFT:
                if clip != nil {
                    end: f64 = clip.drag_start + clip.drag_length
                    start: f64 = clamp(timelineSnapTime(timeline, view, time, true), 0, end - min_length)
                    TimelineClipPlace(timeline, view.gesture_clip, clip.track, start, end - start)
                }
            case .NONE:
            }
        }
        if ctx.input.mouse_released || !ctx.input.mouse_down {
            view.gesture, view.gesture_clip, view.gesture_marker, view.gesture_point, view.gesture_handle, view.gesture_bend = .NONE, {}, {}, {}, {}, {}
        }
    }

    if .DELETE in ctx.input.keys && (ctx.focus == 0 || ctx.focus == id) {
        for removed := true; removed; {
            removed = false
            it := hm.iterator_make(&timeline.points)
            for point, handle in hm.iterate(&it) {
                if point.selected {
                    TimelinePointRemove(timeline, handle)
                    removed = true
                    break
                }
            }
        }
        for removed := true; removed; {
            removed = false
            it := hm.iterator_make(&timeline.markers)
            for marker, handle in hm.iterate(&it) {
                if marker.selected {
                    TimelineMarkerRemove(timeline, handle)
                    removed = true
                    break
                }
            }
        }
        for removed := true; removed; {
            removed = false
            it := hm.iterator_make(&timeline.clips)
            for clip, handle in hm.iterate(&it) {
                if clip.selected {
                    TimelineClipRemove(timeline, handle)
                    removed = true
                    break
                }
            }
        }
    }

    // copy, cut, paste and select all while the timeline has the focus: a paste goes to the playhead, on the track under the pointer when it is on a lane
    if ctx.focus == id && ctx.disabled_depth == 0 {
        actions: Actions = ctx.input.actions
        if view.history != nil && view.gesture == .NONE {
            if .UNDO in actions { TimelineHistoryUndo(view.history, timeline) }
            if .REDO in actions { TimelineHistoryRedo(view.history, timeline) }
        }
        if .SELECT_ALL in actions {
            it := hm.iterator_make(&timeline.clips)
            for clip, _ in hm.iterate(&it) { clip.selected = true }
        }
        // selected points are what is copied when no clip is selected
        points_win: bool = TimelineSelectedCount(timeline) == 0 && TimelineSelectedPoints(timeline) > 0
        if (.COPY in actions || .CUT in actions) && points_win {
            TimelineCopyPoints(timeline)
            if .CUT in actions { TimelinePointsRemove(timeline) }
        } else if .COPY in actions || .CUT in actions {
            TimelineCopy(timeline)
            timeline.copy_is_points = false
        }
        if .CUT in actions && !points_win {
            for removed := true; removed; {
                removed = false
                it := hm.iterator_make(&timeline.clips)
                for clip, handle in hm.iterate(&it) {
                    if clip.selected {
                        TimelineClipRemove(timeline, handle)
                        removed = true
                        break
                    }
                }
            }
        }
        if .DUPLICATE in actions && TimelineSelectedCount(timeline) > 0 {
            // a copy of the selected clips right after the last of them, on the tracks they are on
            last_end: f64
            it := hm.iterator_make(&timeline.clips)
            for clip, _ in hm.iterate(&it) {
                if clip.selected { last_end = max(last_end, clip.start + clip.length) }
            }
            TimelineCopy(timeline)
            TimelinePaste(timeline, last_end)
        }
        if (.ROTATE_LEFT in actions || .ROTATE_RIGHT in actions) && view.gesture == .NONE {
            // around the loop when there is one, else around the whole timeline and one more step (so that the last point has a place): a step of the snap (1 without one)
            step: f64 = view.snap if view.snap > 0 else 1
            from, to: f64 = 0, 0
            if view.loop_enabled {
                from, to = view.loop_start, view.loop_end
            } else {
                // the length of the pattern is kept while only rotating (the points move, the end would): it is measured again after any other edit
                if timeline.serial != view.rotate_serial || view.rotate_period <= 0 { view.rotate_period = TimelineEnd(timeline) + step }
                to = view.rotate_period
            }
            TimelinePointsRotate(timeline, from, max(to, from + step), -step if .ROTATE_LEFT in actions else step)
            view.rotate_serial = timeline.serial
        }
        if .INVERT in actions { TimelinePointsFlip(timeline) }
        if .REVERSE in actions { TimelinePointsMirror(timeline) }
        if .REPEAT in actions { TimelinePointsRepeat(timeline, max(view.snap, 1)) }
        if .PASTE in actions && timeline.copy_is_points {
            lane: int = row if mouse.y >= lanes_top && row >= 0 && ctx.hover == id else -1
            TimelinePastePoints(timeline, max(timelineSnapTime(timeline, view, view.playhead, false), 0), lane)
        } else if .PASTE in actions {
            lane: int = row if mouse.y >= lanes_top && row >= 0 && ctx.hover == id else -1
            TimelinePaste(timeline, max(timelineSnapTime(timeline, view, view.playhead, false), 0), lane)
        }
    }

    index: int = ctx.timeline_frame_count
    if index >= UI_MAX_TIMELINES {
        ctx.problems += {.GRAPH_MISUSE}
        index = UI_MAX_TIMELINES - 1
    } else {
        ctx.timeline_frame_count += 1
    }
    ctx.timeline_frames[index] = {timeline = timeline, view = view, style = style}
    ElementOpen(ctx, {
        id = id,
        layout = {size = {size.width if size.width != {} else Grow(), size.height if size.height != {} else Grow()}},
        clip = {horizontal = true, vertical = true, cut = true},
        hit = {.INTERACTIVE, .SCROLL},
        cursor = .RESIZE_HORIZONTAL if view.hover_clip != {} && zone != .BODY else .ARROW,
        draw = {kind = .TIMELINE, name = IdSplitName(name), user = &ctx.timeline_frames[index]},
    })
    ElementClose(ctx)
    // an edit that is finished (no gesture is going on) is a step of the history
    if view.history != nil && view.gesture == .NONE { TimelineHistoryCommit(view.history, timeline) }
    return timeline.serial != serial_before
}

// Fits the whole timeline in the width of the widget (as it was drawn in the last frame): `margin` units after the last clip.
TimelineViewFit :: proc(timeline: ^Timeline, view: ^TimelineView, margin: f64 = 0) {
    end: f64 = TimelineEnd(timeline) + margin
    if end <= 0 || view.rect.z <= 0 { return }
    view.origin = 0
    view.zoom = clamp(view.rect.z / f32(end), TIMELINE_ZOOM_MIN, TIMELINE_ZOOM_MAX)
}

// ------------------------------------------------------------------------------------------------------------------------
// For the styles: what is drawn

// Draws the lanes, the clips (the selected ones above), the ruler and the playhead of a TIMELINE element through the procs of `TimelineStyle`. A style's TIMELINE proc calls this after its background.
TimelineDraw :: proc(ctx: ^Context, info: ^DrawInfo) {
    frame: ^TimelineFrame = cast(^TimelineFrame)info.user
    if frame == nil { return }
    timeline, view, style := frame.timeline, frame.view, &frame.style
    area: Rect = info.rect
    lanes_top: f32 = area.y + style.ruler_height
    if style.draw_lane != nil {
        for i in 0 ..< timeline.track_count {
            track: ^TimelineTrack = TimelineTrackGet(timeline, timeline.order[i])
            top, height := timelineTrackRow(timeline, style, i)
            y: f32 = lanes_top + top - view.scroll
            if y + height < lanes_top || y > area.y + area.w { continue }
            lane: LaneDraw = {rect = {area.x, y, area.z, height}, name = TimelineTrackName(track), color = track.color, index = i, track = track.handle, user = style.user}
            if .MUTED in track.flags { lane.flags += {.DISABLED} }
            if .LOCKED in track.flags { lane.flags += {.ON} }
            if view.hover_track == i { lane.flags += {.HOVERED} }
            lane.automation = track.kind == .AUTOMATION
            style.draw_lane(ctx, &lane)
            if lane.automation && style.draw_curve != nil { timelineDrawCurve(ctx, timeline, view, style, track, lane.rect) }
        }
    }
    if style.draw_clip != nil {
        for pass in 0 ..< 2 {
            it := hm.iterator_make(&timeline.clips)
            for clip, handle in hm.iterate(&it) {
                if clip.selected != (pass == 1) { continue }
                rect: Rect = TimelineClipRect(timeline, view, style, clip)
                if !RectOverlaps(rect, {area.x, lanes_top, area.z, area.w - style.ruler_height}) { continue }
                track: ^TimelineTrack = TimelineTrackGet(timeline, clip.track)
                draw: ClipDraw = {
                    rect = rect, visible = {area.x, lanes_top, area.z, area.w - style.ruler_height}, name = TimelineClipName(clip), color = clip.color if clip.color.a > 0 else track.color,
                    clip = handle, track = clip.track, track_index = TimelineTrackIndex(timeline, clip.track), start = clip.start, length = clip.length, user = style.user,
                }
                if clip.selected { draw.flags += {.SELECTED} }
                if view.hover_clip == handle { draw.flags += {.HOVERED} }
                if view.gesture_clip == handle && view.gesture != .NONE { draw.flags += {.PRESSED} }
                if .MUTED in track.flags { draw.flags += {.DISABLED} }
                style.draw_clip(ctx, &draw)
            }
        }
    }
    if style.draw_box != nil && view.gesture == .BOX {
        box: BoxDraw = {rect = timelineBoxRect(view, style), user = style.user}
        style.draw_box(ctx, &box)
    }
    if style.draw_ruler != nil {
        zoom: f32 = TimelineViewZoom(view)
        ruler: RulerDraw = {
            rect = {area.x, area.y, area.z, style.ruler_height}, origin = view.origin, zoom = zoom, step = TimelineRulerStep(zoom),
            loop_enabled = view.loop_enabled, loop_x = TimelineX(view, view.loop_start), loop_end_x = TimelineX(view, view.loop_end), user = style.user,
        }
        style.draw_ruler(ctx, &ruler)
    }
    if style.draw_marker != nil {
        it := hm.iterator_make(&timeline.markers)
        for marker, handle in hm.iterate(&it) {
            x: f32 = TimelineX(view, marker.time)
            if x < area.x - style.marker_width || x > area.x + area.z { continue }
            draw: MarkerDraw = {
                x = x, ruler = {area.x, area.y, area.z, style.ruler_height}, area = area, name = TimelineMarkerName(marker), color = marker.color, marker = handle,
                time = marker.time, width = style.marker_width, user = style.user,
            }
            if marker.selected { draw.flags += {.SELECTED} }
            if view.hover_marker == handle { draw.flags += {.HOVERED} }
            if view.gesture_marker == handle && view.gesture == .MARKER { draw.flags += {.PRESSED} }
            style.draw_marker(ctx, &draw)
        }
    }
    if style.draw_playhead != nil {
        x: f32 = TimelineX(view, view.playhead)
        if x >= area.x && x <= area.x + area.z {
            head: PlayheadDraw = {x = x, rect = {area.x, area.y, area.z, area.w}, ruler_height = style.ruler_height, time = view.playhead, user = style.user}
            if view.gesture == .PLAYHEAD { head.flags += {.PRESSED} }
            style.draw_playhead(ctx, &head)
        }
    }
}

// One point of a lane for the drawing and the picking: the screen place and what the segment after it is.
@(private)
CurveEntry :: struct {
    x: f32,
    y: f32,
    point: PointHandle,
    time: f64,
    value: f32,
    shape: CurveShape,
    curve: f32,
    tangent_in: f32,
    tangent_out: f32,
    next_tangent_in: f32,       // the slope at the end of the segment that leaves this point (HERMITE)
    selected: bool,
    bend: f32,                  // what the bend macro of the track added to `curve` (the handle is where the segment really is, a drag takes it off again)
    last_in_view: bool,         // the last point of the list: no segment leaves it
}

// Gathers the points of an automation lane that are in view (and one on each side) in the order of their time. How many (at most len(points)).
@(private)
timelineLanePoints :: proc(timeline: ^Timeline, view: ^TimelineView, style: ^TimelineStyle, track: ^TimelineTrack, lane: Rect, points: []CurveEntry) -> int {
    count: int
    left, right: f64 = TimelineTime(view, lane.x), TimelineTime(view, lane.x + lane.z)
    before, after: ^TimelinePoint
    inner: Rect = timelineLaneInner(lane)
    range: f32 = track.value_max - track.value_min
    entry_of :: proc(point: ^TimelinePoint, view: ^TimelineView, track: ^TimelineTrack, inner: Rect, range: f32) -> CurveEntry {
        return {
            x = TimelineX(view, point.time), y = inner.y + inner.w * (1 - (point.value - track.value_min) / range), point = point.handle, time = point.time, value = point.value,
            shape = .HOLD if track.steps else point.shape, curve = point.curve, tangent_in = point.tangent_in, tangent_out = point.tangent_out, selected = point.selected,
        }
    }
    it := hm.iterator_make(&timeline.points)
    for point, _ in hm.iterate(&it) {
        if point.track != track.handle { continue }
        if point.time < left {
            if before == nil || point.time > before.time { before = point }
            continue
        }
        if point.time > right {
            if after == nil || point.time < after.time { after = point }
            continue
        }
        if count >= len(points) - 2 { continue }
        entry: CurveEntry = entry_of(point, view, track, inner, range)
        position: int = count
        for position > 0 && points[position - 1].time > entry.time {
            points[position] = points[position - 1]
            position -= 1
        }
        points[position] = entry
        count += 1
    }
    if before != nil {
        copy(points[1:count + 1], points[:count])
        points[0] = entry_of(before, view, track, inner, range)
        count += 1
    }
    if after != nil {
        points[count] = entry_of(after, view, track, inner, range)
        count += 1
    }
    for i in 0 ..< count - 1 {
        points[i].next_tangent_in = points[i + 1].tangent_in
        // the curve of the segment as the track bends it: the handle and the line are where it really is
        real: f32 = TimelineSegmentCurve(track, points[i].shape, points[i].curve, points[i + 1].value - points[i].value)
        points[i].bend, points[i].curve = real - points[i].curve, real
    }
    if count > 0 { points[count - 1].last_in_view = true }
    return count
}

// Gives the style the curve of an automation lane.
@(private)
timelineDrawCurve :: proc(ctx: ^Context, timeline: ^Timeline, view: ^TimelineView, style: ^TimelineStyle, track: ^TimelineTrack, lane: Rect) {
    entries: [TIMELINE_CURVE_POINTS]CurveEntry
    points: [TIMELINE_CURVE_POINTS]CurvePoint
    count: int = timelineLanePoints(timeline, view, style, track, lane, entries[:])
    for i in 0 ..< count {
        entry: CurveEntry = entries[i]
        points[i] = {x = entry.x, y = entry.y, point = entry.point, time = entry.time, value = entry.value, shape = entry.shape, curve = entry.curve, tangent_in = entry.tangent_in, tangent_out = entry.tangent_out}
        if entry.selected { points[i].flags += {.SELECTED} }
        if view.hover_point == entry.point { points[i].flags += {.HOVERED} }
        if view.gesture_point == entry.point && view.gesture == .POINTS { points[i].flags += {.PRESSED} }
        if view.hover_handle == entry.point { (&points[i].handle_flags_end if view.hover_handle_end else &points[i].handle_flags)^ += {.HOVERED} }
        if view.gesture_handle == entry.point && view.gesture == .CURVE { (&points[i].handle_flags_end if view.gesture_handle_end else &points[i].handle_flags)^ += {.PRESSED} }
    }
    curve: CurveDraw = {
        rect = lane, inner = timelineLaneInner(lane), points = points[:count], name = TimelineTrackName(track), color = track.color, steps = track.steps,
        bend_rect = timelineBendRect(lane), bend_rise = track.bend_rise, bend_fall = track.bend_fall,
        bend_hover = (2 if view.hover_bend_fall else 1) if view.hover_bend == track.handle else 0,
        bend_pressed = view.gesture == .BEND && view.gesture_bend == track.handle, lane_hovered = view.hover_track >= 0 && timeline.order[view.hover_track] == track.handle,
        track = track.handle, value_min = track.value_min, value_max = track.value_max, user = style.user,
    }
    style.draw_curve(ctx, &curve)
}
