#+private file
package demo_common

// Easing comparison. Each row is a looping Tween owned by the demo, no pool

import tw ".."
import "core:math/ease"
import kit "../../demo_kit"

@(private="package")
demo_ease: kit.Demo = {
    name = "ease",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

EASE_COUNT :: 8
ease_list: [EASE_COUNT]ease.Ease = {
    .Linear,
    .Quadratic_In_Out,
    .Cubic_Out,
    .Sine_In_Out,
    .Exponential_Out,
    .Elastic_Out,
    .Back_In_Out,
    .Bounce_Out,
}
ease_names: [EASE_COUNT]string = {
    "Linear",
    "Quadratic_In_Out",
    "Cubic_Out",
    "Sine_In_Out",
    "Exponential_Out",
    "Elastic_Out",
    "Back_In_Out",
    "Bounce_Out",
}
ease_x: [EASE_COUNT]f32
ease_tweens: [EASE_COUNT]tw.Tween

init :: proc(ctx: ^kit.Context) {
    for i in 0 ..< EASE_COUNT {
        ease_x[i] = 250
        ease_tweens[i] = tw.TweenMake()
        tw.TweenProperty(&ease_tweens[i], &ease_x[i], 900, 1.5, ease_list[i])
        tw.TweenInterval(&ease_tweens[i], 0.3)
        tw.TweenProperty(&ease_tweens[i], &ease_x[i], 250, 0.6, .Quadratic_In_Out)
        tw.TweenSetLoops(&ease_tweens[i], 0)
        tw.TweenPlay(&ease_tweens[i])
    }
}

update :: proc(ctx: ^kit.Context) {
    for i in 0 ..< EASE_COUNT {
        tw.TweenUpdate(&ease_tweens[i], ctx.delta_time)
    }
}

draw :: proc(ctx: ^kit.Context) {
    for i in 0 ..< EASE_COUNT {
        y: f32 = 80 + f32(i) * 50
        kit.DrawText(ctx, ease_names[i], {20, y}, 20, kit.DARK_GRAY)
        kit.DrawLine(ctx, {250, y + 10}, {900, y + 10}, 1, kit.LIGHT_GRAY)
        kit.DrawCircle(ctx, {ease_x[i], y + 10}, 10, {102, 191, 255, 255})
    }
    kit.DrawText(ctx, "tween: chained steps (ease, interval, return) with infinite loops", {10, 10}, 20, kit.BLACK)
}

script: []kit.Step = {
    kit.Wait(30),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ease_x[0] > 250 && ease_x[0] < 900 }, "the circles move along their rows"),
    kit.Wait(60),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ease_x[0] >= 899 }, "the first step ends at the far point"),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ease_x[0] >= 899 }, "then the interval holds it"),
    kit.Wait(240),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return ease_x[0] < 899 }, "and it loops: infinite loops keep going"),
    kit.Wait(2),
    kit.Capture("tween_ease_end"),
    kit.Wait(1),
}
