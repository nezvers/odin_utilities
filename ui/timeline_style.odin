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
    automation: bool,           // a lane of points: the curve is drawn after it (CurveDraw)
    user: rawptr,               // `user` of the TimelineStyle
}

// One point of an automation curve, on the screen.
CurvePoint :: struct {
    x: f32,
    y: f32,
    point: PointHandle,
    time: f64,
    value: f32,
    shape: CurveShape,          // the shape of the segment that leaves this point (to the next one in the list)
    curve: f32,
    tangent_in: f32,            // HERMITE: the slopes at this point (TimelinePoint)
    tangent_out: f32,
    flags: Flags,               // SELECTED, HOVERED, PRESSED: it is being dragged
    handle_flags: Flags,        // of the handle that bends the segment that leaves it (HERMITE: the first one, at the start of the segment): HOVERED, PRESSED
    handle_flags_end: Flags,    // HERMITE: the second handle, at the end of the segment
}

// The curve of an automation lane: the points in the order of their time, those in view and one before and one after them (for the lines that leave the view).
CurveDraw :: struct {
    rect: Rect,                 // the lane
    inner: Rect,                // the part of the lane a value can be at: its top is the highest value, its bottom the lowest
    points: []CurvePoint,       // valid during the call
    name: string,
    color: Color,               // of the track, alpha 0: the style's own
    steps: bool,                // the value is held until the next point
    track: TrackHandle,
    value_min: f32,
    value_max: f32,
    bend_rect: Rect,            // the small control of the bend macro of the lane (top right): two bars, the rising and the falling segments
    bend_rise: f32,             // -1 .. 1
    bend_fall: f32,
    bend_hover: u8,             // 0: the pointer is not on it, 1: on the left half (rise), 2: on the right half (fall)
    bend_pressed: bool,
    lane_hovered: bool,         // the pointer is over the lane: a style may show the bend control only then and when it is not 0
    user: rawptr,
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
    body: ^ClipBody,            // the content to draw inside (kind NONE: nothing); alive for the frame
    muted: bool,                // the clip does not play: drawn dim, its "M" lit
    gain_db: f32,               // the knob of the header
    header: bool,               // the clip is big enough for the header buttons below (TimelineClipHeader)
    header_mute, header_knob: Rect,
    fadeable: bool,             // an audio clip: draw its fades
    fade_in, fade_out: f64,     // in the units of the timeline
    fade_handles: bool,         // the clip is big enough for the handles below (TimelineClipFadeHandles)
    fade_in_handle, fade_out_handle: Rect,
    hover_zone: TimelineZone,   // when HOVERED: MUTE or GAIN while the pointer is on that button
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
    beat_seconds: f64,          // above 0: count bars and beats (a beat is this long, `beats_per_bar` of them make a bar); 0: plain numbers, a tick every `step`
    beats_per_bar: int,
    user: rawptr,
}

// A marker: a flag at the top of the ruler and a line down through the tracks.
MarkerDraw :: struct {
    x: f32,                     // where the line is
    ruler: Rect,
    area: Rect,                 // the whole widget
    name: string,
    color: Color,               // alpha 0: the style's own
    marker: MarkerHandle,
    time: f64,
    flags: Flags,               // SELECTED, HOVERED, PRESSED: it is being dragged
    width: f32,                 // the room of the flag to the right of the line (TimelineStyle.marker_width)
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
MarkerDrawProc :: proc(ctx: ^Context, marker: ^MarkerDraw)
CurveDrawProc :: proc(ctx: ^Context, curve: ^CurveDraw)

TimelineStyle :: struct {
    draw_lane: LaneDrawProc,
    draw_clip: ClipDrawProc,
    draw_ruler: RulerDrawProc,
    draw_playhead: PlayheadDrawProc,
    draw_box: BoxDrawProc,
    draw_marker: MarkerDrawProc,
    draw_curve: CurveDrawProc,
    ruler_height: f32,          // 0: 24
    track_height: f32,          // of a track that has none of its own: 0 is 48
    edge: f32,                  // the width of the part of a clip's side that resizes it: 0 is 6
    point_radius: f32,          // how far from a point of an automation curve the pointer still picks it: 0 is 7
    track_scale: f32,           // set by the widget from the vertical zoom of the view: the heights of all the tracks are multiplied by it (0 is 1)
    marker_width: f32,          // the room of the flag of a marker, to the right of its line (the part of the ruler that picks it): 0 is 64
    user: rawptr,               // comes back in what is drawn
}

TIMELINE_RULER_HEIGHT :: f32(24)
TIMELINE_TRACK_HEIGHT :: f32(48)
TIMELINE_EDGE :: f32(6)
TIMELINE_MARKER_WIDTH :: f32(64)
TIMELINE_POINT_RADIUS :: f32(7)
TIMELINE_LANE_MARGIN :: f32(5)             // between the top of an automation lane and its highest value, and the same below
TIMELINE_CURVE_POINTS :: 1024              // the points of one lane that are drawn (those in view and one on each side)

TimelineStyleResolved :: proc(style: ^Style) -> TimelineStyle {
    result: TimelineStyle = style.timeline
    if result.ruler_height <= 0 { result.ruler_height = TIMELINE_RULER_HEIGHT }
    if result.track_height <= 0 { result.track_height = TIMELINE_TRACK_HEIGHT }
    if result.edge <= 0 { result.edge = TIMELINE_EDGE }
    if result.marker_width <= 0 { result.marker_width = TIMELINE_MARKER_WIDTH }
    if result.point_radius <= 0 { result.point_radius = TIMELINE_POINT_RADIUS }
    return result
}
