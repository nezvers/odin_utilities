#+private file
package demo_common

import sp ".."
import kit "../../demo_kit"

@(private="package")
demo_spring_damper: kit.Demo = {
    name = "spring damper",
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
    HERTZ :: f32(0.4)
    DAMPING :: f32(1.5)
    offset: kit.Vec2 = position - target
    velocity = {
        sp.SpringDamper(HERTZ, DAMPING, offset.x, velocity.x, ctx.delta_time),
        sp.SpringDamper(HERTZ, DAMPING, offset.y, velocity.y, ctx.delta_time),
    }
    position += velocity
}

draw :: proc(ctx: ^kit.Context) {
    kit.DrawCircle(ctx, position, 10, {255, 109, 194, 255})
    kit.DrawText(ctx, "the circle follows the mouse on a spring damper (box2d style), click puts it on the mouse", {10, 10}, 18, kit.GRAY)
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
    kit.Wait(300),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return distance_to({800, 500}) < 30 * 30 }, "and gets to it"),
    kit.Wait(2),
    kit.Capture("spring_spring_damper_end"),
    kit.Wait(1),
}
