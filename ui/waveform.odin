package ui

// A waveform view of an audio clip or a sample: the samples as a min / max column per pixel, a ruler of time on top, a playhead, a selection region and named markers. The samples are the
// program's (`Waveform.samples`, one channel, must live until `UiRender`); for a long sample the program builds a table of peaks once (`WaveformBuildPeaks` into a storage it gives) so
// a zoomed out view reads a few values per pixel instead of the whole sample. Where a thing is on the screen is arithmetic (`WaveformAreas`, `WaveformX`, `WaveformSampleAt`).
//
//   wave: ui.Waveform;  markers: [32]ui.WaveMarker;  peaks: [4096]ui.WavePeak;  view: ui.WaveformView
//   ui.WaveformInit(&wave, samples, 48000, markers[:]);  ui.WaveformBuildPeaks(&wave, peaks[:], 256)
//   ui.UiWaveform(&ctx, "Clip", &wave, &view, {Grow(), Grow()})        // every frame; wave.on_event tells what the person did
//
// Pointer: the wheel zooms around the pointer (Shift + wheel pans); a press on the ruler moves the playhead (and drags it); a drag over the body selects a region (a click clears it);
// a press on a marker drags it, a double click on empty space adds a marker, on a marker removes it.
//
// Limits: one channel (the program mixes or picks, a stereo view is two views); the peaks are one level (zoomed out beyond it the columns read more peaks per pixel, up to the table);
// no editing of the samples, no fades or gain handles; markers do not snap; times are in samples with seconds shown by the style when `sample_rate` is set; events are told when a gesture ends.

import "core:math"

WAVE_RULER_HEIGHT :: 20
WAVE_MARKER_PICK :: 6                   // pixels either side of a marker line that a press takes
WAVE_MIN_SPP :: 1.0 / 32                // the closest zoom: samples per pixel
WAVE_ZOOM_STEP :: f64(1.2)

WavePeak :: struct {
    low: f32,
    high: f32,
}

WaveMarker :: struct {
    position: f64,                      // samples
    name: string,                       // the program's, must live as long as the marker
}

WaveEventKind :: enum u8 {
    SEEK,                               // the playhead was moved: `position`
    SELECTION,                          // a region was selected or cleared (`position` start, `end`; both 0 and `cleared` when it was cleared)
    MARKER_ADDED,                       // `marker` is its index
    MARKER_REMOVED,
    MARKER_MOVED,                       // `position` is the new place
}

WaveEvent :: struct {
    kind: WaveEventKind,
    marker: int,
    position: f64,
    end: f64,
    cleared: bool,
}

WaveEventProc :: proc(wave: ^Waveform, event: ^WaveEvent)

Waveform :: struct {
    samples: []f32,                     // one channel, -1 .. 1
    sample_rate: f32,                   // 0: times are shown in samples
    peaks: []WavePeak,                  // optional (`WaveformBuildPeaks`)
    peak_block: int,                    // samples per peak
    markers: []WaveMarker,              // the storage
    marker_count: int,
    on_event: WaveEventProc,
    user: rawptr,
    serial: u64,                        // grows with every change of the markers
}

WaveGesture :: enum u8 {
    NONE,
    SEEK,
    SELECT,
    MARKER,
}

WaveformView :: struct {
    samples_per_pixel: f64,             // 0: the whole sample fits
    origin: f64,                        // the sample at the left edge
    playhead: f64,
    show_playhead: bool,
    has_selection: bool,
    selection_start: f64,               // samples, start <= end
    selection_end: f64,
    // set by the widget
    wave: ^Waveform,                    // what the style draws
    rect: Rect,
    gesture: WaveGesture,
    grab: int,
    anchor: f64,                        // the sample where a selection started
    moved: bool,
    hover_marker: int,                  // -1: none
}

WaveAreas :: struct {
    ruler: Rect,
    body: Rect,
}

WaveformInit :: proc(wave: ^Waveform, samples: []f32, sample_rate: f32 = 0, marker_storage: []WaveMarker = nil, user: rawptr = nil) {
    wave^ = {samples = samples, sample_rate = sample_rate, markers = marker_storage, user = user}
}

// Fills the table of peaks, one per `block` samples; false when the storage is too small (then no table is used)
WaveformBuildPeaks :: proc(wave: ^Waveform, storage: []WavePeak, block: int) -> bool {
    wave.peaks, wave.peak_block = nil, 0
    if block < 2 { return false }
    needed: int = (len(wave.samples) + block - 1) / block
    if needed > len(storage) { return false }
    for i in 0 ..< needed {
        first, last: int = i * block, min((i + 1) * block, len(wave.samples))
        low, high: f32 = wave.samples[first], wave.samples[first]
        for s in wave.samples[first:last] {
            low, high = min(low, s), max(high, s)
        }
        storage[i] = {low, high}
    }
    wave.peaks, wave.peak_block = storage[:needed], block
    return true
}

