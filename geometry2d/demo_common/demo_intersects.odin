#+private file
package demo_common

import gm ".."
import kit "../../demo_kit"

@(private="package")
demo_intersects: kit.Demo = {
    name = "intersects",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

pos_a: kit.Vec2
pos_b: kit.Vec2
point_count: int

init :: proc(ctx: ^kit.Context) {
    pos_a = {100, 100}
    pos_b = {400, 300}
}

update :: proc(ctx: ^kit.Context) {
    if ctx.ui_hover { return }
    if kit.MousePressed(&ctx.input, .LEFT) { pos_a = ctx.input.mouse_position }
    if kit.MousePressed(&ctx.input, .RIGHT) { pos_b = ctx.input.mouse_position }
}

draw :: proc(ctx: ^kit.Context) {
    mouse: kit.Vec2 = ctx.input.mouse_position
    size: f32 = 100
    line: gm.Line
    line.xy = pos_a
    line.zw = mouse
    circle: gm.Circle
    circle.xy = pos_b
    circle.z = size
    points, count := gm.IntersectsLineCircle(line, circle)
    point_count = count

    kit.DrawLine(ctx, line.xy, mouse, 1, kit.DARK_GRAY)
    kit.DrawCircleOutline(ctx, circle.xy, size, 1, kit.LIGHT_GRAY)
    for i in 0 ..< count {
        kit.DrawCircle(ctx, points[i], 5, kit.RED)
    }
    kit.DrawText(ctx, "a line from the first point to the mouse and a circle: red points are where they meet.  left click: move the line start, right click: the circle", {10, 10}, 16, kit.DARK_GRAY)
}

script: []kit.Step = {
    // the line (100,100) -> (700,500) goes through the center of the circle at (400,300)
    kit.MoveTo({700, 500}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return point_count == 2 }, "a line through a circle meets it twice"),
    kit.MoveTo({100, 600}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return point_count == 0 }, "a line that goes away from it does not meet it"),
    kit.Wait(2),
    kit.Capture("geometry2d_intersects_end"),
    kit.Wait(1),
}
