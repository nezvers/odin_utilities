#+private file
package demo_common

// One demo = one file: a Demo value with its procs and a `script`, the input a person would give and what has to come out of it.
// State is globals of the file (it is a demo, not a library).

import "core:fmt"
import kit "../../demo_kit"
import example ".."

@(private="package")
demo_counter: kit.Demo = {
    name = "counter",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

counter: example.Counter

init :: proc(ctx: ^kit.Context) {
    example.CounterInit(&counter, 5)
}

update :: proc(ctx: ^kit.Context) {
    if kit.KeyPressed(&ctx.input, .SPACE) { example.CounterAdd(&counter, 1) }
    // ui_hover: the mouse is over the menu of the kit, a click is not for the demo
    if kit.MousePressed(&ctx.input) && !ctx.ui_hover { example.CounterAdd(&counter, 2) }
}

draw :: proc(ctx: ^kit.Context) {
    bar: kit.Rect = {100, 100, 400, 24}
    kit.DrawRect(ctx, bar, kit.LIGHT_GRAY)
    kit.DrawRect(ctx, {bar.x, bar.y, bar.z * f32(counter.value) / f32(counter.limit), bar.w}, kit.GREEN)
    kit.DrawText(ctx, fmt.tprintf("%d / %d   space: +1   click: +2", counter.value, counter.limit), {100, 60}, 20, kit.BLACK)
}

script: []kit.Step = {
    kit.Wait(2),
    kit.Tap(.SPACE),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return counter.value == 1 }, "space adds one"),
    kit.Click({300, 300}),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return counter.value == 3 }, "a click adds two"),
    kit.Hold(.SPACE, 3),
    kit.Tap(.SPACE),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return example.CounterIsFull(&counter) }, "it stops at the limit"),
}
