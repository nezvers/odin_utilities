#+private file
package demo_common

// A track list and a device card of an audio program: `ui.UiTrackHeader` rows (colour strip, fold, name and kind, M / S / R, volume and pan bars, input) and `ui.UiDeviceCard` with a
// preset selector, sections divided by rules and a fold button. The script mutes a track and folds the card.

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_chain: kit.Demo = {
    name = "chain",
    init = init,
    draw = draw,
    script = script,
}

TRACKS :: 4
NAMES: [TRACKS]string = {"Drums", "Bass", "Chords", "Lead"}
KINDS: [TRACKS]string = {"Instrument", "Instrument", "Instrument", "Audio"}
COLORS: [TRACKS]ui.Color = {{200, 90, 80, 255}, {90, 170, 90, 255}, {80, 170, 160, 255}, {80, 130, 200, 255}}
INPUTS: [3]string = {"All inputs", "Ext. in 1", "Resampling"}
PRESETS: [4]string = {"Init", "Warm", "Bright", "Dub"}

State :: struct {
    app: UiDemo,
    mute: [TRACKS]bool,
    solo: [TRACKS]bool,
    arm: [TRACKS]bool,
    volume: [TRACKS]f32,
    pan: [TRACKS]f32,
    input: [TRACKS]int,
    on: bool,
    folded: bool,
    closed: bool,
    preset: int,
    cutoff: f32,
    resonance: f32,
    drive: f32,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {on = true, cutoff = 0.6, resonance = 0.3, drive = 0.2}
    state.volume = {-3, -8.5, -6, 0}
    state.pan = {0, -0.3, 0.25, 0}
    ui_demo_init(&state.app)
    ctx.background = {17, 19, 21, 255}
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "chain", {size = {ui.Fixed(640), ui.Fixed(430)}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 8}) {
        for i in 0 ..< TRACKS {
            header: ui.TrackHeader = {
                name = NAMES[i], kind = KINDS[i], color = COLORS[i], selected = i == 1, mute = &state.mute[i], solo = &state.solo[i], arm = &state.arm[i] if i < 3 else nil,
                volume = &state.volume[i], pan = &state.pan[i], inputs = INPUTS[:], input = &state.input[i],
            }
            ui.UiTrackHeader(c, ui.UiFormat(c, "track%d", i), header)
        }
        card: ui.DeviceCard = {title = "Filter", on = &state.on, folded = &state.folded, close = &state.closed, presets = PRESETS[:], preset = &state.preset}
        if ui.UiDeviceCard(c, "card", card, {ui.Grow(), ui.Fit()}) {
            if ui.UiDeviceSection(c, "filter", "Filter", false) {
                if ui.UiRow(c, {gap = 14}) {
                    ui.UiKnob(c, "Cutoff", &state.cutoff, 0, 1, 0.5, {ui.Fixed(52), ui.Fixed(52)}, "%.2f")
                    ui.UiKnob(c, "Reson", &state.resonance, 0, 1, 0.5, {ui.Fixed(52), ui.Fixed(52)}, "%.2f")
                }
            }
            if ui.UiDeviceSection(c, "drive", "Drive") { ui.UiKnob(c, "Drive", &state.drive, 0, 1, 0, {ui.Fixed(52), ui.Fixed(52)}, "%.2f") }
        }
    }
    ui_demo_end(&state.app)
}

target: ui.Vec2

find :: proc(path: ..string) -> bool {
    rect, found := ui.UiElementRect(&state.app.ctx, ui.UiIdPath(..path))
    if found { target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5} }
    return found
}

script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("chain", "track0", "M##m") }, "the mute button of the first track"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.mute[0] && !state.mute[1] }, "the button mutes its own track"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("chain", "card", "##preset", "##next") }, "the next arrow of the preset selector"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.preset == 1 }, "the arrow chooses the next preset"),
    kit.MoveTo({700, 20}),
    kit.Wait(3),
    kit.Capture("chain"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("chain", "card", "##fold") }, "the fold button of the card"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.folded }, "the chevron folds the card"),
}
