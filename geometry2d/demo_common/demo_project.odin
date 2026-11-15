#+private file
package demo_common

import gm ".."
import kit "../../demo_kit"

@(private="package")
demo_project: kit.Demo = {
    name = "project",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

pos_a: kit.Vec2
pos_b: kit.Vec2
last_hit: bool

init :: proc(ctx: ^kit.Context) {
    pos_a = {100, 200}
    pos_b = {500, 300}
}

update :: proc(ctx: ^kit.Context) {
    if ctx.ui_hover { return }
    if kit.MousePressed(&ctx.input, .LEFT) { pos_a = ctx.input.mouse_position }
    if kit.MousePressed(&ctx.input, .RIGHT) { pos_b = ctx.input.mouse_position }
}

draw :: proc(ctx: ^kit.Context) {
    mouse: kit.Vec2 = ctx.input.mouse_position
    shape_a: gm.Circle = {pos_a.x, pos_a.y, 100}
    shape_b: gm.Circle = {pos_b.x, pos_b.y, 100}
    vector: kit.Vec2 = mouse - pos_a
    ray: gm.Ray = {pos_a.x, pos_a.y, vector.x, vector.y}
    result := gm.ProjectCircleCircle(shape_a, shape_b, ray)
    last_hit = result.hit

    kit.DrawLine(ctx, shape_a.xy, mouse, 1, kit.DARK_GRAY)
    kit.DrawCircleOutline(ctx, shape_a.xy, shape_a.z, 1, kit.LIGHT_GRAY)
    kit.DrawCircleOutline(ctx, shape_b.xy, shape_b.z, 1, kit.LIGHT_GRAY)
    if result.hit {
        kit.DrawCircleOutline(ctx, result.point, shape_a.z, 1, kit.RED)
    }
    kit.DrawText(ctx, "the first circle moves toward the mouse and stops where it touches the second (red).  left click: move the first, right click: the second", {10, 10}, 16, kit.DARK_GRAY)
}

script: []kit.Step = {
    kit.MoveTo({700, 300}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return last_hit }, "moving toward the second circle hits it"),
    kit.MoveTo({100, 650}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !last_hit }, "moving away from it does not"),
}
