package ui

// A frequency response graph with draggable band nodes (an equalizer or a filter): a logarithmic frequency axis (across), a decibel axis (up), the curve that the bands make together,
// a node per band and, behind the curve, the spectrum of the signal when the program gives one. The bands are the program's data in a storage it gives (`FreqGraphInit`, no allocation,
// a full storage refuses the next band); the curve is computed here from the bands as the magnitude of biquad filters (the formulas of the RBJ cookbook), so what is drawn is what a
// filter with these numbers does at `sample_rate` (`FreqBandResponse`, `FreqGraphResponse` are pure and usable for tests and for drawing elsewhere).
//
//   graph: ui.FreqGraph;  storage: [8]ui.FreqBand;  view: ui.FreqGraphView
//   ui.FreqGraphInit(&graph, storage[:], 48000);  ui.FreqGraphAdd(&graph, .BELL, 1000, 3, 1)
//   ui.UiFreqGraph(&ctx, "EQ", &graph, &view, {Grow(), Grow()})        // every frame; graph.on_event tells what the person did
//
// Pointer: a press on a node selects it and a drag moves it (frequency across, gain up; cut and notch nodes move across only; Shift makes the drag ten times finer); the wheel over a
// node changes its Q (the bandwidth); a double click on empty graph adds a bell there, on a node removes it; Delete removes the selected band; a press on empty graph clears the selection.
// A readout of the node under the pointer (or being dragged) is drawn next to it.
//
// Limits: a band is one biquad (no cascades for steeper cuts, no dynamic or linked bands); the response ignores the oversampling and the phase; the spectrum is linear bins in dB that the
// program fills (no analyser inside); the axes are fixed in the view (no zoom of the graph); no stereo or mid / side bands; events are told when a gesture ends, the data changes while it goes on.

import "core:math"

FREQ_NODE_RADIUS :: 6
FREQ_PICK_RADIUS :: 11                  // pixels around a node that a press takes
FREQ_Q_MIN :: 0.1
FREQ_Q_MAX :: 18
FREQ_Q_STEP :: 1.12                     // per notch of the wheel
FREQ_AXIS_LEFT :: 38                    // the room of the dB labels
FREQ_AXIS_BOTTOM :: 18

FreqBandKind :: enum u8 {
    BELL,
    LOW_SHELF,
    HIGH_SHELF,
    LOW_CUT,                            // high pass
    HIGH_CUT,                           // low pass
    NOTCH,
}

FreqBand :: struct {
    kind: FreqBandKind,
    frequency: f32,                     // Hz
    gain: f32,                          // dB (bell and shelves)
    q: f32,                             // 0 is 0.707
    enabled: bool,
    selected: bool,
}

FreqEventKind :: enum u8 {
    ADDED,                              // `band` is its index
    REMOVED,                            // the band as it was (`band` is the index it had)
    CHANGED,                            // a drag, or the wheel, ended: the band has new numbers
    SELECTION,
}

FreqEvent :: struct {
    kind: FreqEventKind,
    band: int,
    data: FreqBand,
}

FreqEventProc :: proc(graph: ^FreqGraph, event: ^FreqEvent)

FreqGraph :: struct {
    bands: []FreqBand,                  // the storage, the program's
    count: int,
    sample_rate: f32,                   // 0 is 48000
    spectrum: []f32,                    // optional: linear bins from 0 Hz to sample_rate / 2, in dB (the program's, must live until UiRender)
    on_event: FreqEventProc,
    user: rawptr,
    serial: u64,                        // grows with every change of the bands
}

FreqGesture :: enum u8 {
    NONE,
    NODE,
}

FreqGraphView :: struct {
    min_frequency: f32,                 // Hz at the left edge (0 is 20)
    max_frequency: f32,                 // (0 is 20000)
    range_db: f32,                      // the graph shows -range_db .. range_db (0 is 18)
    spectrum_floor: f32,                // dB that the bottom of the spectrum fill is (0 is -90), the top is 0 dB
    // set by the widget
    graph: ^FreqGraph,                  // what the style draws
    rect: Rect,
    gesture: FreqGesture,
    grab: int,
    last_mouse: Vec2,
    drag_position: Vec2,                // where the node is while it is dragged, in pixels, moved by the pointer (a tenth of it with Shift)
    moved: bool,
    fine: bool,                         // Shift is down
    hover_band: int,                    // -1: none
    mouse: Vec2,                        // the pointer, for the readout
    inside: bool,                       // the pointer is over the graph
}

FreqAreas :: struct {
    grid: Rect,
    axis_left: Rect,
    axis_bottom: Rect,
}

FreqGraphInit :: proc(graph: ^FreqGraph, storage: []FreqBand, sample_rate: f32 = 48000, user: rawptr = nil) {
    graph^ = {bands = storage, sample_rate = sample_rate, user = user}
}

