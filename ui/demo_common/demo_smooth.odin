#+private file
package demo_common

// Soft edged shapes (ui/aa.odin) next to the plain ones: the toggle switches the mesh off and the same calls draw the old way. Rounded rectangles and rings of many radii, discs, lines
// of many widths at angles (a turning fan), a Bezier curve whose handles move, a polyline with joints and a cable with round ends. Shapes are drawn through the painter of the
// demo, so what is seen is what the style procs get.

import "core:math"
import ui ".."
import ui_default "../default_style"
import kit "../../demo_kit"

@(private="package")
demo_smooth: kit.Demo = {
    name = "smooth",
    init = init,
    draw = draw,
    script = script,
}

State :: struct {
    app: UiDemo,
    plain: bool,
    storage: []ui.AaVertex,
    time: f32,
}

state: State

init :: proc(ctx: ^kit.Context) {
    state = {}
    ui_demo_init(&state.app)
    state.storage = state.app.painter.mesh.vertices
    ctx.background = {17, 19, 21, 255}        // the background of the dark theme (ui_default.THEME_DARK)
}

draw :: proc(ctx: ^kit.Context) {
    state.time += 1.0 / 60
    painter: ^ui_default.Painter = &state.app.painter
    painter.mesh.vertices = nil if state.plain else state.storage
    ui_demo_begin(&state.app, ctx)
    c: ^ui.Context = &state.app.ctx

    // rounded rectangles: radius 2 .. 40, then rings
    x: f32 = 20
    for radius in ([]f32{2, 5, 9, 14, 20, 30}) {
        size: f32 = 60
        ui_default.FillRounded(painter, {x, 80, size, size}, radius / (size * 0.5), {90, 160, 250, 255})
        ui_default.RingRounded(painter, {x, 150, size, size}, radius, 2, {250, 200, 90, 255})
        x += size + 14
    }
    // discs and translucent overlap (a translucent shape has no seam inside)
    for i in 0 ..< 5 {
        ui_default.Disc(painter, {40 + f32(i) * 34, 250}, 6 + f32(i) * 3, {240, 110, 110, 160})
    }
    // a fan of lines of different widths, turning
    center: ui.Vec2 = {520, 190}
    widths: [6]f32 = {0.5, 1, 1.5, 2, 4, 8}
    for width, i in widths {
        angle: f32 = state.time * 0.4 + f32(i) * 0.5
        direction: ui.Vec2 = {math.cos(angle), math.sin(angle)}
        points: [2]ui.Vec2 = {center + direction * 20, center + direction * 100}
        ui_default.Polyline(painter, points[:], false, width, {235, 235, 235, 255}, .ROUND)
    }
    // a Bezier with moving handles, and a polyline with joints
    sway: f32 = math.sin(state.time) * 40
    ui_default.Bezier(painter, {{20, 330}, {120, 260 + sway}, {220, 400 - sway}, {320, 330}}, 4, {120, 220, 150, 255})
    ui_default.Bezier(painter, {{20, 360}, {120, 290 + sway}, {220, 430 - sway}, {320, 360}}, 1, {120, 220, 150, 255}, .BUTT)
    zigzag: [5]ui.Vec2 = {{360, 400}, {400, 320}, {440, 400}, {480, 320}, {520, 400}}
    ui_default.Polyline(painter, zigzag[:], false, 6, {200, 140, 250, 200}, .ROUND)
    ui_default.Polyline(painter, zigzag[:], false, 1, {255, 255, 255, 255})
    // a window of the ui over the shapes
    if ui.UiPanel(c, "smooth", {size = {ui.Fixed(190), ui.Fit()}, direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 8}) {
        ui.UiToggle(c, "Plain edges", &state.plain)
        ui.UiLabelf(c, "triangles: %d", painter.mesh.count / 3)
    }
    ui_demo_end(&state.app)
}

script: []kit.Step = {
    kit.Wait(10),
    kit.Capture("smooth_on"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.app.painter.mesh.count > 0 }, "the shapes went through the mesh"),
    kit.Click({24, 24}),
    kit.Wait(4),
    kit.Capture("smooth_off"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ui.UiProblems(&state.app.ctx) == {} }, "the frames had no problems"),
}
