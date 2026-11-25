#+private file
package demo_common

// Four screens of Nota (odin_plug/references/nota, a DAW) recreated with this library: the arrangement with a browser and a device strip, the mixer, the modular
// view (the signal chain of a track as a node graph) and the piano roll. They are the screenshots in nota/assets/screenshots, made from the widgets that exist.
// Where Nota has a widget that `ui` does not (see docs/NOTA_GAP.md) the screen draws it by hand with a custom element: those places are marked `GAP`, and each is one
// entry of that list, so the demo is also the checklist of what the library still needs.

import "core:fmt"
import "core:math"
import ui ".."
import ui_default "../default_style"
import kit "../../demo_kit"

@(private="package")
demo_nota: kit.Demo = {
    name = "nota",
    init = init,
    draw = draw,
    script = script,
}

SCREENS: [4]string = {"Arrangement", "Mixer", "Modular", "Piano roll"}
TRACK_NAMES: [5]string = {"Drums", "Bass", "Keys", "Lead", "Texture"}
TRACK_KINDS: [5]string = {"MIDI", "MIDI", "MIDI", "MIDI", "Audio"}
TRACK_COLORS: [5]ui.Color = {{110, 190, 90, 255}, {110, 190, 90, 255}, {80, 190, 170, 255}, {90, 150, 210, 255}, {120, 200, 150, 255}}
CHANNELS :: 8
CHANNEL_NAMES: [CHANNELS]string = {"Rhythm", "Drums", "Bass", "Keys", "Lead", "Texture", "Reverb", "Master"}
BROWSER: [7][2]string = {{"Aurora", "Wavetable synth"}, {"Consort", "Paraphonic synth"}, {"Drum Rack", "Built-in"}, {"Flux", "Vector-morph synth"}, {"Grain", "Granular synth"}, {"Instrument Rack", "Built-in"}, {"Keys", "Electric piano"}}
FILTERS: [5]string = {"Synths", "Keys & physical", "Drums", "Samplers", "Racks"}
PRESETS: [4]string = {"Init", "Warm pad", "Glass bell", "Sub bass"}
INPUTS: [3]string = {"All inputs", "In 1", "In 2"}
NOTE_NAMES: [12]string = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

Note :: struct {
    start: f32,         // beats
    length: f32,
    pitch: int,         // MIDI number
    velocity: f32,
}

