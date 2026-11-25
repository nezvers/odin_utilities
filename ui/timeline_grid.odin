package ui

// Bars and beats for the timeline: the times of a timeline are seconds, and with `view.tempo` set the ruler counts in bars and beats ("1", "2", "2.3") and the grid snap can be chosen
// as a musical step (a bar, a beat, 1/8 .. 1/32 of a note) or left to the zoom (AUTO). Pure arithmetic, so the ruler of the style, the snap and a transport readout agree.
//
//   view.tempo = 124;  view.beats_per_bar = 4                       // the ruler shows bars and beats
//   ui.TimelineApplySnap(&view, .AUTO)                              // every frame for AUTO (it follows the zoom), once for the others
//   text := ui.TimelineBarsBeatsText(buffer[:], &view, view.playhead)   // "12.3.2"
//
// Limits: one tempo and one time signature for the whole timeline (no tempo map), a beat is a quarter note, no triplet or swing steps.

import "core:fmt"
import "core:math"

TimelineSnapChoice :: enum u8 {
    OFF,
    BAR,
    BEAT,               // 1/4
    HALF_BEAT,          // 1/8
    QUARTER_BEAT,       // 1/16
    EIGHTH_BEAT,        // 1/32
    AUTO,               // the finest step that is still wide enough on the screen
}

TIMELINE_SNAP_NAMES: [7]string = {"Off", "Bar", "1/4", "1/8", "1/16", "1/32", "Auto"}      // in the order of TimelineSnapChoice, for a dropdown that edits an int

TIMELINE_AUTO_SNAP_PIXELS :: 14         // AUTO picks the finest step that is at least this wide

// Seconds of a beat (0 without a tempo)
TimelineBeatSeconds :: proc(view: ^TimelineView) -> f64 {
    return 60 / view.tempo if view.tempo > 0 else 0
}

TimelineBeatsPerBar :: proc(view: ^TimelineView) -> int {
    return view.beats_per_bar if view.beats_per_bar > 0 else 4
}

// The length of a snap choice in seconds (0: no snap, or no tempo for a musical step)
TimelineSnapSeconds :: proc(view: ^TimelineView, choice: TimelineSnapChoice) -> f64 {
    beat: f64 = TimelineBeatSeconds(view)
    if beat <= 0 { return 0 }
    switch choice {
    case .OFF: return 0
    case .BAR: return beat * f64(TimelineBeatsPerBar(view))
    case .BEAT: return beat
    case .HALF_BEAT: return beat / 2
    case .QUARTER_BEAT: return beat / 4
    case .EIGHTH_BEAT: return beat / 8
    case .AUTO:
        zoom: f64 = f64(TimelineViewZoom(view))
        for step in ([]TimelineSnapChoice{.EIGHTH_BEAT, .QUARTER_BEAT, .HALF_BEAT, .BEAT}) {
            if TimelineSnapSeconds(view, step) * zoom >= TIMELINE_AUTO_SNAP_PIXELS { return TimelineSnapSeconds(view, step) }
        }
        return TimelineSnapSeconds(view, .BAR)
    }
    return 0
}

// Sets `view.snap` from a choice. AUTO has to be applied again when the zoom changes.
TimelineApplySnap :: proc(view: ^TimelineView, choice: TimelineSnapChoice) {
    view.snap = TimelineSnapSeconds(view, choice)
}

// The bar, beat and sixteenth of a time, all counted from 1 (a time before 0 is bar 1)
TimelineBarsBeats :: proc(view: ^TimelineView, time: f64) -> (bar: int, beat: int, sixteenth: int) {
    seconds: f64 = TimelineBeatSeconds(view)
    if seconds <= 0 { return 1, 1, 1 }
    sixteenths: int = int(math.floor(max(time, 0) / seconds * 4 + 1e-6))
    per_bar: int = TimelineBeatsPerBar(view)
    return sixteenths / (4 * per_bar) + 1, sixteenths / 4 % per_bar + 1, sixteenths % 4 + 1
}

// "12.3.2" for bar, beat and sixteenth; plain seconds without a tempo
TimelineBarsBeatsText :: proc(buffer: []u8, view: ^TimelineView, time: f64) -> string {
    if view.tempo <= 0 { return fmt.bprintf(buffer, "%.2f s", time) }
    bar, beat, sixteenth := TimelineBarsBeats(view, time)
    return fmt.bprintf(buffer, "%d.%d.%d", bar, beat, sixteenth)
}
