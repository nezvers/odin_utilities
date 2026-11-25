#+private file
package demo_common

// The small controls of an audio program (ui/widgets_pads.odin): a range slider, an XY pad with a ghost point, a pitch wheel that springs back and a modulation wheel that stays, a thin
// scroll bar, a piano keyboard with lit notes and the root marked, and a step grid with a playhead. The script drags the range slider and paints steps.

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_pads: kit.Demo = {
    name = "pads",
    init = init,
    draw = draw,
    script = script,
}

State :: struct {
    app: UiDemo,
    low: f32,
    high: f32,
    x: f32,
    y: f32,
    ghost: [2]f32,
    bend: f32,
    modwheel: f32,
    offset: f32,
    lit: [128]bool,
    cells: [32]f32,
    details: [32]ui.StepDetail,
    played: int,
    velocity: f32,
    root: int,
    mask: u16,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {low = 25, high = 70, x = 0.3, y = 0.65, ghost = {0.45, 0.8}, modwheel = 0.35, offset = 120, played = -1, root = 2, mask = 0b101010110101}
    for step in ([]int{0, 3, 6, 8, 11, 14}) { state.cells[step] = 1 }          // kick
    for step in ([]int{4, 12}) { state.cells[16 + step] = 1 }                  // snare
    state.details[14].ratchet = 3                                              // a roll on the last kick
    state.details[16 + 12].length = 3                                          // a long snare
    ui_demo_init(&state.app)
    ctx.background = {17, 19, 21, 255}
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "pads", {size = {ui.Fixed(620), ui.Fixed(560)}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 10}) {
        if ui.UiRow(c, {gap = 14}) {
            if ui.UiColumn(c, {gap = 10}) {
                ui.UiLabelDim(c, "Range")
                ui.UiRangeSlider(c, "range", &state.low, &state.high, 0, 100, {ui.Fixed(250), {}}, "%.0f")
                ui.UiLabelDim(c, "Scroll")
                ui.UiScrollBar(c, "bar", &state.offset, 1000, 250, true, {ui.Fixed(250), {}})
                ui.UiLabelDim(c, "Steps")
                ui.UiStepGrid(c, "steps", state.cells[:], 2, 16, 5, 4, 1, {ui.Fixed(250), ui.Fixed(60)}, details = state.details[:])
            }
            ui.UiXYPad(c, "xy", &state.x, &state.y, {0.5, 0.5}, &state.ghost, {ui.Fixed(130), ui.Fixed(130)})
            ui.UiWheel(c, "bend", &state.bend, -1, 1, 0, true, {ui.Fixed(34), ui.Fixed(130)})
            ui.UiWheel(c, "mod", &state.modwheel, 0, 1, 0, false, {ui.Fixed(34), ui.Fixed(130)})
        }
        ui.UiLabelDim(c, "Key and scale")
        ui.UiScalePicker(c, "scale", &state.root, &state.mask, {ui.Fixed(590), {}})
        ui.UiLabelDim(c, "Keyboard (the notes of the scale lit, the root marked)")
        for pitch in 48 ..= 72 { state.lit[pitch] = ui.ScaleContains(state.root, state.mask, pitch) }
        pressed, _ := ui.UiKeyboard(c, "keys", 48, 72, &state.lit, 48 + (state.root + 12 - 48 % 12) % 12, {ui.Fixed(520), ui.Fixed(110)}, velocity = &state.velocity)
        if pressed >= 0 { state.played = pressed }
    }
    ui_demo_end(&state.app)
}

target: ui.Vec2

find :: proc(name: string, fx: f32, fy: f32) -> bool {
    rect, found := ui.UiElementRect(&state.app.ctx, ui.UiIdPath("pads", name))
    if found { target = {rect.x + rect.z * fx, rect.y + rect.w * fy} }
    return found
}

script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("keys", 0.5, 0.9) }, "the keyboard"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.played >= 48 && state.played <= 72 }, "a press on a key plays it"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.velocity > 0.75 }, "a press low on the key is hard"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find("steps", 0.5 / 16 + 1.0 / 16, 0.75) }, "a step of the second row"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.cells[16 + 1] == 1 }, "a click turns a step on"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.details[14].ratchet == 3 && state.details[16 + 12].length == 3 }, "the grid keeps its details"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.mask == 0b101010110101 && state.root == 2 }, "D major to start"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        id: ui.Id = ui.UiIdPath("pads", "scale", "D# ##n1")
        r, f := ui.UiElementRect(&state.app.ctx, id)
        if f { target = {r.x + r.z * 0.5, r.y + r.w * 0.5} }
        return f
    }, "the second note chip"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.mask == 0b101010110111 && ui.ScaleName(state.mask) == "Custom" }, "a click adds a note and the scale is custom"),
    kit.MoveTo({900, 20}),
    kit.Wait(3),
    kit.Capture("pads"),
    kit.Wait(2),
}
