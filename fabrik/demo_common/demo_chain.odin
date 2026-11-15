#+private file
package demo_common

import "core:math"
import fabrik ".."
import kit "../../demo_kit"

@(private="package")
demo_chain: kit.Demo = {
    name = "chain",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

POINT_COUNT :: 6
start_points: [POINT_COUNT]kit.Vec2 = {
    {100.0, 100.0},
    {120.0, 100.0},
    {135.0, 100.0},
    {180.0, 100.0},
    {225.0, 100.0},
    {250.0, 100.0},
}
point_list: [POINT_COUNT]kit.Vec2
length_buffer: [POINT_COUNT - 1]f32
total_length: f32

init :: proc(ctx: ^kit.Context) {
    ctx.background = kit.BLACK
    point_list = start_points
    total_length = fabrik.calculate_lengths(point_list[:], length_buffer[:])
}

update :: proc(ctx: ^kit.Context) {
    mouse: kit.Vec2 = ctx.input.mouse_position
    if kit.MouseDown(&ctx.input, .LEFT) {
        // reach for the mouse, the chain keeps its lengths
        fabrik.fabrik(point_list[:], length_buffer[:], mouse, 4, 0.01)
        return
    }
    if kit.MouseDown(&ctx.input, .RIGHT) {
        // pull the chain behind the mouse: the first point follows, the rest are pulled by their lengths
        fabrik.pull_back(point_list[:], length_buffer[:], mouse)
    }
}

draw :: proc(ctx: ^kit.Context) {
    line_count: int = len(point_list) - 1
    for i in 0 ..< line_count {
        percent: f32 = f32(i) / f32(line_count - 1)
        // white to red along the chain
        color: kit.Color = {255, u8(255 - 226 * percent), u8(255 - 218 * percent), 255}
        kit.DrawLine(ctx, point_list[i], point_list[i + 1], 1, color)
    }
    kit.DrawText(ctx, "left button: reach for the mouse    right button: pull the chain", {10, 10}, 18, kit.GRAY)
}

chain_length :: proc() -> f32 {
    sum: f32 = 0
    for i in 0 ..< len(point_list) - 1 {
        d: kit.Vec2 = point_list[i + 1] - point_list[i]
        sum += math.sqrt(d.x * d.x + d.y * d.y)
    }
    return sum
}

script: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(chain_length() - total_length) < 0.01 }, "starts at its full length"),
    kit.MoveTo({300, 400}),
    kit.MouseDownStep(.LEFT),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(chain_length() - total_length) < 0.5 }, "reaching keeps the lengths of the bones"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        // the first point is the root and stays, the chain is too short to reach (150 long, 360 away): the free end gets closer than it was
        d: kit.Vec2 = point_list[POINT_COUNT - 1] - kit.Vec2{300, 400}
        return d.x * d.x + d.y * d.y < 340 * 340
    }, "and the free end gets closer to the mouse"),
    kit.MouseUpStep(.LEFT),
    kit.MoveTo({500, 300}),
    kit.MouseDownStep(.RIGHT),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return abs(chain_length() - total_length) < 0.5 && point_list[0] == kit.Vec2{500, 300} }, "pulling puts the first point on the mouse and keeps the lengths"),
    kit.MouseUpStep(.RIGHT),
}