State :: struct {
    app: UiDemo,
    screen: int,
    playing: bool,
    recording: bool,
    bpm: int,
    time: f32,
    frozen: bool,       // a script stops the clock so that the pictures are the same every time
    // arrangement
    timeline: ui.Timeline,
    view: ui.TimelineView,
    search: [32]u8,
    search_length: int,
    filters: [5]bool,
    preset: int,
    cutoff: f32,
    resonance: f32,
    drift: f32,
    detune: f32,
    pad_pan: f32,
    mod_amount: f32,
    on: [2]bool,
    bands: [8]f32,
    // mixer
    volume: [CHANNELS]f32,
    pan: [CHANNELS]f32,
    send: [CHANNELS]f32,
    input: [CHANNELS]int,
    mute: [CHANNELS]bool,
    solo: [CHANNELS]bool,
    arm: [CHANNELS]bool,
    show_sends: bool,
    show_io: bool,
    // modular
    graph: ui.Graph,
    graph_view: ui.GraphView,
    nodes: [4]ui.NodeHandle,
    // piano roll
    notes: [14]Note,
    snap: int,
    quantize: f32,
    scale_on: bool,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {bpm = 124, cutoff = 0.62, resonance = 0.25, drift = 0.25, detune = 0.04, on = {true, true}, quantize = 80, pad_pan = -0.3, mod_amount = 45, show_sends = true, show_io = true, snap = 1}
    ui_demo_init(&state.app)
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
    for i in 0 ..< CHANNELS {
        state.volume[i] = 0.5 if i % 3 != 0 else 0.7
        state.pan[i] = 0
        state.send[i] = 20 * f32(i % 4)
    }
    state.pan[4] = 0.3
    state.mute[0] = false
    state.bands = {0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5}
    // the arrangement
    ui.TimelineInit(&state.timeline, &state)
    state.view = {zoom = 18, snap = 1}
    for name, i in TRACK_NAMES {
        track, _ := ui.TimelineTrackAdd(&state.timeline, name, 42, color = TRACK_COLORS[i])
        switch i {
        case 0: for bar in 0 ..< 7 { ui.TimelineClipAdd(&state.timeline, track, f64(8 + bar * 8), 7.5, "Beat") }
        case 1: for bar in 1 ..< 7 { ui.TimelineClipAdd(&state.timeline, track, f64(8 + bar * 8), 7.5, "Bass") }
        case 2: for bar in 0 ..< 8 { ui.TimelineClipAdd(&state.timeline, track, f64(bar * 8), 7.5, "Chords") }
        case 3:
            ui.TimelineClipAdd(&state.timeline, track, 16, 16, "Hook")
            ui.TimelineClipAdd(&state.timeline, track, 48, 16, "Hook")
        case 4:
            ui.TimelineClipAdd(&state.timeline, track, 0, 5, "Pad")
            ui.TimelineClipAdd(&state.timeline, track, 32, 5, "Pad")
        }
    }
    for {
        _, has := ui.TimelinePollEvent(&state.timeline)
        if !has { break }
    }
    // the modular view: the chain of the track Keys
    ui.GraphInit(&state.graph)
    names: [4]string = {"Nota Pentad", "Nota EQ-8", "Nota Chamber", "Track output"}
    for name, i in names {
        node, _ := ui.GraphNodeAdd(&state.graph, name, {40 + f32(i) * 240, 160}, color = {})
        state.nodes[i] = node
        if i > 0 { ui.GraphPortAdd(&state.graph, node, "Audio in", .INPUT, 1) } else { ui.GraphPortAdd(&state.graph, node, "MIDI in", .INPUT, 2) }
        if i < 3 { ui.GraphPortAdd(&state.graph, node, "Audio out", .OUTPUT, 1) }
    }
    for i in 0 ..< 3 {
        from: ui.PortHandle = lastPort(state.nodes[i], .OUTPUT)
        to: ui.PortHandle = lastPort(state.nodes[i + 1], .INPUT)
        ui.GraphConnect(&state.graph, from, to)
    }
    for {
        _, has := ui.GraphPollEvent(&state.graph)
        if !has { break }
    }
    // the piano roll: a hook of the lead
    pitches: [14]int = {69, 72, 74, 72, 76, 74, 72, 69, 71, 72, 76, 79, 77, 74}
    for i in 0 ..< len(state.notes) {
        state.notes[i] = {start = f32(i) * 1.0 + (0.5 if i % 4 == 3 else 0), length = 0.5 if i % 3 != 0 else 1.5, pitch = pitches[i], velocity = 0.45 + 0.5 * f32((i * 37) % 10) / 10}
    }
}

lastPort :: proc(node: ui.NodeHandle, kind: ui.PortKind) -> ui.PortHandle {
    port: ^ui.Port = ui.GraphPort(&state.graph, ui.GraphNode(&state.graph, node).first_port)
    found: ui.PortHandle
    for port != nil {
        if port.kind == kind { found = port.handle }
        port = ui.GraphPort(&state.graph, port.next_in_node)
    }
    return found
}

draw :: proc(ctx: ^kit.Context) {
    if !state.frozen { state.time += 1.0 / 60 }
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    screen: ui.Vec2 = c.screen
    if ui.UiPanel(c, "nota", {size = {ui.Fixed(screen.x), ui.Fixed(screen.y)}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(0), gap = 0}) {
        transport(c)
        switch state.screen {
        case 0: arrangement(c, screen)
        case 1: mixer(c)
        case 2: modular(c)
        case 3: pianoRoll(c, screen)
        }
        statusBar(c)
    }
    ui_demo_end(&state.app)
}

// ------------------------------------------------------------------------------------------------------------------------
// The bar on top: the screens, transport, position, tempo, the master level

