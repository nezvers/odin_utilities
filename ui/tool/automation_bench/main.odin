package main

// How many nanoseconds a sample of the automation block renderer costs, per shape: `odin run ui/tool/automation_bench -o:speed`. Blocks of 512 samples, a segment spans many blocks,
// best of five runs of 4000 blocks. The audio thread has 5 to 10 ms for a block, so the number to watch is how many lanes of automation fit.

import "core:fmt"
import "core:time"
import ui "../.."

BLOCK :: 512
BLOCKS :: 4000

main :: proc() {
    shapes := [?]ui.CurveShape{.HOLD, .LINEAR, .EXP, .SMOOTH, .CURVE, .S_CURVE, .HERMITE, .TRIANGLE, .WAVE, .STAIRS, .PULSE}
    out: [BLOCK]f32
    fmt.println("automation renderer, ns a sample (512 sample blocks)")
    for shape in shapes {
        coefficient: f32 = ui.CurveCoefficient(shape, 0.5)
        segments: [1]ui.AutomationSegment = {{start = 0, end = 1e9, inverse_length = 1e-9, value = 0, change = 1, coefficient = coefficient, coefficient2 = 1, shape = shape}}
        plan: ui.AutomationPlan = {segments = segments[:], first_value = 0, last_value = 1, valid = true}
        best: f64 = 1e30
        sink: f32
        for _ in 0 ..< 5 {
            cursor: ui.AutomationCursor
            start: time.Tick = time.tick_now()
            for block in 0 ..< BLOCKS {
                ui.AutomationRender(&plan, &cursor, f64(block * BLOCK) * 1000, 1000, out[:])
                sink += out[BLOCK - 1]
            }
            best = min(best, f64(time.duration_nanoseconds(time.tick_since(start))))
        }
        fmt.printf("  %-10v %7.3f\n", shape, best / f64(BLOCKS * BLOCK))
        if sink == 12345.678 { fmt.println(sink) }
    }
}
