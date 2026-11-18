#+private file
package demo_common

// A timeline of an arrangement: four tracks with clips, a ruler in beats, a playhead. Drag a clip to move it (to another track too), drag its edges to resize it, press the ruler to put
// the playhead, scroll the wheel to zoom around the pointer, Shift + click to select several clips (they move together), Delete removes them. The rules keep the clips of a track apart.
// The last event of the timeline, with the name of the track it happened on (the user pointer of the track), is shown under it.

import "core:fmt"
import hm "core:container/handle_map"
import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_timeline: kit.Demo = {
    name = "timeline",
    init = init,
    draw = draw,
    script = script,
}

Channel :: struct {
    name: string,
}

State :: struct {
    app: UiDemo,
    timeline: ui.Timeline,
    view: ui.TimelineView,
    channels: [5]Channel,
    tracks: [4]ui.TrackHandle,
    cutoff: ui.TrackHandle,
    log: [160]u8,
    log_length: int,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_demo_init(&state.app)
    ctx.background = {24, 26, 32, 255}
    ui.TimelineInit(&state.timeline, &state)
    state.timeline.rules.can_place = ui.TimelineRuleNoOverlap
    state.timeline.rules.min_length = 0.25
    state.timeline.on_event = onEvent
    state.view = {zoom = 40, snap = 0.25}
    names: [4]string = {"Drums", "Bass", "Lead", "Vocals"}
    for i in 0 ..< 4 {
        state.channels[i] = {name = names[i]}
        state.tracks[i], _ = ui.TimelineTrackAdd(&state.timeline, names[i], user = &state.channels[i])
    }
    ui.TimelineClipAdd(&state.timeline, state.tracks[0], 0, 4, "Beat")
    ui.TimelineClipAdd(&state.timeline, state.tracks[0], 6, 2, "Fill")
    ui.TimelineClipAdd(&state.timeline, state.tracks[1], 2, 8, "Line")
    ui.TimelineClipAdd(&state.timeline, state.tracks[2], 8, 4, "Hook")
    ui.TimelineClipAdd(&state.timeline, state.tracks[3], 4, 6, "Verse")
    state.channels[4] = {name = "Cutoff"}
    cutoff, _ := ui.TimelineAutomationAdd(&state.timeline, "Cutoff", 0, 100, user = &state.channels[4])
    state.cutoff = cutoff
    for point in ([5][2]f64{{0, 20}, {4, 80}, {8, 40}, {12, 90}, {16, 10}}) { ui.TimelinePointAdd(&state.timeline, cutoff, point[0], f32(point[1])) }
    ui.TimelineMarkerAdd(&state.timeline, 0, "Intro")
    ui.TimelineMarkerAdd(&state.timeline, 8, "Drop")
    for {
        _, has := ui.TimelinePollEvent(&state.timeline)
        if !has { break }
    }
}

onEvent :: proc(timeline: ^ui.Timeline, event: ^ui.TimelineEvent) {
    s: ^State = cast(^State)event.timeline_user
    track: string
    if channel := cast(^Channel)event.track_user; channel != nil { track = channel.name }
    #partial switch event.kind {
    case .CLIP_MOVED:
        s.log_length = len(fmt.bprintf(s.log[:], "moved to %s at %.2f", track, event.start))
    case .CLIP_RESIZED:
        s.log_length = len(fmt.bprintf(s.log[:], "resized on %s: %.2f .. %.2f", track, event.start, event.start + event.length))
    case .PLAYHEAD:
        s.log_length = len(fmt.bprintf(s.log[:], "playhead at %.2f", event.time))
    case .POINT_MOVED:
        s.log_length = len(fmt.bprintf(s.log[:], "%s: %.1f at %.2f", track, event.value, event.time))
    case .POINT_SHAPED:
        s.log_length = len(fmt.bprintf(s.log[:], "%s: curve %v %.2f", track, event.shape, event.curve))
    case .POINT_ADDED:
        s.log_length = len(fmt.bprintf(s.log[:], "%s: point added, %.1f at %.2f", track, event.value, event.time))
    case .MARKER_MOVED:
        s.log_length = len(fmt.bprintf(s.log[:], "marker moved to %.2f", event.time))
    case .CLIP_REMOVED:
        s.log_length = len(fmt.bprintf(s.log[:], "clip removed from %s", track))
    case .EMPTY_DOUBLE_CLICK:
        s.log_length = len(fmt.bprintf(s.log[:], "double click on %s at %.2f", track, event.time))
    }
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "timeline demo", {size = {ui.Fixed(800), ui.Fit()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 8}) {
        ui.UiTimeline(c, "Arrangement", &state.timeline, &state.view, {ui.Fixed(780), ui.Fixed(320)})
        ui.UiLabel(c, string(state.log[:state.log_length]))
    }
    ui_demo_end(&state.app)
}