transport :: proc(c: ^ui.Context) {
    if ui.UiPanel(c, "transport", {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingXY(10, 6), gap = 14, align = {y = .CENTER}}, blocks_pointer = false) {
        ui.UiSegmented(c, "screens", SCREENS[:], &state.screen)
        if ui.UiButton(c, "Stop##t") { state.playing = false }
        ui.UiToggle(c, "Play", &state.playing)
        ui.UiToggle(c, "Rec", &state.recording)
        bars: f32 = state.time * f32(state.bpm) / 60 / 4 if state.playing else 0
        ui.UiLabelf(c, "%d.%d.%02d bars", int(bars) + 1, int(bars * 4) % 4 + 1, int(bars * 400) % 100)
        ui.UiLabelDim(c, "BPM")
        ui.UiDragInt(c, "##bpm", &state.bpm, 0.3, 40, 240, "%.0f", {ui.Fixed(64), {}})
        ui.UiLabel(c, "4 / 4")
        ui.UiLabelDim(c, "1 bar  Auto grid")
        ui.UiSpacer(c)
        ui.UiLabelDim(c, "DSP 2%")
        ui.UiLabelDim(c, "Master")
        ui.UiMeter(c, "master meter", 0.4 + 0.3 * math.sin(state.time * 3), 0.78, 0, 1, {ui.Fixed(120), ui.Fixed(14)}, horizontal = true)
    }
}

statusBar :: proc(c: ^ui.Context) {
    if ui.UiPanel(c, "status", {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingXY(10, 4), gap = 10}, blocks_pointer = false) {
        ui.UiLabelDim(c, "Saved Night Drive.nota")
        ui.UiSpacer(c)
        ui.UiLabelDim(c, "44.1 kHz . 512")
        ui.UiLabelDim(c, "v0.60.1")
    }
}

// ------------------------------------------------------------------------------------------------------------------------
// Arrangement: the browser, the tracks and the devices under them

arrangement :: proc(c: ^ui.Context, screen: ui.Vec2) {
    if ui.UiColumn(c, {size = {ui.Grow(), ui.Grow()}, exact = true}) {
        if ui.UiRow(c, {size = {ui.Grow(), ui.Percent(0.58)}, exact = true}) {
            browser(c)
            ui.UiTimeline(c, "Arrangement", &state.timeline, &state.view, {ui.Grow(), ui.Grow()})
        }
        devices(c)
    }
}

