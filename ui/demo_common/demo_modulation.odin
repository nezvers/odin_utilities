#+private file
package demo_common

// The modulation matrix of ui/mod_matrix.odin: three sources, five targets. The script connects an empty cell with a click, drags another to a negative amount and checks the amounts.

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_modulation: kit.Demo = {
    name = "modulation",
    init = init,
    draw = draw,
    script = script,
}

SOURCES: [4]string = {"LFO 1", "LFO 2", "Envelope", "Mod wheel"}
TARGETS: [5]string = {"Cutoff", "Resonance", "Pitch", "Pan", "Level"}

State :: struct {
    app: UiDemo,
    amounts: [20]f32,
    routing: ui.ModMatrix,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {}
    state.routing = {sources = SOURCES[:], targets = TARGETS[:], amounts = state.amounts[:]}
    state.amounts[0] = 0.45
    state.amounts[2] = -0.2
    state.amounts[6] = 0.8
    state.amounts[10] = 1
    state.amounts[13] = -0.6
    state.amounts[19] = 0.3
    ui_demo_init(&state.app)
    ctx.background = {17, 19, 21, 255}
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "mod", {size = {ui.Fixed(560), ui.Fixed(260)}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 8}) {
        ui.UiLabelDim(c, "Click to connect, drag to set, wheel to nudge, double click to clear")
        ui.UiModMatrix(c, "matrix", &state.routing, {ui.Fixed(536), ui.Fixed(170)})
        if row, column, ok := ui.ModMatrixSelected(c, "matrix", &state.routing); ok {
            ui.UiLabelf(c, "%s -> %s: %.0f %%", SOURCES[row], TARGETS[column], state.amounts[row * len(TARGETS) + column] * 100)
        } else {
            ui.UiLabelDim(c, "no cell selected")
        }
    }
    ui_demo_end(&state.app)
}

target: ui.Vec2

find :: proc(row: int, column: int, fx: f32, fy: f32) -> bool {
    rect, found := ui.UiElementRect(&state.app.ctx, ui.UiIdPath("mod", "matrix"))
    if !found { return false }
    cell: ui.Rect = ui.ModMatrixCellRect(rect, len(SOURCES), len(TARGETS), row, column)
    target = {cell.x + cell.z * fx, cell.y + cell.w * fy}
    return true
}

script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find(0, 3, 0.5, 0.5) }, "an empty cell"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.amounts[3] == 0.5 }, "a click connects at half"),
    kit.Wait(30),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find(3, 1, 0.5, 0.5) }, "a cell of the last row"),
    kit.MoveAt(&target),
    kit.MouseDownStep(),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return find(3, 1, 0.5, 3.0) }, "three cell heights down"),
    kit.MoveAt(&target),
    kit.Wait(3),
    kit.MouseUpStep(),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.amounts[16] < -0.3 }, "a drag down makes a negative amount"),
    kit.MoveTo({900, 20}),
    kit.Wait(3),
    kit.Capture("modulation"),
    kit.Wait(2),
}