@(private)
waveTell :: proc(wave: ^Waveform, event: WaveEvent) {
    event := event
    if wave.on_event != nil { wave.on_event(wave, &event) }
}

WaveformAddMarker :: proc(wave: ^Waveform, position: f64, name: string = "") -> (index: int, ok: bool) {
    if wave.marker_count >= len(wave.markers) { return -1, false }
    wave.markers[wave.marker_count] = {position = clamp(position, 0, f64(len(wave.samples))), name = name}
    wave.marker_count += 1
    wave.serial += 1
    return wave.marker_count - 1, true
}

WaveformRemoveMarker :: proc(wave: ^Waveform, index: int) {
    if index < 0 || index >= wave.marker_count { return }
    for i in index ..< wave.marker_count - 1 { wave.markers[i] = wave.markers[i + 1] }
    wave.marker_count -= 1
    wave.serial += 1
}

// The lowest and highest sample in the range [first, last) (clamped); the table of peaks answers when the range is wide enough to hold whole blocks
WaveformRange :: proc(wave: ^Waveform, first: int, last: int) -> (low: f32, high: f32) {
    a, b: int = clamp(first, 0, len(wave.samples)), clamp(last, 0, len(wave.samples))
    if b <= a { return 0, 0 }
    if wave.peak_block > 0 && b - a >= wave.peak_block * 2 {
        start, end: int = (a + wave.peak_block - 1) / wave.peak_block, b / wave.peak_block
        low, high = 1e30, -1e30
        for peak in wave.peaks[start:min(end, len(wave.peaks))] {
            low, high = min(low, peak.low), max(high, peak.high)
        }
        // the ragged ends are read from the samples
        for s in wave.samples[a:min(start * wave.peak_block, b)] { low, high = min(low, s), max(high, s) }
        for s in wave.samples[max(end * wave.peak_block, a):b] { low, high = min(low, s), max(high, s) }
        if low > high { return 0, 0 }
        return
    }
    low, high = wave.samples[a], wave.samples[a]
    for s in wave.samples[a:b] { low, high = min(low, s), max(high, s) }
    return
}

// ------------------------------------------------------------------------------------------------------------------------
// Where things are

WaveformAreas :: proc(rect: Rect) -> WaveAreas {
    return {ruler = {rect.x, rect.y, rect.z, min(WAVE_RULER_HEIGHT, rect.w)}, body = {rect.x, rect.y + WAVE_RULER_HEIGHT, rect.z, max(rect.w - WAVE_RULER_HEIGHT, 0)}}
}

// Samples a pixel is wide (the whole sample when the view is not zoomed)
WaveformSamplesPerPixel :: proc(wave: ^Waveform, view: ^WaveformView, areas: WaveAreas) -> f64 {
    if view.samples_per_pixel > 0 { return max(view.samples_per_pixel, WAVE_MIN_SPP) }
    return max(f64(len(wave.samples)) / f64(max(areas.body.z, 1)), WAVE_MIN_SPP)
}

WaveformX :: proc(wave: ^Waveform, view: ^WaveformView, areas: WaveAreas, sample: f64) -> f32 {
    return areas.body.x + f32((sample - view.origin) / WaveformSamplesPerPixel(wave, view, areas))
}

WaveformSampleAt :: proc(wave: ^Waveform, view: ^WaveformView, areas: WaveAreas, x: f32) -> f64 {
    return view.origin + f64(x - areas.body.x) * WaveformSamplesPerPixel(wave, view, areas)
}

WaveformMarkerAt :: proc(wave: ^Waveform, view: ^WaveformView, areas: WaveAreas, x: f32) -> int {
    best: int = -1
    best_distance: f32 = WAVE_MARKER_PICK
    for i in 0 ..< wave.marker_count {
        distance: f32 = abs(WaveformX(wave, view, areas, wave.markers[i].position) - x)
        if distance <= best_distance {
            best_distance = distance
            best = i
        }
    }
    return best
}

// ------------------------------------------------------------------------------------------------------------------------
// The widget