browser :: proc(c: ^ui.Context) {
    if ui.UiPanel(c, "browser", {size = {ui.Fixed(260), ui.Grow()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 8}) {
        ui.UiTextField(c, "##search", state.search[:], &state.search_length, {ui.Grow(), {}})      // GAP: search field with a count and a filter button
        if ui.UiRow(c, {size = {ui.Grow(), ui.Fit()}, gap = 6}) {
            for name, i in FILTERS[:3] {
                if ui.UiChip(c, name, state.filters[i]) { state.filters[i] = !state.filters[i] }
            }
        }
        ui.UiSeparatorText(c, "Built-in")
        for item in BROWSER {
            if ui.UiRow(c, {size = {ui.Grow(), ui.Fit()}, gap = 6, align = {y = .CENTER}}) {
                ui.UiLabel(c, item[0])
                ui.UiSpacer(c)
                ui.UiLabelDim(c, item[1])
            }
        }
    }
}

// The device strip: a card per device with a switch, a preset selector, tabs and the parameters
devices :: proc(c: ^ui.Context) {
    if ui.UiPanel(c, "devices", {size = {ui.Grow(), ui.Grow()}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingAll(8), gap = 8}) {
        if ui.UiPanel(c, "Nota Pentad", {size = {ui.Percent(0.5), ui.Grow()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(8), gap = 8}) {
            deviceHeader(c, "Nota Pentad", &state.on[0])
            if ui.UiRow(c, {size = {ui.Grow(), ui.Grow()}, gap = 18, align = {y = .CENTER}}) {
                knob(c, "Cutoff", &state.cutoff, "%.2f")
                knob(c, "Reson", &state.resonance, "%.2f")
                knob(c, "Drift", &state.drift, "%.2f")
                knob(c, "Detune", &state.detune, "%.2f")
                ui.UiFader(c, "Glide", &state.drift, 0, 1, 0, {ui.Fixed(26), ui.Fixed(96)})
                if ui.UiColumn(c, {size = {ui.Fixed(190), ui.Fit()}, gap = 8}) {
                    ui.UiValueBar(c, "Pan", &state.pad_pan, ui.ValueBarPan(), {ui.Grow(), {}})
                    if ui.UiTagged(c, "modulation") {
                        ui.UiValueBar(c, "Cutoff mod", &state.mod_amount, {minimum = -100, maximum = 100, bipolar = true, format = "%.0f %%"}, {ui.Grow(), {}})
                    }
                }
            }
        }
        if ui.UiPanel(c, "Nota EQ-8", {size = {ui.Grow(), ui.Grow()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(8), gap = 8}) {
            deviceHeader(c, "Nota EQ-8", &state.on[1])
            ui.UiCustom(c, "##eq graph", eqGraph, {ui.Grow(), ui.Grow()}, nil, 0, true)        // GAP: frequency graph with draggable bands
        }
    }
}

// GAP: the preset selector (arrows + dropdown) and the card header
deviceHeader :: proc(c: ^ui.Context, title: string, on: ^bool) {
    if ui.UiRow(c, {size = {ui.Grow(), ui.Fit()}, gap = 8, align = {y = .CENTER}}) {
        ui.UiLabel(c, title)
        ui.UiButton(c, "<##prev", {ui.Fixed(24), {}})
        ui.UiDropdown(c, "##preset", PRESETS[:], &state.preset, {ui.Fixed(140), {}})
        ui.UiButton(c, ">##next", {ui.Fixed(24), {}})
        ui.UiSpacer(c)
        ui.UiSwitch(c, "##on", on)
    }
}

knob :: proc(c: ^ui.Context, name: string, value: ^f32, format: string) {
    if ui.UiPanel(c, name, {size = {ui.Fit(), ui.Fit()}, direction = .TOP_TO_BOTTOM, gap = 2, align = {x = .CENTER}}, blocks_pointer = false) {
        ui.UiKnob(c, name, value, 0, 1, 0.5, {ui.Fixed(52), ui.Fixed(52)}, format)
        ui.UiLabelDim(c, name)
    }
}

// The EQ plot: a log frequency axis, a dB axis, the curve of the eight bands and a node on each (drawn by hand; the nodes are not draggable here)
eqGraph :: proc(c: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^ui_default.Painter = ui_default.PainterOf(c)
    theme: ^ui_default.Theme = &painter.theme
    area: ui.Rect = info.rect
    ui_default.FillRounded(painter, area, 0.05, theme.track)
    for db in 0 ..< 5 {
        y: f32 = area.y + area.w * f32(db) / 4
        painter.fill_rect(painter, {area.x, y, area.z, 1}, theme.border)
    }
    freqs: [8]f32 = {0.05, 0.17, 0.32, 0.47, 0.6, 0.72, 0.84, 0.95}
    points: [64]ui.Vec2
    for i in 0 ..< len(points) {
        t: f32 = f32(i) / f32(len(points) - 1)
        gain: f32 = 0
        for band in 0 ..< 8 {
            gain += (0.5 - state.bands[band] + (0.07 if band % 2 == 0 else -0.03)) * math.exp(-math.pow((t - freqs[band]) * 7, 2))
        }
        points[i] = {area.x + t * area.z, area.y + area.w * (0.5 - gain * 0.8)}
    }
    ui_default.Polyline(painter, points[:], false, 2, theme.accent, .ROUND)
    for band in 0 ..< 8 {
        x: f32 = area.x + freqs[band] * area.z
        ui_default.Disc(painter, {x, area.y + area.w * 0.5}, 7, theme.accent if band == 1 else theme.text_dim)
        ui_default.Disc(painter, {x, area.y + area.w * 0.5}, 5, theme.track)
    }
}

// ------------------------------------------------------------------------------------------------------------------------
// Mixer: a strip per channel

mixer :: proc(c: ^ui.Context) {
    if ui.UiColumn(c, {size = {ui.Grow(), ui.Grow()}, padding = ui.PaddingAll(8), gap = 8}) {
        if ui.UiRow(c, {size = {ui.Grow(), ui.Grow()}, gap = 4}) {
            for i in 0 ..< CHANNELS { strip(c, i) }
        }
        if ui.UiPanel(c, "mixer bar", {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, gap = 10, align = {y = .CENTER}}) {
            ui.UiLabelDim(c, "Show")
            ui.UiToggle(c, "Sends", &state.show_sends)
            ui.UiToggle(c, "I/O", &state.show_io)
            ui.UiLabelDim(c, "Pan law  Stereo / Balance")
        }
    }
}

strip :: proc(c: ^ui.Context, i: int) {
    name: string = CHANNEL_NAMES[i]
    if ui.UiPanel(c, name, {size = {ui.Grow(), ui.Grow()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(8), gap = 6, align = {x = .CENTER}}) {
        ui.UiTitle(c, name)
        if state.show_io {
            ui.UiLabelDim(c, "MIDI in" if i > 0 && i < 5 else "Sum bus")
            if i > 0 && i < 5 { ui.UiDropdown(c, ui.UiFormat(c, "##in%d", i), INPUTS[:], &state.input[i], {ui.Grow(), {}}) }
        }
        if state.show_sends {
            ui.UiValueBar(c, ui.UiFormat(c, "A##s%d", i), &state.send[i], {format = "%.0f %%", maximum = 100, snap = 1}, {ui.Grow(), {}})
        }
        ui.UiKnob(c, ui.UiFormat(c, "Pan##p%d", i), &state.pan[i], -1, 1, 0, {ui.Fixed(44), ui.Fixed(44)}, "%.1f")   // GAP: pan with the centre mark and 30L / C / 12R
        if ui.UiRow(c, {size = {ui.Grow(), ui.Grow()}, gap = 8, align = {x = .CENTER}}) {
            ui.UiFader(c, ui.UiFormat(c, "Vol##v%d", i), &state.volume[i], 0, 1, 0.7, {ui.Fixed(26), ui.Grow()}, "%.2f")    // GAP: dB scale next to the fader
            level: f32 = state.volume[i] * (0.55 + 0.4 * math.sin(state.time * (2 + f32(i)) + f32(i)))
            ui.UiMeter(c, ui.UiFormat(c, "meter %d", i), max(level, 0), max(level, 0) * 1.1, 0, 1, {ui.Fixed(10), ui.Grow()})
        }
        if ui.UiRow(c, {size = {ui.Grow(), ui.Fit()}, gap = 4, align = {x = .CENTER}}) {
            ui.UiToggle(c, ui.UiFormat(c, "M##m%d", i), &state.mute[i])
            ui.UiToggle(c, ui.UiFormat(c, "S##s%d", i), &state.solo[i])
            if i < 6 { ui.UiToggle(c, ui.UiFormat(c, "R##r%d", i), &state.arm[i]) }
        }
    }
}

// ------------------------------------------------------------------------------------------------------------------------
// Modular: the chain of a track as a graph

modular :: proc(c: ^ui.Context) {
    if ui.UiRow(c, {size = {ui.Grow(), ui.Grow()}, exact = true}) {
        if ui.UiGraph(c, "chain", &state.graph, &state.graph_view, {ui.Grow(), ui.Grow()}) {
            order: [4]ui.NodeHandle
            count: int = ui.GraphNodesByDepth(&state.graph, order[:], &state.graph_view)
            for node in order[:count] {
                if ui.UiGraphNode(c, &state.graph, node) {
                    port: ^ui.Port = ui.GraphPort(&state.graph, ui.GraphNode(&state.graph, node).first_port)
                    for port != nil {
                        ui.UiGraphPin(c, &state.graph, port.handle)
                        port = ui.GraphPort(&state.graph, port.next_in_node)
                    }
                }
            }
        }
    }
}

// ------------------------------------------------------------------------------------------------------------------------
// Piano roll

pianoRoll :: proc(c: ^ui.Context, screen: ui.Vec2) {
    if ui.UiColumn(c, {size = {ui.Grow(), ui.Grow()}, exact = true}) {
        if ui.UiPanel(c, "clip bar", {size = {ui.Grow(), ui.Fit()}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingXY(10, 6), gap = 12, align = {y = .CENTER}}) {
            ui.UiTitle(c, "Hook")
            ui.UiLabelDim(c, "MIDI")
            snaps: [4]string = {"1/4", "1/8", "1/16", "1/32"}
            ui.UiDropdown(c, "##snap", snaps[:], &state.snap, {ui.Fixed(80), {}})
            ui.UiLabelDim(c, "Quantize")
            ui.UiValueBar(c, "Strength", &state.quantize, {maximum = 100, default_value = 100, format = "%.0f %%", snap = 1}, {ui.Fixed(140), {}})
            ui.UiToggle(c, "Scale", &state.scale_on)
            ui.UiSpacer(c)
            ui.UiLabelDim(c, "32 beats")
        }
        ui.UiCustom(c, "##roll", rollDraw, {ui.Grow(), ui.Grow()}, nil, 0, true)       // GAP: piano roll (keys, notes, ruler, velocity lane)
    }
}

KEY_WIDTH :: 54
RULER_HEIGHT :: 22
VELOCITY_HEIGHT :: 90
LOW_NOTE :: 57
HIGH_NOTE :: 84
BEATS_SHOWN :: 16

rollDraw :: proc(c: ^ui.Context, info: ^ui.DrawInfo) {
    painter: ^ui_default.Painter = ui_default.PainterOf(c)
    theme: ^ui_default.Theme = &painter.theme
    area: ui.Rect = info.rect
    grid: ui.Rect = {area.x + KEY_WIDTH, area.y + RULER_HEIGHT, area.z - KEY_WIDTH, area.w - RULER_HEIGHT - VELOCITY_HEIGHT}
    rows: int = HIGH_NOTE - LOW_NOTE + 1
    row_height: f32 = grid.w / f32(rows)
    beat_width: f32 = grid.z / BEATS_SHOWN
    painter.fill_rect(painter, grid, theme.track)
    for note in LOW_NOTE ..= HIGH_NOTE {
        y: f32 = grid.y + f32(HIGH_NOTE - note) * row_height
        pitch_class: int = note % 12
        black: bool = pitch_class == 1 || pitch_class == 3 || pitch_class == 6 || pitch_class == 8 || pitch_class == 10
        if black { painter.fill_rect(painter, {grid.x, y, grid.z, row_height}, {0, 0, 0, 50}) }
        painter.fill_rect(painter, {area.x, y, KEY_WIDTH - 2, row_height - 1}, theme.panel if black else theme.track)
        if pitch_class == 0 { painter.draw_text(painter, fmt.tprintf("C%d", note / 12 - 1), {area.x + 6, y}, row_height * 0.9, theme.text_dim) }
    }
    for beat in 0 ..= BEATS_SHOWN {
        x: f32 = grid.x + f32(beat) * beat_width
        bar: bool = beat % 4 == 0
        painter.fill_rect(painter, {x, grid.y, 1, grid.w + VELOCITY_HEIGHT}, theme.border if !bar else theme.text_dim)
        if bar { painter.draw_text(painter, fmt.tprintf("%d", beat / 4 + 9), {x + 4, area.y + 3}, 13, theme.text) }
    }
    ui_default.Line(painter, {grid.x - 20, grid.y}, {grid.x - 20, grid.y}, 1, theme.accent)
    // the notes and under them their velocities
    velocity_area: ui.Rect = {grid.x, grid.y + grid.w, grid.z, VELOCITY_HEIGHT}
    painter.fill_rect(painter, velocity_area, theme.panel)
    for note in state.notes {
        if note.pitch < LOW_NOTE || note.pitch > HIGH_NOTE || note.start >= BEATS_SHOWN { continue }
        x: f32 = grid.x + note.start * beat_width
        y: f32 = grid.y + f32(HIGH_NOTE - note.pitch) * row_height
        ui_default.FillRounded(painter, {x, y + 1, note.length * beat_width - 1, row_height - 2}, 0.2, theme.accent_soft)
        stem: f32 = (VELOCITY_HEIGHT - 12) * note.velocity
        painter.fill_rect(painter, {x - 1, velocity_area.y + VELOCITY_HEIGHT - 4 - stem, 2, stem}, theme.accent)
        ui_default.Disc(painter, {x, velocity_area.y + VELOCITY_HEIGHT - 4 - stem}, 3, theme.accent)
    }
    // the playhead
    head: f32 = grid.x + math.mod(state.time * 2, BEATS_SHOWN) * beat_width if state.playing else grid.x + 0.4 * beat_width
    painter.fill_rect(painter, {head, area.y, 1.5, area.w}, {250, 180, 60, 255})
}

script: []kit.Step = {
    kit.Check(proc(ctx: ^kit.Context) -> bool { state.frozen, state.time = true, 1.3; return true }, "the clock stops"),
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.screen == 0 && ui.TimelineClipCount(&state.timeline) > 20 }, "the arrangement starts with its clips"),
    kit.Capture("nota_arrangement"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { state.screen = 1; return true }, "the mixer"),
    kit.Wait(4),
    kit.Capture("nota_mixer"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { state.screen = 2; return true }, "the modular view"),
    kit.Wait(4),
    kit.Capture("nota_modular"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { state.screen = 3; return true }, "the piano roll"),
    kit.Wait(4),
    kit.Capture("nota_piano_roll"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
