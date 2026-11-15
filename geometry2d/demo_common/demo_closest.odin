#+private file
package demo_common

import gm ".."
import kit "../../demo_kit"

@(private="package")
demo_closest: kit.Demo = {
    name = "closest",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

pos_a: kit.Vec2
pos_b: kit.Vec2
pos_c: kit.Vec2
last_point: kit.Vec2

init :: proc(ctx: ^kit.Context) {
    pos_a = {100, 100}
    pos_b = {400, 100}
    pos_c = {400, 400}
}

update :: proc(ctx: ^kit.Context) {
    if ctx.ui_hover { return }
    if kit.MousePressed(&ctx.input, .LEFT) { pos_a = ctx.input.mouse_position }
    if kit.MousePressed(&ctx.input, .RIGHT) { pos_b = ctx.input.mouse_position }
}

draw :: proc(ctx: ^kit.Context) {
    mouse: kit.Vec2 = ctx.input.mouse_position
    shape_a: gm.Line = {pos_a.x, pos_a.y, mouse.x, mouse.y}
    shape_b: gm.Line = {pos_b.x, pos_b.y, pos_c.x, pos_c.y}
    kit.DrawLine(ctx, shape_a.xy, shape_a.zw, 1, kit.DARK_GRAY)
    kit.DrawLine(ctx, shape_b.xy, shape_b.zw, 1, kit.DARK_GRAY)
    last_point = gm.ClosestLineLine(shape_a, shape_b)
    kit.DrawCircle(ctx, last_point, 5, kit.RED)
    kit.DrawText(ctx, "the red point is the closest point of the two lines.  left click: move the start of the first, right click: the start of the second", {10, 10}, 16, kit.DARK_GRAY)
}

script: []kit.Step = {
    kit.MoveTo({700, 250}),
    kit.Wait(2),
    // the first line (100,100) -> (700,250) crosses the second (x = 400, y 100..400) at (400, 175)
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(last_point.x - 400) < 1 && abs(last_point.y - 175) < 1 }, "crossing lines: the closest point is the crossing"),
}
