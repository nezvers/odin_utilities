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

@(private)
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
    tool: TimelineTool,
    loop_start: f64,            // the loop range: Shift + a drag on the ruler makes one, its edges are dragged; the program plays inside of it when `loop_enabled`
    loop_end: f64,
    loop_enabled: bool,
    rect: Rect,                 // where the widget is on the screen (as drawn in the last frame)
    hover_clip: ClipHandle,
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

@(private)
timelineSnap :: proc(view: ^TimelineView, time: f64) -> f64 {
    if view.snap <= 0 { return time }
    return math.round(time / view.snap) * view.snap
}

// The top and the height of a track from the top of the lanes (before the scroll).
@(private)
timelineTrackRow :: proc(timeline: ^Timeline, style: ^TimelineStyle, index: int) -> (top: f32, height: f32) {
    for i in 0 ..< timeline.track_count {
        track: ^TimelineTrack = TimelineTrackGet(timeline, timeline.order[i])
        height = track.height if track != nil && track.height > 0 else style.track_height
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
        height: f32 = track.height if track != nil && track.height > 0 else style.track_height
        if y < top + height { return i }
        top += height
    }
    return -1
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
    view.rect = state.rect
    mouse: Vec2 = ctx.input.mouse_position
    shift: bool = .SHIFT in ctx.input.modifiers
    serial_before: u64 = timeline.serial
    delta: Vec2 = mouse - view.last_mouse
    view.last_mouse = mouse
    lanes_top: f32 = view.rect.y + style.ruler_height

    if ctx.hover == id && ctx.input.wheel.y != 0 && view.gesture == .NONE && ctx.disabled_depth == 0 {
        before: f32 = TimelineViewZoom(view)
        if shift {
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
    view.hover_clip, view.hover_track = {}, -1
    zone: TimelineZone
    if hovering && mouse.y >= lanes_top {
        view.hover_clip, zone = timelinePick(timeline, view, &style, mouse)
        view.hover_track = row
    }
    min_length: f64 = max(timeline.rules.min_length, 4 / f64(zoom))

    if interaction.pressed && ctx.input.mouse_pressed && view.gesture == .NONE {
        ctrl: bool = .CTRL in ctx.input.modifiers
        switch {
        case mouse.y < lanes_top:
            near_start: f32 = abs(TimelineX(view, view.loop_start) - mouse.x)
            near_end: f32 = abs(TimelineX(view, view.loop_end) - mouse.x)
            switch {
            case view.loop_enabled && min(near_start, near_end) <= style.edge:
                view.gesture = .LOOP_START if near_start <= near_end else .LOOP_END
            case shift:
                view.gesture = .LOOP_NEW
                view.loop_anchor = max(timelineSnap(view, time), 0)
            case:
                view.gesture = .PLAYHEAD
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
        case:
            view.gesture = .PAN
            if !shift { TimelineSelectClear(timeline) }
            if interaction.double_clicked && row >= 0 {
                timelineEmit(timeline, {kind = .EMPTY_DOUBLE_CLICK, track = timeline.order[row], time = max(timelineSnap(view, time), 0)})
            }
        }
    }

    if view.gesture != .NONE {
        if (ctx.input.mouse_down || ctx.input.mouse_released) && !ctx.input.mouse_pressed {
            clip: ^TimelineClip = TimelineClipGet(timeline, view.gesture_clip)
            switch view.gesture {
            case .PLAYHEAD:
                moved: f64 = max(timelineSnap(view, time), 0)
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
            case .LOOP_NEW:
                a, b: f64 = view.loop_anchor, max(timelineSnap(view, time), 0)
                start, end: f64 = min(a, b), max(a, b)
                if end - start >= min_length && (start != view.loop_start || end != view.loop_end || !view.loop_enabled) {
                    view.loop_start, view.loop_end, view.loop_enabled = start, end, true
                    timelineEmit(timeline, {kind = .LOOP_CHANGED, start = start, length = end - start})
                }
            case .LOOP_START:
                start: f64 = clamp(timelineSnap(view, time), 0, view.loop_end - min_length)
                if start != view.loop_start {
                    view.loop_start = start
                    timelineEmit(timeline, {kind = .LOOP_CHANGED, start = start, length = view.loop_end - start})
                }
            case .LOOP_END:
                end: f64 = max(timelineSnap(view, time), view.loop_start + min_length)
                if end != view.loop_end {
                    view.loop_end = end
                    timelineEmit(timeline, {kind = .LOOP_CHANGED, start = view.loop_start, length = end - view.loop_start})
                }
            case .PAN:
                view.origin = max(view.origin - f64(delta.x / zoom), 0)
                view.scroll = clamp(view.scroll - delta.y, 0, max(timelineTotalHeight(timeline, &style) - visible_height, 0))
            case .MOVE:
                if clip != nil {
                    raw: f64 = clip.drag_start + (time - view.grab_time)
                    shift_time: f64 = timelineSnap(view, raw) - clip.drag_start
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
                    end: f64 = max(timelineSnap(view, time), clip.start + min_length)
                    TimelineClipPlace(timeline, view.gesture_clip, clip.track, clip.start, end - clip.start)
                }
            case .RESIZE_LEFT:
                if clip != nil {
                    end: f64 = clip.drag_start + clip.drag_length
                    start: f64 = clamp(timelineSnap(view, time), 0, end - min_length)
                    TimelineClipPlace(timeline, view.gesture_clip, clip.track, start, end - start)
                }
            case .NONE:
            }
        }
        if ctx.input.mouse_released || !ctx.input.mouse_down {
            view.gesture, view.gesture_clip = .NONE, {}
        }
    }

    if .DELETE in ctx.input.keys && (ctx.focus == 0 || ctx.focus == id) {
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
            style.draw_lane(ctx, &lane)
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
    if style.draw_playhead != nil {
        x: f32 = TimelineX(view, view.playhead)
        if x >= area.x && x <= area.x + area.z {
            head: PlayheadDraw = {x = x, rect = {area.x, area.y, area.z, area.w}, ruler_height = style.ruler_height, time = view.playhead, user = style.user}
            if view.gesture == .PLAYHEAD { head.flags += {.PRESSED} }
            style.draw_playhead(ctx, &head)
        }
    }
}