clipOf :: proc(index: int) -> ^ui.TimelineClip {
    out: [8]ui.ClipHandle
    count: int = ui.TimelineTrackClips(&state.timeline, state.tracks[index], out[:])
    if count == 0 { return nil }
    return ui.TimelineClipGet(&state.timeline, out[0])
}

// the timeline is at (10, 10): the ruler 24 high, the lanes 48 high from y 34, 40 pixels a beat
script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.TimelineClipCount(&state.timeline) == 5 }, "five clips"),
    // the automation lane (y 226 .. 274, the values from y 231 down to y 269): its second point is dragged two beats later and up to the top, a double click on the empty lane adds a point
    kit.MoveTo({170, 239}),
    kit.Wait(3),
    kit.Drag({170, 239}, {250, 220}, 10),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        out: [8]ui.PointHandle
        count: int = ui.TimelineTrackPoints(&state.timeline, state.cutoff, out[:])
        if count != 5 { return false }
        moved: ^ui.TimelinePoint = ui.TimelinePointGet(&state.timeline, out[1])
        return abs(moved.time - 6) < 0.01 && moved.value == 100
    }, "a point was dragged two beats later and to the top of the range"),
    kit.MoveTo({410, 262}),
    kit.Wait(3),
    kit.Click({410, 262}),
    kit.Click({410, 262}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        value, found := ui.TimelineAutomationValue(&state.timeline, state.cutoff, 10)
        return found && ui.TimelinePointCount(&state.timeline) == 6 && abs(value - 18.4) < 1
    }, "a double click on the lane added a point at its place"),
    kit.Capture("timeline_automation"),
    kit.Wait(1),
    kit.Tap(.DELETE),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.TimelinePointCount(&state.timeline) == 5 }, "Delete removed the selected point"),
    // the curve between two points: Ctrl and a click on a point makes the curve that leaves it the next shape (linear, smooth, bias, S, hold), the handle in the middle of a segment bends it
    kit.KeyDownStep(.LEFT_CTRL),
    kit.Wait(1),
    kit.Click({330, 254}),
    kit.Wait(1),
    kit.KeyUpStep(.LEFT_CTRL),
    kit.Wait(2),
    kit.MoveTo({570, 250}),
    kit.Wait(3),
    kit.Drag({570, 250}, {570, 245}, 6),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        out: [8]ui.PointHandle
        count: int = ui.TimelineTrackPoints(&state.timeline, state.cutoff, out[:])
        if count != 5 { return false }
        smooth: ^ui.TimelinePoint = ui.TimelinePointGet(&state.timeline, out[2])
        bent: ^ui.TimelinePoint = ui.TimelinePointGet(&state.timeline, out[3])
        return smooth.shape == .SMOOTH && bent.shape == .CURVE && bent.curve < -0.2 && bent.curve > -0.5
    }, "Ctrl and a click made a segment smooth, the handle bent another one to start slowly"),
    kit.Capture("timeline_curves"),
    kit.Wait(1),
    // "Beat" (beats 0 .. 4, x 10 .. 170) two beats later and two tracks down, on the free part of "Lead"
    kit.MoveTo({60, 50}),
    kit.Wait(3),
    kit.Drag({60, 50}, {140, 146}, 10),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        clip: ^ui.TimelineClip = clipOf(2)
        return clip != nil && ui.TimelineClipName(clip) == "Beat" && abs(clip.start - 2) < 0.01
    }, "the clip was dragged two beats later onto the third track"),
    // "Hook" (beats 8 .. 12): its right edge (x 490) is dragged to x 570, two beats longer
    kit.MoveTo({487, 150}),
    kit.Wait(3),
    kit.Drag({487, 150}, {567, 150}, 10),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        out: [8]ui.ClipHandle
        count: int = ui.TimelineTrackClips(&state.timeline, state.tracks[2], out[:])
        if count != 2 { return false }
        hook: ^ui.TimelineClip = ui.TimelineClipGet(&state.timeline, out[1])
        return ui.TimelineClipName(hook) == "Hook" && abs(hook.length - 6) < 0.01
    }, "the right edge made the clip two beats longer"),
    // the ruler: the playhead at beat 4
    kit.MoveTo({170, 20}),
    kit.Wait(3),
    kit.Click({170, 20}),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(state.view.playhead - 4) < 0.01 }, "a press on the ruler put the playhead there"),
    // the wheel under the last lane zooms around the pointer
    kit.MoveTo({600, 245}),
    kit.Wait(3),
    kit.Scroll(2),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(ui.TimelineViewZoom(&state.view) - 40 * ui.TIMELINE_ZOOM_STEP * ui.TIMELINE_ZOOM_STEP) < 0.01 }, "the wheel zoomed"),
    kit.Capture("timeline"),
    // Shift and a drag on the ruler makes a loop range (its edges can be dragged), Ctrl and a drag over the lanes selects the clips the box touches
    kit.KeyDownStep(.LEFT_SHIFT),
    kit.Wait(1),
    kit.MoveTo({450, 20}),
    kit.Wait(2),
    kit.Drag({450, 20}, {650, 20}, 8),
    kit.Wait(3),
    kit.KeyUpStep(.LEFT_SHIFT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.view.loop_enabled && state.view.loop_end - state.view.loop_start > 2 }, "Shift and a drag on the ruler made a loop range"),
    kit.KeyDownStep(.LEFT_CTRL),
    kit.Wait(1),
    kit.MoveTo({770, 235}),
    kit.Wait(2),
    kit.Drag({770, 235}, {20, 60}, 10),
    kit.Wait(3),
    kit.KeyUpStep(.LEFT_CTRL),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.TimelineSelectedCount(&state.timeline) >= 3 }, "Ctrl and a drag selected the clips the box touched"),
    kit.Capture("timeline_loop_box"),
    // a marker is dragged on the ruler; with snap_to_edges it lands on the end of a clip when it is near
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        state.view.snap_to_edges = true
        return true
    }, "snap to the edges of clips and markers"),
    kit.MoveTo({253, 15}),
    kit.Wait(3),
    kit.Drag({253, 15}, {353, 15}, 10),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        it := hm.iterator_make(&state.timeline.markers)
        for marker, _ in hm.iterate(&it) {
            if ui.TimelineMarkerName(marker) == "Drop" { return marker.time == 10 && marker.selected }
        }
        return false
    }, "the marker was dragged 1.9 beats and snapped to the end of the Line clip"),
    kit.Capture("timeline_markers"),
    kit.Wait(1),
    // copy a clip, put the playhead on the ruler, paste: the copy lands at the playhead on the track it came from, selected
    kit.Click({190, 60}),
    kit.Wait(2),
    kit.KeyDownStep(.LEFT_CTRL),
    kit.Wait(1),
    kit.Tap(.C),
    kit.Wait(1),
    kit.KeyUpStep(.LEFT_CTRL),
    kit.Wait(2),
    kit.Click({401, 28}),
    kit.Wait(2),
    kit.KeyDownStep(.LEFT_CTRL),
    kit.Wait(1),
    kit.Tap(.V),
    kit.Wait(1),
    kit.KeyUpStep(.LEFT_CTRL),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if ui.TimelineClipCount(&state.timeline) != 6 { return false }
        out: [8]ui.ClipHandle
        count: int = ui.TimelineTrackClips(&state.timeline, state.tracks[0], out[:])
        if count != 2 { return false }
        copy: ^ui.TimelineClip = ui.TimelineClipGet(&state.timeline, out[1])
        return ui.TimelineClipName(copy) == "Fill" && abs(copy.start - 11) < 0.01 && copy.selected
    }, "Ctrl + C and Ctrl + V made a copy of Fill at the playhead"),
    kit.Capture("timeline_paste"),
    kit.Wait(1),
    // Ctrl + D: a copy of the selected clip right after it; Ctrl and the wheel: the tracks get taller around the pointer
    kit.KeyDownStep(.LEFT_CTRL),
    kit.Wait(1),
    kit.Tap(.D),
    kit.Wait(2),
    kit.MoveTo({600, 150}),
    kit.Wait(2),
    kit.Scroll(2),
    kit.Wait(3),
    kit.KeyUpStep(.LEFT_CTRL),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if ui.TimelineClipCount(&state.timeline) != 7 { return false }
        out: [8]ui.ClipHandle
        count: int = ui.TimelineTrackClips(&state.timeline, state.tracks[0], out[:])
        if count != 3 { return false }
        copy: ^ui.TimelineClip = ui.TimelineClipGet(&state.timeline, out[2])
        return abs(copy.start - 13) < 0.01 && copy.selected
    }, "Ctrl + D put a copy of the pasted clip right after it"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.TimelineViewTrackZoom(&state.view) > 1.3 }, "Ctrl and the wheel made the tracks taller"),
    kit.Capture("timeline_duplicate_zoom"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
