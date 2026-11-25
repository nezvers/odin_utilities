#+private file
package demo_common

// The history view of ui/history_view.odin beside a small timeline. The script makes four edits (each committed as a step, one with a name of the program) and goes back by a click on a step.

import ui ".."
import kit "../../demo_kit"

@(private="package")
demo_history: kit.Demo = {
    name = "history",
    init = init,
    draw = draw,
    script = script,
}

State :: struct {
    app: UiDemo,
    timeline: ui.Timeline,
    view: ui.TimelineView,
    history: ui.TimelineHistory,
    states: [12]ui.TimelineState,
    track: ui.TrackHandle,
    clip: ui.ClipHandle,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui.TimelineInit(&state.timeline)
    state.view = {zoom = 40, snap = 0.5}
    state.track, _ = ui.TimelineTrackAdd(&state.timeline, "Drums", 50)
    ui.TimelineTrackAdd(&state.timeline, "Bass", 50)
    state.clip, _ = ui.TimelineClipAdd(&state.timeline, state.track, 1, 3, "Beat")
    ui.TimelineHistoryInit(&state.history, state.states[:], &state.timeline)
    state.view.history = &state.history
    ui_demo_init(&state.app)
    ctx.background = {17, 19, 21, 255}
}

draw :: proc(ctx: ^kit.Context) {
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx
    if ui.UiPanel(c, "history demo", {size = {ui.Fixed(700), ui.Fixed(300)}, direction = .LEFT_TO_RIGHT, padding = ui.PaddingAll(10), gap = 10}) {
        ui.UiTimeline(c, "Timeline", &state.timeline, &state.view, {ui.Fixed(470), ui.Fixed(270)})
        if ui.UiColumn(c, {gap = 6}) {
            ui.UiLabelDim(c, "History")
            ui.UiTimelineHistory(c, "steps", &state.history, &state.timeline, 8, {ui.Fixed(190), ui.Fixed(230)})
        }
    }
    ui_demo_end(&state.app)
}

edit :: proc(start: f64, label: string) -> bool {
    ui.TimelineClipPlace(&state.timeline, state.clip, state.track, start, 3)
    ui.TimelineHistoryCommit(&state.history, &state.timeline, label)
    return true
}

target: ui.Vec2

script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return edit(2, "") }, "a move"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        ui.TimelineClipAdd(&state.timeline, state.track, 6, 1.5, "Fill")
        return ui.TimelineHistoryCommit(&state.history, &state.timeline)
    }, "a new clip"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return edit(3, "Nudge by hand") }, "a named step"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return edit(4, "") }, "another move"),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.history.count == 5 && state.history.current == 4 }, "five steps"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        rect, found := ui.UiElementRect(&state.app.ctx, ui.IdFromIndex(2, ui.UiIdPath("history demo", "steps")))
        if found { target = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5} }
        return found
    }, "the third step"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.history.current == 2 && ui.TimelineClipGet(&state.timeline, state.clip).start == 2 }, "a click goes back to that step"),
    kit.MoveTo({900, 20}),
    kit.Wait(3),
    kit.Capture("history"),
    kit.Wait(2),
}