@(private)
freqTell :: proc(graph: ^FreqGraph, event: FreqEvent) {
    event := event
    if graph.on_event != nil { graph.on_event(graph, &event) }
}

// Adds a band. False when the storage is full.
FreqGraphAdd :: proc(graph: ^FreqGraph, kind: FreqBandKind, frequency: f32, gain: f32 = 0, q: f32 = 0) -> (index: int, ok: bool) {
    if graph.count >= len(graph.bands) { return -1, false }
    graph.bands[graph.count] = {kind = kind, frequency = clamp(frequency, 10, 24000), gain = clamp(gain, -48, 48), q = q, enabled = true}
    graph.count += 1
    graph.serial += 1
    return graph.count - 1, true
}

FreqGraphRemove :: proc(graph: ^FreqGraph, index: int) {
    if index < 0 || index >= graph.count { return }
    for i in index ..< graph.count - 1 { graph.bands[i] = graph.bands[i + 1] }
    graph.count -= 1
    graph.serial += 1
}

FreqGraphSelect :: proc(graph: ^FreqGraph, index: int) {
    for i in 0 ..< graph.count { graph.bands[i].selected = i == index }
}

// ------------------------------------------------------------------------------------------------------------------------
// The filters

@(private)
freqSampleRate :: proc(graph: ^FreqGraph) -> f64 {
    return f64(graph.sample_rate) if graph.sample_rate > 0 else 48000
}

// The magnitude (dB) of one band at a frequency (Hz): a biquad of the RBJ cookbook
FreqBandResponse :: proc(band: FreqBand, sample_rate: f32, frequency: f32) -> f32 {
    rate: f64 = f64(sample_rate) if sample_rate > 0 else 48000
    q: f64 = f64(band.q) if band.q > 0 else 0.7071
    nyquist: f64 = rate * 0.5 - 1
    w0: f64 = 2 * math.PI * min(f64(band.frequency), nyquist) / rate
    cosine, sine: f64 = math.cos(w0), math.sin(w0)
    alpha: f64 = sine / (2 * q)
    amp: f64 = math.pow(10, f64(band.gain) / 40)
    b0, b1, b2, a0, a1, a2: f64
    switch band.kind {
    case .BELL:
        b0, b1, b2 = 1 + alpha * amp, -2 * cosine, 1 - alpha * amp
        a0, a1, a2 = 1 + alpha / amp, -2 * cosine, 1 - alpha / amp
    case .LOW_SHELF:
        root: f64 = 2 * math.sqrt(amp) * alpha
        b0, b1, b2 = amp * ((amp + 1) - (amp - 1) * cosine + root), 2 * amp * ((amp - 1) - (amp + 1) * cosine), amp * ((amp + 1) - (amp - 1) * cosine - root)
        a0, a1, a2 = (amp + 1) + (amp - 1) * cosine + root, -2 * ((amp - 1) + (amp + 1) * cosine), (amp + 1) + (amp - 1) * cosine - root
    case .HIGH_SHELF:
        root: f64 = 2 * math.sqrt(amp) * alpha
        b0, b1, b2 = amp * ((amp + 1) + (amp - 1) * cosine + root), -2 * amp * ((amp - 1) + (amp + 1) * cosine), amp * ((amp + 1) + (amp - 1) * cosine - root)
        a0, a1, a2 = (amp + 1) - (amp - 1) * cosine + root, 2 * ((amp - 1) - (amp + 1) * cosine), (amp + 1) - (amp - 1) * cosine - root
    case .LOW_CUT:
        b0, b1, b2 = (1 + cosine) * 0.5, -(1 + cosine), (1 + cosine) * 0.5
        a0, a1, a2 = 1 + alpha, -2 * cosine, 1 - alpha
    case .HIGH_CUT:
        b0, b1, b2 = (1 - cosine) * 0.5, 1 - cosine, (1 - cosine) * 0.5
        a0, a1, a2 = 1 + alpha, -2 * cosine, 1 - alpha
    case .NOTCH:
        b0, b1, b2 = 1, -2 * cosine, 1
        a0, a1, a2 = 1 + alpha, -2 * cosine, 1 - alpha
    }
    w: f64 = 2 * math.PI * min(f64(frequency), nyquist) / rate
    c1, s1, c2, s2: f64 = math.cos(w), math.sin(w), math.cos(2 * w), math.sin(2 * w)
    numerator: f64 = math.pow(b0 + b1 * c1 + b2 * c2, 2) + math.pow(b1 * s1 + b2 * s2, 2)
    denominator: f64 = math.pow(a0 + a1 * c1 + a2 * c2, 2) + math.pow(a1 * s1 + a2 * s2, 2)
    if denominator <= 0 || numerator <= 0 { return -120 }
    return f32(10 * math.log10(numerator / denominator))
}

