package ui

// What a style decides about a timeline: how a lane, a clip, the ruler and the playhead are drawn, and the numbers of the layout. The library draws nothing itself; the procs are
// called by TimelineDraw (timeline_widgets.odin) in the order lanes, clips, ruler, playhead, with everything in screen coordinates.
//
//     style.timeline.draw_clip = MyClip
//     style.timeline.track_height = 64

// A track row.
LaneDraw :: struct {
    rect: Rect,
    name: string,
    color: Color,               // the color of the track, alpha 0: the style's own
    index: int,                 // from the top
    track: TrackHandle,
    flags: Flags,               // HOVERED: the pointer is on it, DISABLED: muted, ON: locked
    user: rawptr,               // `user` of the TimelineStyle
}

// A clip.
ClipDraw :: struct {
    rect: Rect,
    visible: Rect,              // the part of the screen the lanes are in: a clip that starts left of it keeps its name in view
    name: string,
    color: Color,               // of the clip, else of its track; alpha 0: the style's own
    clip: ClipHandle,
    track: TrackHandle,
    track_index: int,
    start: f64,
    length: f64,
    flags: Flags,               // SELECTED, HOVERED, PRESSED: it is being dragged or resized, DISABLED: its track is muted
    user: rawptr,
}

// The ruler: a tick every `step` units, starting at a multiple of it, `zoom` pixels per unit, `origin` the time at the left edge of `rect`.
RulerDraw :: struct {
    rect: Rect,
    origin: f64,
    zoom: f32,
    step: f64,
    loop_enabled: bool,         // a loop range: from `loop_x` to `loop_end_x` on the screen
    loop_x: f32,
    loop_end_x: f32,
    user: rawptr,
}

// The rectangle that is dragged to select clips (on the screen).
BoxDraw :: struct {
    rect: Rect,
    user: rawptr,
}

PlayheadDraw :: struct {
    x: f32,
    rect: Rect,                 // the whole widget
    ruler_height: f32,
    time: f64,
    flags: Flags,               // PRESSED: it is being dragged
    user: rawptr,
}

LaneDrawProc :: proc(ctx: ^Context, lane: ^LaneDraw)
ClipDrawProc :: proc(ctx: ^Context, clip: ^ClipDraw)
RulerDrawProc :: proc(ctx: ^Context, ruler: ^RulerDraw)
PlayheadDrawProc :: proc(ctx: ^Context, head: ^PlayheadDraw)
BoxDrawProc :: proc(ctx: ^Context, box: ^BoxDraw)

TimelineStyle :: struct {
    draw_lane: LaneDrawProc,
    draw_clip: ClipDrawProc,
    draw_ruler: RulerDrawProc,
    draw_playhead: PlayheadDrawProc,
    draw_box: BoxDrawProc,
    ruler_height: f32,          // 0: 24
    track_height: f32,          // of a track that has none of its own: 0 is 48
    edge: f32,                  // the width of the part of a clip's side that resizes it: 0 is 6
    user: rawptr,               // comes back in what is drawn
}

TIMELINE_RULER_HEIGHT :: f32(24)
TIMELINE_TRACK_HEIGHT :: f32(48)
TIMELINE_EDGE :: f32(6)

TimelineStyleResolved :: proc(style: ^Style) -> TimelineStyle {
    result: TimelineStyle = style.timeline
    if result.ruler_height <= 0 { result.ruler_height = TIMELINE_RULER_HEIGHT }
    if result.track_height <= 0 { result.track_height = TIMELINE_TRACK_HEIGHT }
    if result.edge <= 0 { result.edge = TIMELINE_EDGE }
    return result
}
