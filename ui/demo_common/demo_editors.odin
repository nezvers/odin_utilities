#+private file
package demo_common

// The two graph editors of an audio program: the frequency response graph with draggable band nodes (an equalizer, `ui.UiFreqGraph`) and the waveform view with a ruler, selection and
// markers (`ui.UiWaveform`). The script drags a node down and selects a region of the wave.

import "core:math"
import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_editors: kit.Demo = {
    name = "editors",
    init = init,
    draw = draw,
    script = script,
}

State :: struct {
    app: UiDemo,
    eq: ui.FreqGraph,
    eq_view: ui.FreqGraphView,
    eq_bands: [6]ui.FreqBand,
    spectrum: [256]f32,
    wave: ui.Waveform,
    wave_view: ui.WaveformView,
    samples: [96000]f32,
    peaks: [512]ui.WavePeak,
    markers: [8]ui.WaveMarker,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_demo_init(&state.app)
    ctx.background = {17, 19, 21, 255}
    ui.FreqGraphInit(&state.eq, state.eq_bands[:], 48000)
    ui.FreqGraphAdd(&state.eq, .LOW_CUT, 40, 0, 0.707)
    ui.FreqGraphAdd(&state.eq, .BELL, 250, -3, 1.2)
    ui.FreqGraphAdd(&state.eq, .BELL, 1000, 6, 1)
    ui.FreqGraphAdd(&state.eq, .HIGH_SHELF, 8000, -4, 0.7)
    state.eq.spectrum = state.spectrum[:]
    for i in 0 ..< len(state.spectrum) {
        f: f32 = f32(i) / f32(len(state.spectrum) - 1) * 24000
        state.spectrum[i] = -26 - 24 * math.log10(1 + f / 250) + 6 * math.sin(f32(i) * 0.7)
    }
    // two seconds: a decaying burst every half second over a low tone
    for i in 0 ..< len(state.samples) {
        t: f64 = f64(i) / 48000
        burst: f64 = math.exp(-math.mod(t, 0.5) * 9)
        state.samples[i] = f32(0.8 * burst * math.sin(t * 2 * math.PI * 220 * (1 + 2 * burst)) + 0.12 * math.sin(t * 2 * math.PI * 55))
    }
    ui.WaveformInit(&state.wave, state.samples[:], 48000, state.markers[:])
    ui.WaveformBuildPeaks(&state.wave, state.peaks[:], 256)
    ui.WaveformAddMarker(&state.wave, 24000, "Hit")
    ui.WaveformAddMarker(&state.wave, 72000, "Drop")
    state.wave_view.show_playhead, state.wave_view.playhead = true, 12000
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "editors", {size = {ui.Fixed(520), ui.Fixed(450)}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 10}) {
        ui.UiFreqGraph(c, "eq", &state.eq, &state.eq_view, {ui.Fixed(500), ui.Fixed(260)})
        ui.UiWaveform(c, "wave", &state.wave, &state.wave_view, {ui.Fixed(500), ui.Fixed(160)})
    }
    ui_demo_end(&state.app)
}

// The panel is at (0, 0), padding 10: the graph is at (10, 10) 500 x 260 (its grid from x 48, y 16, 444 x 236, 18 dB range), the bell of 1 kHz +6 dB is at (299, 95);
// the wave is at (10, 280) 500 x 160 (ruler 20 high, the body from y 300)
script: []kit.Step = {
    kit.Wait(4),
    kit.MoveTo({299, 95}),
    kit.Wait(3),
    kit.Drag({299, 95}, {299, 140}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        band: ui.FreqBand = state.eq_bands[2]
        return band.gain < 0 && abs(band.frequency - 1000) < 40
    }, "dragging the node down lowers the gain and keeps the frequency"),
    kit.Drag({120, 370}, {260, 370}, 8),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.wave_view.has_selection && state.wave_view.selection_end > state.wave_view.selection_start }, "dragging over the wave selects a region"),
    kit.MoveTo({600, 20}),
    kit.Wait(3),
    kit.Capture("editors"),
    kit.Wait(2),
}