// The response of all enabled bands together (dB)
FreqGraphResponse :: proc(graph: ^FreqGraph, frequency: f32) -> (db: f32) {
    for i in 0 ..< graph.count {
        if graph.bands[i].enabled { db += FreqBandResponse(graph.bands[i], graph.sample_rate, frequency) }
    }
    return
}

// ------------------------------------------------------------------------------------------------------------------------
// Where things are

@(private)
freqMin :: proc(view: ^FreqGraphView) -> f32 { return view.min_frequency if view.min_frequency > 0 else 20 }
@(private)
freqMax :: proc(view: ^FreqGraphView) -> f32 { return view.max_frequency if view.max_frequency > 0 else 20000 }

FreqGraphRange :: proc(view: ^FreqGraphView) -> f32 {
    return view.range_db if view.range_db > 0 else 18
}

FreqGraphAreas :: proc(rect: Rect) -> FreqAreas {
    grid: Rect = {rect.x + FREQ_AXIS_LEFT, rect.y + 6, max(rect.z - FREQ_AXIS_LEFT - 6, 0), max(rect.w - FREQ_AXIS_BOTTOM - 6, 0)}
    return {grid = grid, axis_left = {rect.x, grid.y, FREQ_AXIS_LEFT, grid.w}, axis_bottom = {grid.x, grid.y + grid.w, grid.z, FREQ_AXIS_BOTTOM}}
}

FreqGraphX :: proc(view: ^FreqGraphView, areas: FreqAreas, frequency: f32) -> f32 {
    low, high: f64 = f64(freqMin(view)), f64(freqMax(view))
    return areas.grid.x + f32(math.ln(clamp(f64(frequency), low, high) / low) / math.ln(high / low)) * areas.grid.z
}

FreqGraphFrequencyAt :: proc(view: ^FreqGraphView, areas: FreqAreas, x: f32) -> f32 {
    low, high: f64 = f64(freqMin(view)), f64(freqMax(view))
    t: f64 = clamp(f64(x - areas.grid.x) / f64(max(areas.grid.z, 1)), 0, 1)
    return f32(low * math.pow(high / low, t))
}

FreqGraphY :: proc(view: ^FreqGraphView, areas: FreqAreas, db: f32) -> f32 {
    range: f32 = FreqGraphRange(view)
    return areas.grid.y + (range - clamp(db, -range, range)) / (2 * range) * areas.grid.w
}

FreqGraphGainAt :: proc(view: ^FreqGraphView, areas: FreqAreas, y: f32) -> f32 {
    range: f32 = FreqGraphRange(view)
    return clamp(range - (y - areas.grid.y) / max(areas.grid.w, 1) * 2 * range, -range, range)
}

// Where the node of a band is: a cut and a notch sit on the 0 dB line
FreqGraphNode :: proc(view: ^FreqGraphView, areas: FreqAreas, band: FreqBand) -> Vec2 {
    gain: f32 = band.gain if band.kind == .BELL || band.kind == .LOW_SHELF || band.kind == .HIGH_SHELF else 0
    return {FreqGraphX(view, areas, band.frequency), FreqGraphY(view, areas, gain)}
}

FreqGraphBandAt :: proc(graph: ^FreqGraph, view: ^FreqGraphView, areas: FreqAreas, point: Vec2) -> int {
    best: int = -1
    best_distance: f32 = FREQ_PICK_RADIUS * FREQ_PICK_RADIUS
    for i in 0 ..< graph.count {
        node: Vec2 = FreqGraphNode(view, areas, graph.bands[i])
        distance: f32 = (node.x - point.x) * (node.x - point.x) + (node.y - point.y) * (node.y - point.y)
        if distance <= best_distance {
            best_distance = distance
            best = i
        }
    }
    return best
}

// ------------------------------------------------------------------------------------------------------------------------
// The widget

