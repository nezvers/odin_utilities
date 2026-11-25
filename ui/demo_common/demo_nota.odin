#+private file
package demo_common

// Four screens of Nota (odin_plug/references/nota, a DAW) recreated with this library: the arrangement with a browser and a device strip, the mixer, the modular
// view (the signal chain of a track as a node graph) and the piano roll. They are the screenshots in nota/assets/screenshots, made from the widgets that exist.
// Where Nota has a widget that `ui` does not (see docs/NOTA_GAP.md) the screen draws it by hand with a custom element: those places are marked `GAP`, and each is one
// entry of that list, so the demo is also the checklist of what the library still needs.

import "core:math"
import ui ".."
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
    overview: ui.Overview,
    sections: [3]ui.OverviewSection,
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
    eq: ui.FreqGraph,
    eq_view: ui.FreqGraphView,
    eq_bands: [8]ui.FreqBand,
    eq_spectrum: [256]f32,
    // mixer
    volume: [CHANNELS]f32,
    levels: [CHANNELS]ui.MixerLevels,
    snap_choice: int,
    eq_preset: int,
    position: [24]u8,
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
    notes: [128]ui.PianoNote,
    roll: ui.PianoRoll,
    roll_view: ui.PianoRollView,
    snap: int,
    quantize: f32,
    scale_on: bool,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {bpm = 124, cutoff = 0.62, resonance = 0.25, drift = 0.25, detune = 0.04, on = {true, true}, quantize = 80, pad_pan = -0.3, mod_amount = 45, show_sends = true, show_io = true, snap = 2, scale_on = true}
    ui_demo_init(&state.app)
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
    for i in 0 ..< CHANNELS {
        state.volume[i] = -9 if i % 3 != 0 else -2
        state.pan[i] = 0
        state.send[i] = 20 * f32(i % 4)
    }
    state.pan[4] = 0.3
    state.mute[0] = false
    ui.FreqGraphInit(&state.eq, state.eq_bands[:], 48000)
    ui.FreqGraphAdd(&state.eq, .LOW_CUT, 30, 0, 0.707)
    ui.FreqGraphAdd(&state.eq, .LOW_SHELF, 120, 3, 0.7)
    ui.FreqGraphAdd(&state.eq, .BELL, 400, -4, 1.4)
    ui.FreqGraphAdd(&state.eq, .BELL, 2500, 5, 0.9)
    ui.FreqGraphAdd(&state.eq, .HIGH_SHELF, 9000, -3, 0.7)
    state.eq_bands[3].selected = true
    state.eq.spectrum = state.eq_spectrum[:]
    for i in 0 ..< len(state.eq_spectrum) {
        f: f32 = f32(i) / f32(len(state.eq_spectrum) - 1) * 24000
        state.eq_spectrum[i] = -28 - 22 * math.log10(1 + f / 300) + 7 * math.sin(f32(i) * 0.9) * math.exp(-f / 9000)
    }
    // the arrangement
    ui.TimelineInit(&state.timeline, &state)
    state.view = {zoom = 18, snap = 1, tempo = 124, beats_per_bar = 4}
    state.sections = {{0, 32, "Intro", {}}, {32, 64, "Verse", {}}, {96, 48, "Chorus", {}}}
    state.overview = {timeline = &state.timeline, view = &state.view, total = 160, sections = state.sections[:]}
    state.snap_choice = int(ui.TimelineSnapChoice.AUTO)
    for name, i in TRACK_NAMES {
        track, _ := ui.TimelineTrackAdd(&state.timeline, name, 42, color = TRACK_COLORS[i])
        switch i {
        case 0: for bar in 0 ..< 7 { addClip(track, f64(8 + bar * 8), 7.5, "Beat", {kind = .STEPS, steps = CLIP_DRUMS[:], rows = 2, content_length = 4}) }
        case 1: for bar in 1 ..< 7 { addClip(track, f64(8 + bar * 8), 7.5, "Bass", {kind = .NOTES, notes = CLIP_BASS[:], content_length = 4}) }
        case 2: for bar in 0 ..< 8 { addClip(track, f64(bar * 8), 7.5, "Chords", {kind = .NOTES, notes = CLIP_CHORDS[:], content_length = 8}) }
        case 3:
            addClip(track, 16, 16, "Hook", {kind = .NOTES, notes = CLIP_HOOK[:], content_length = 8})
            addClip(track, 48, 16, "Hook", {kind = .NOTES, notes = CLIP_HOOK[:], content_length = 8})
        case 4:
            addClip(track, 0, 5, "Pad", {kind = .WAVEFORM, peaks = CLIP_PEAKS[:]})
            addClip(track, 32, 5, "Pad", {kind = .WAVEFORM, peaks = CLIP_PEAKS[:]})
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
    ui.PianoRollInit(&state.roll, state.notes[:])
    state.roll_view = {snap = 0.25, scale_mask = 0b101010110101, scale_root = 0, top_pitch = 86}
    for i in 0 ..< len(pitches) {
        ui.PianoRollAdd(&state.roll, f64(i) * 1.0 + (0.5 if i % 4 == 3 else 0), 0.5 if i % 3 != 0 else 1.5, pitches[i], 0.45 + 0.5 * f32((i * 37) % 10) / 10)
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
        state.view.tempo = f64(state.bpm)
        ui.UiLabelf(c, "%s bars", ui.TimelineBarsBeatsText(state.position[:], &state.view, f64(state.time) if state.playing else 0))
        ui.UiLabelDim(c, "BPM")
        ui.UiDragInt(c, "##bpm", &state.bpm, 0.3, 40, 240, "%.0f", {ui.Fixed(64), {}})
        ui.UiLabel(c, "4 / 4")
        ui.UiDropdown(c, "##grid", ui.TIMELINE_SNAP_NAMES[:], &state.snap_choice, {ui.Fixed(80), {}})
        ui.TimelineApplySnap(&state.view, ui.TimelineSnapChoice(state.snap_choice))
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

// What the clips show inside of themselves (ui/clip_body.odin): data of the program that lives as long as the demo
CLIP_DRUMS: [16]f32 = {1, 0, 0, 0.5, 0, 0, 1, 0,  0, 0, 0.6, 0, 0, 0, 0.6, 0.6}
CLIP_BASS: [4]ui.ClipBodyNote = {{0, 1, 36}, {1.5, 0.5, 36}, {2, 1, 39}, {3, 0.75, 34}}
CLIP_CHORDS: [6]ui.ClipBodyNote = {{0, 3.5, 60}, {0, 3.5, 64}, {0, 3.5, 67}, {4, 3.5, 58}, {4, 3.5, 62}, {4, 3.5, 65}}
CLIP_HOOK: [6]ui.ClipBodyNote = {{0, 1, 72}, {1, 0.5, 74}, {1.5, 0.5, 76}, {2, 2, 79}, {5, 1, 76}, {6, 1.5, 72}}
CLIP_PEAKS: [24]f32 = {0.2, 0.5, 0.8, 0.6, 0.9, 0.7, 0.4, 0.6, 0.85, 0.5, 0.3, 0.7, 0.9, 0.6, 0.45, 0.8, 0.55, 0.3, 0.65, 0.4, 0.25, 0.35, 0.2, 0.1}

addClip :: proc(track: ui.TrackHandle, start: f64, length: f64, name: string, body: ui.ClipBody) {
    clip, _ := ui.TimelineClipAdd(&state.timeline, track, start, length, name)
    ui.TimelineClipSetBody(&state.timeline, clip, body)
}

// ------------------------------------------------------------------------------------------------------------------------
// Arrangement: the browser, the tracks and the devices under them

arrangement :: proc(c: ^ui.Context, screen: ui.Vec2) {
    if ui.UiColumn(c, {size = {ui.Grow(), ui.Grow()}, exact = true}) {
        if ui.UiRow(c, {size = {ui.Grow(), ui.Percent(0.58)}, exact = true}) {
            browser(c)
            if ui.UiColumn(c, {size = {ui.Grow(), ui.Grow()}, exact = true}) {
                ui.UiOverview(c, "Overview", &state.overview, {ui.Grow(), ui.Fixed(34)})
                ui.UiTimeline(c, "Arrangement", &state.timeline, &state.view, {ui.Grow(), ui.Grow()})
            }
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
        pentad: ui.DeviceCard = {title = "Nota Pentad", on = &state.on[0], presets = PRESETS[:], preset = &state.preset}
        if ui.UiDeviceCard(c, "Nota Pentad", pentad, {ui.Percent(0.5), ui.Grow()}) {
            if ui.UiDeviceSection(c, "filter", "Filter", false, {ui.Grow(), ui.Grow()}) {
                if ui.UiRow(c, {gap = 18}) {
                    knob(c, "Cutoff", &state.cutoff, "%.2f")
                    knob(c, "Reson", &state.resonance, "%.2f")
                }
            }
            if ui.UiDeviceSection(c, "osc", "Oscillator", true, {ui.Grow(), ui.Grow()}) {
                if ui.UiRow(c, {gap = 18}) {
                    knob(c, "Drift", &state.drift, "%.2f")
                    knob(c, "Detune", &state.detune, "%.2f")
                }
            }
            if ui.UiDeviceSection(c, "mod", "Modulation", true, {ui.Fixed(210), ui.Grow()}) {
                ui.UiValueBar(c, "Pan", &state.pad_pan, ui.ValueBarPan(), {ui.Grow(), {}})
                if ui.UiTagged(c, "modulation") {
                    ui.UiValueBar(c, "Cutoff mod", &state.mod_amount, {minimum = -100, maximum = 100, bipolar = true, format = "%.0f %%"}, {ui.Grow(), {}})
                }
            }
        }
        eq_card: ui.DeviceCard = {title = "Nota EQ-8", on = &state.on[1], presets = PRESETS[:], preset = &state.eq_preset}
        if ui.UiDeviceCard(c, "Nota EQ-8", eq_card, {ui.Grow(), ui.Grow()}) {
            if ui.UiDeviceSection(c, "graph", "", false, {ui.Grow(), ui.Grow()}) {
                ui.UiFreqGraph(c, "eq graph", &state.eq, &state.eq_view)
            }
        }
    }
}

knob :: proc(c: ^ui.Context, name: string, value: ^f32, format: string) {
    if ui.UiPanel(c, name, {size = {ui.Fit(), ui.Fit()}, direction = .TOP_TO_BOTTOM, gap = 2, align = {x = .CENTER}}, blocks_pointer = false) {
        ui.UiKnob(c, name, value, 0, 1, 0.5, {ui.Fixed(52), ui.Fixed(52)}, format)
        ui.UiLabelDim(c, name)
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
            swing: f32 = 0.55 + 0.4 * math.sin(state.time * (2 + f32(i)) + f32(i))
            left: f32 = state.volume[i] + 20 * math.log10(max(swing, 0.001)) - 6
            right: f32 = state.volume[i] + 20 * math.log10(max(0.55 + 0.4 * math.sin(state.time * (2.3 + f32(i)) + f32(i)), 0.001)) - 6
            state.levels[i] = {left, right, left + 3.5, right + 3}
            ui.UiMixerFader(c, ui.UiFormat(c, "Vol##v%d", i), &state.volume[i], &state.levels[i], 0, {ui.Fixed(104), ui.Grow()})
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
        snap_steps: [4]f64 = {1, 0.5, 0.25, 0.125}
        state.roll_view.snap = snap_steps[state.snap]
        if !state.scale_on { state.roll_view.scale_mask = 0 } else { state.roll_view.scale_mask = 0b101010110101 }
        state.roll_view.playhead = math.mod(f64(state.time) * 2, 16) if state.playing else 0.4
        state.roll_view.show_playhead = true
        ui.UiPianoRoll(c, "roll", &state.roll, &state.roll_view)
    }
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
