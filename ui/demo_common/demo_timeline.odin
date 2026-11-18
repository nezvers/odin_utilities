#+private file
package demo_common

// A timeline of an arrangement: four tracks with clips, a ruler in beats, a playhead. Drag a clip to move it (to another track too), drag its edges to resize it, press the ruler to put
// the playhead, scroll the wheel to zoom around the pointer, Shift + click to select several clips (they move together), Delete removes them. The rules keep the clips of a track apart.
// The last event of the timeline, with the name of the track it happened on (the user pointer of the track), is shown under it.

import "core:fmt"
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
    channels: [4]Channel,
    tracks: [4]ui.TrackHandle,
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
        ui.UiTimeline(c, "Arrangement", &state.timeline, &state.view, {ui.Fixed(780), ui.Fixed(240)})
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
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
