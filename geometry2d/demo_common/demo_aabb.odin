#+private file
package demo_common

import gm ".."
import kit "../../demo_kit"

@(private="package")
demo_aabb: kit.Demo = {
    name = "aabb",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

pos_a: kit.Vec2
pos_b: kit.Vec2
last_hit: bool
last_stop: kit.Vec2

init :: proc(ctx: ^kit.Context) {
    pos_a = {100, 100}
    pos_b = {400, 100}
}

update :: proc(ctx: ^kit.Context) {
    if ctx.ui_hover { return }
    if kit.MousePressed(&ctx.input, .LEFT) { pos_a = ctx.input.mouse_position }
    if kit.MousePressed(&ctx.input, .RIGHT) { pos_b = ctx.input.mouse_position }
}

draw :: proc(ctx: ^kit.Context) {
    mouse: kit.Vec2 = ctx.input.mouse_position
    size: kit.Vec2 = {100, 100}
    shape_a: gm.Rect = {pos_a.x, pos_a.y, size.x, size.y}
    shape_b: gm.Rect = {pos_b.x, pos_b.y, size.x, size.y}
    offset: kit.Vec2 = size * 0.5
    center_a: kit.Vec2 = pos_a + offset
    vector: kit.Vec2 = mouse - center_a
    result := gm.AABBRectRect(shape_a, shape_b, vector)
    last_hit = result.hit
    last_stop = result.point

    kit.DrawLine(ctx, center_a, mouse, 1, kit.DARK_GRAY)
    kit.DrawRectOutline(ctx, shape_a, 1, kit.LIGHT_GRAY)
    kit.DrawRectOutline(ctx, shape_b, 1, kit.LIGHT_GRAY)
    if result.hit {
        shape_a.xy = result.point - offset
        kit.DrawRectOutline(ctx, shape_a, 1, kit.RED)
    } else {
        shape_a.xy = mouse - offset
        kit.DrawRectOutline(ctx, shape_a, 1, kit.GRAY)
    }
    kit.DrawText(ctx, "a rectangle sweeps from the left one toward the mouse and stops at the other.  left click: move the first, right click: move the second", {10, 10}, 16, kit.DARK_GRAY)
}

script: []kit.Step = {
    kit.MoveTo({700, 150}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return last_hit }, "the sweep toward the right hits the second rectangle"),
    kit.MoveTo({100, 600}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !last_hit }, "a sweep down misses"),
    kit.Click({300, 300}, .RIGHT),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return pos_b == kit.Vec2{300, 300} }, "right click moves the second rectangle"),
}
