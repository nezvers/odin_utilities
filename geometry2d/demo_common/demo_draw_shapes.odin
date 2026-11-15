#+private file
package demo_common

import gm ".."
import kit "../../demo_kit"

@(private="package")
demo_draw_shapes: kit.Demo = {
    name = "shapes",
    init = init,
    draw = draw,
    script = script,
}

init :: proc(ctx: ^kit.Context) {
    ctx.background = kit.BLACK
}

draw :: proc(ctx: ^kit.Context) {
    // the shapes of the library are small numbers, the demo scales them to see them
    scale: f32 = 4
    draw_line(ctx, gm.LineNew({100, 100}, {200, 100}), scale, kit.WHITE)
    draw_circle(ctx, gm.CircleNew({50, 15}, 5), scale, kit.WHITE)
    draw_rect(ctx, gm.RectNew({70, 10}, {10, 10}), scale, kit.WHITE)
    draw_triangle(ctx, gm.TriangleNew({90, 10}, {105, 10}, {97, 20}), scale, kit.WHITE)
    draw_ray(ctx, gm.RayNew({115, 10}, {10, 10}), scale, kit.WHITE)
}

draw_line :: proc(ctx: ^kit.Context, line: gm.Line, scale: f32, color: kit.Color) {
    kit.DrawLine(ctx, line.xy * scale, line.zw * scale, 1, color)
}

draw_circle :: proc(ctx: ^kit.Context, circle: gm.Circle, scale: f32, color: kit.Color) {
    kit.DrawCircleOutline(ctx, circle.xy * scale, circle.z * scale, 1, color)
}

draw_rect :: proc(ctx: ^kit.Context, rect: gm.Rect, scale: f32, color: kit.Color) {
    kit.DrawRectOutline(ctx, rect * scale, 1, color)
}

draw_triangle :: proc(ctx: ^kit.Context, triangle: gm.Triangle, scale: f32, color: kit.Color) {
    kit.DrawLine(ctx, triangle[0] * scale, triangle[1] * scale, 1, color)
    kit.DrawLine(ctx, triangle[1] * scale, triangle[2] * scale, 1, color)
    kit.DrawLine(ctx, triangle[2] * scale, triangle[0] * scale, 1, color)
}

draw_ray :: proc(ctx: ^kit.Context, ray: gm.Ray, scale: f32, color: kit.Color) {
    kit.DrawLine(ctx, ray.xy * scale, (ray.xy + ray.zw) * scale, 1, color)
}

script: []kit.Step = {
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ctx.backend.stats.draw_calls >= 5 * 5 }, "the five shapes are drawn every frame"),
}