UiWaveform :: proc(ctx: ^Context, name: string, wave: ^Waveform, view: ^WaveformView, size: Size = {}) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    view.wave = wave
    view.rect = state.rect
    areas: WaveAreas = WaveformAreas(view.rect)
    mouse: Vec2 = ctx.input.mouse_position
    serial_before: u64 = wave.serial
    live: bool = ctx.disabled_depth == 0
    hovering: bool = ctx.hover == id && live && view.gesture == .NONE
    total: f64 = f64(len(wave.samples))

    if hovering && ctx.input.wheel.y != 0 {
        before: f64 = WaveformSamplesPerPixel(wave, view, areas)
        if .SHIFT in ctx.input.modifiers {
            view.origin -= f64(ctx.input.wheel.y) * 60 * before
        } else {
            after: f64 = before / math.pow(WAVE_ZOOM_STEP, f64(ctx.input.wheel.y))
            fit: f64 = total / f64(max(areas.body.z, 1))
            after = clamp(after, WAVE_MIN_SPP, max(fit, WAVE_MIN_SPP))
            view.origin += f64(mouse.x - areas.body.x) * (before - after)
            view.samples_per_pixel = after
        }
    }
    // the view stays on the sample
    spp: f64 = WaveformSamplesPerPixel(wave, view, areas)
    view.origin = clamp(view.origin, 0, max(total - f64(areas.body.z) * spp, 0))

    if interaction.pressed && ctx.input.mouse_pressed && interaction.hovered && view.gesture == .NONE && live {
        wavePress(wave, view, areas, mouse, interaction.double_clicked)
    } else if view.gesture != .NONE && interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
        waveDrag(wave, view, areas, mouse)
        if ctx.input.mouse_released { waveEnd(wave, view) }
    }
    if view.gesture != .NONE && !interaction.pressed { waveEnd(wave, view) }

    view.hover_marker = view.grab if view.gesture == .MARKER else -1
    if hovering && view.gesture == .NONE && RectContains(areas.body, mouse) { view.hover_marker = WaveformMarkerAt(wave, view, areas, mouse.x) }
    ElementOpen(ctx, {
        id = id,
        layout = {size = {size.width if size.width != {} else Grow(), size.height if size.height != {} else Grow()}},
        clip = {horizontal = true, vertical = true, cut = true},
        hit = {.INTERACTIVE, .SCROLL},
        cursor = .RESIZE_HORIZONTAL if view.hover_marker >= 0 else .ARROW,
        draw = {kind = .WAVEFORM, name = IdSplitName(name), user = view, font_size = ctx.style.metrics.font_size},
    })
    ElementClose(ctx)
    return wave.serial != serial_before
}

@(private)
wavePress :: proc(wave: ^Waveform, view: ^WaveformView, areas: WaveAreas, mouse: Vec2, double: bool) {
    total: f64 = f64(len(wave.samples))
    sample: f64 = clamp(WaveformSampleAt(wave, view, areas, mouse.x), 0, total)
    view.moved, view.grab = false, -1
    if RectContains(areas.ruler, mouse) {
        view.gesture = .SEEK
        view.playhead, view.show_playhead = sample, true
        waveTell(wave, {kind = .SEEK, position = sample})
    } else if RectContains(areas.body, mouse) {
        marker: int = WaveformMarkerAt(wave, view, areas, mouse.x)
        if marker >= 0 {
            if double {
                WaveformRemoveMarker(wave, marker)
                waveTell(wave, {kind = .MARKER_REMOVED, marker = marker})
                return
            }
            view.gesture, view.grab = .MARKER, marker
        } else if double {
            if added, ok := WaveformAddMarker(wave, sample); ok { waveTell(wave, {kind = .MARKER_ADDED, marker = added, position = sample}) }
        } else {
            view.gesture, view.anchor = .SELECT, sample
        }
    }
}

@(private)
waveDrag :: proc(wave: ^Waveform, view: ^WaveformView, areas: WaveAreas, mouse: Vec2) {
    total: f64 = f64(len(wave.samples))
    sample: f64 = clamp(WaveformSampleAt(wave, view, areas, mouse.x), 0, total)
    switch view.gesture {
    case .NONE:
    case .SEEK:
        view.playhead = sample
    case .MARKER:
        if view.grab >= 0 && view.grab < wave.marker_count && wave.markers[view.grab].position != sample {
            wave.markers[view.grab].position = sample
            wave.serial += 1
            view.moved = true
        }
    case .SELECT:
        // a press that does not move is a click: it clears the selection when it ends
        if abs(sample - view.anchor) >= WaveformSamplesPerPixel(wave, view, areas) * 2 || view.moved {
            view.moved = true
            view.has_selection = true
            view.selection_start, view.selection_end = min(view.anchor, sample), max(view.anchor, sample)
        }
    }
}

@(private)
waveEnd :: proc(wave: ^Waveform, view: ^WaveformView) {
    switch view.gesture {
    case .NONE:
    case .SEEK:
        waveTell(wave, {kind = .SEEK, position = view.playhead})
    case .MARKER:
        if view.moved && view.grab >= 0 && view.grab < wave.marker_count {
            waveTell(wave, {kind = .MARKER_MOVED, marker = view.grab, position = wave.markers[view.grab].position})
        }
    case .SELECT:
        if view.moved {
            waveTell(wave, {kind = .SELECTION, position = view.selection_start, end = view.selection_end})
        } else if view.has_selection {
            view.has_selection = false
            waveTell(wave, {kind = .SELECTION, cleared = true})
        }
    }
    view.gesture, view.moved, view.grab = .NONE, false, -1
}
