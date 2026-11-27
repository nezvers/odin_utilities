#+private file
package demo_common

import sp ".."
import kit "../../demo_kit"

@(private="package")
demo_inertia_spring: kit.Demo = {
    name = "inertia spring",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

position: kit.Vec2
velocity: kit.Vec2

init :: proc(ctx: ^kit.Context) {
    ctx.background = kit.BLACK
    position = {}
    velocity = {}
}

update :: proc(ctx: ^kit.Context) {
    target: kit.Vec2 = ctx.input.mouse_position
    if kit.MousePressed(&ctx.input) && !ctx.ui_hover {
        position = target
    }
    damping: f32 = 10
    frequency: f32 = 1
    sp.InertiaSpring(&position.x, &velocity.x, target.x, frequency, damping, ctx.delta_time)
    sp.InertiaSpring(&position.y, &velocity.y, target.y, frequency, damping, ctx.delta_time)
}

draw :: proc(ctx: ^kit.Context) {
    kit.DrawCircle(ctx, position, 10, {255, 109, 194, 255})
    kit.DrawText(ctx, "the circle follows the mouse on an inertia spring, click puts it on the mouse", {10, 10}, 18, kit.GRAY)
}

distance_to :: proc(point: kit.Vec2) -> f32 {
    d: kit.Vec2 = point - position
    return d.x * d.x + d.y * d.y
}

script: []kit.Step = {
    kit.Wait(2),
    kit.Click({400, 300}),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return distance_to({400, 300}) < 1 }, "a click puts the circle on the mouse"),
    kit.MoveTo({800, 500}),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return position.x > 400 && distance_to({800, 500}) > 100 }, "it starts moving toward the new target, it does not jump"),
    kit.Wait(240),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return distance_to({800, 500}) < 2 * 2 }, "and settles on it"),
    kit.Wait(2),
    kit.Capture("spring_inertia_spring_end"),
    kit.Wait(1),
}