UiFreqGraph :: proc(ctx: ^Context, name: string, graph: ^FreqGraph, view: ^FreqGraphView, size: Size = {}) -> (changed: bool) {
    id: Id = UiId(ctx, name)
    state: ^WidgetState = stateGet(ctx, id)
    interaction: Interaction = widgetBehavior(ctx, id)
    view.graph = graph
    view.rect = state.rect
    areas: FreqAreas = FreqGraphAreas(view.rect)
    mouse: Vec2 = ctx.input.mouse_position
    serial_before: u64 = graph.serial
    live: bool = ctx.disabled_depth == 0
    hovering: bool = ctx.hover == id && live
    view.mouse = mouse
    view.fine = .SHIFT in ctx.input.modifiers
    view.inside = hovering && RectContains(areas.grid, mouse)
    if view.hover_band >= graph.count || view.gesture == .NONE && !hovering { view.hover_band = -1 }
    if view.gesture == .NONE && !hovering { view.grab = -1 }

    if hovering && view.gesture == .NONE && ctx.input.wheel.y != 0 {
        index: int = FreqGraphBandAt(graph, view, areas, mouse)
        if index >= 0 {
            band: ^FreqBand = &graph.bands[index]
            band.q = clamp((band.q if band.q > 0 else 0.7071) * math.pow(FREQ_Q_STEP, ctx.input.wheel.y), FREQ_Q_MIN, FREQ_Q_MAX)
            graph.serial += 1
            freqTell(graph, {kind = .CHANGED, band = index, data = band^})
        }
    }

    if interaction.pressed && ctx.input.mouse_pressed && interaction.hovered && view.gesture == .NONE && live {
        freqPress(graph, view, areas, mouse, interaction.double_clicked)
    } else if view.gesture != .NONE && interaction.pressed && (ctx.input.mouse_down || ctx.input.mouse_released) {
        freqDrag(graph, view, areas, mouse)
        if ctx.input.mouse_released { freqEnd(graph, view) }
    }
    if view.gesture != .NONE && !interaction.pressed { freqEnd(graph, view) }
    view.last_mouse = mouse

    if ctx.focus == id && live && view.gesture == .NONE && (.DELETE in ctx.input.keys || .BACKSPACE in ctx.input.keys) {
        for i := graph.count - 1; i >= 0; i -= 1 {
            if !graph.bands[i].selected { continue }
            gone: FreqBand = graph.bands[i]
            FreqGraphRemove(graph, i)
            freqTell(graph, {kind = .REMOVED, band = i, data = gone})
        }
    }

    view.hover_band = view.grab if view.gesture == .NODE else (FreqGraphBandAt(graph, view, areas, mouse) if hovering else -1)
    ElementOpen(ctx, {
        id = id,
        layout = {size = {size.width if size.width != {} else Grow(), size.height if size.height != {} else Grow()}},
        clip = {horizontal = true, vertical = true, cut = true},
        hit = {.INTERACTIVE, .SCROLL},
        cursor = .HAND if view.hover_band >= 0 else .ARROW,
        draw = {kind = .FREQ_GRAPH, name = IdSplitName(name), user = view, font_size = ctx.style.metrics.font_size},
    })
    ElementClose(ctx)
    return graph.serial != serial_before
}

@(private)
freqPress :: proc(graph: ^FreqGraph, view: ^FreqGraphView, areas: FreqAreas, mouse: Vec2, double: bool) {
    if !RectContains(areas.grid, mouse) { return }
    index: int = FreqGraphBandAt(graph, view, areas, mouse)
    if index >= 0 {
        if double {
            gone: FreqBand = graph.bands[index]
            FreqGraphRemove(graph, index)
            freqTell(graph, {kind = .REMOVED, band = index, data = gone})
            return
        }
        FreqGraphSelect(graph, index)
        freqTell(graph, {kind = .SELECTION, band = index})
        view.gesture, view.grab, view.moved = .NODE, index, false
        view.drag_position = FreqGraphNode(view, areas, graph.bands[index])
    } else if double {
        FreqGraphSelect(graph, -1)
        if added, ok := FreqGraphAdd(graph, .BELL, FreqGraphFrequencyAt(view, areas, mouse.x), FreqGraphGainAt(view, areas, mouse.y)); ok {
            graph.bands[added].selected = true
            freqTell(graph, {kind = .ADDED, band = added, data = graph.bands[added]})
        }
    } else {
        FreqGraphSelect(graph, -1)
        freqTell(graph, {kind = .SELECTION, band = -1})
    }
}

@(private)
freqDrag :: proc(graph: ^FreqGraph, view: ^FreqGraphView, areas: FreqAreas, mouse: Vec2) {
    if view.gesture != .NODE || view.grab < 0 || view.grab >= graph.count { return }
    delta: Vec2 = mouse - view.last_mouse
    if delta == {} { return }
    if view.fine { delta *= 0.1 }
    view.drag_position += delta
    band: ^FreqBand = &graph.bands[view.grab]
    band.frequency = FreqGraphFrequencyAt(view, areas, view.drag_position.x)
    if band.kind == .BELL || band.kind == .LOW_SHELF || band.kind == .HIGH_SHELF { band.gain = FreqGraphGainAt(view, areas, view.drag_position.y) }
    view.moved = true
    graph.serial += 1
}

@(private)
freqEnd :: proc(graph: ^FreqGraph, view: ^FreqGraphView) {
    if view.gesture == .NODE && view.moved && view.grab >= 0 && view.grab < graph.count {
        freqTell(graph, {kind = .CHANGED, band = view.grab, data = graph.bands[view.grab]})
    }
    view.gesture, view.moved = .NONE, false
}
