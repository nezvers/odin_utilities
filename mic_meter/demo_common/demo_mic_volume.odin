#+private file
package demo_common

// The capture devices as buttons (the chosen one has a blue outline) and the peak volume of the one that listens as a bar.
// There is no simulated microphone: the demo has no checks, its script only clicks the first device so the headless test and
// DEMO_TEST exercise the device list and the switching on whatever hardware is there (no device: nothing to click, nothing breaks).

import mic ".."
import kit "../../demo_kit"

@(private="package")
demo_mic_volume: kit.Demo = {
    name = "mic volume",
    init = init,
    finit = finit,
    draw = draw,
    script = script,
}

mic_ctx: mic.MicContext
mic_ok: bool

init :: proc(ctx: ^kit.Context) {
    mic_ok = mic.Init(&mic_ctx)
}

finit :: proc(ctx: ^kit.Context) {
    if mic_ok { mic.Finit(&mic_ctx) }
}

draw :: proc(ctx: ^kit.Context) {
    rect: kit.Rect = {10, 10, 400, 25}
    if !mic_ok {
        kit.DrawText(ctx, "no microphone could be opened", rect.xy, 20, kit.RED)
        return
    }
    for i in 0 ..< mic_ctx.capture_count {
        if i == mic_ctx.current_idx {
            kit.DrawRect(ctx, {rect.x - 1, rect.y - 1, rect.z + 2, rect.w + 2}, kit.BLUE)
        }
        if kit.Button(ctx, rect, string(mic.GetDeviceName(&mic_ctx, i))) {
            mic.SetDevice(&mic_ctx, i)
        }
        rect.y += 30
    }
    kit.DrawRect(ctx, {rect.x, rect.y, rect.z * mic_ctx.peak, rect.w}, kit.GREEN)
    kit.DrawRectOutline(ctx, rect, 1, kit.GRAY)
}

script: []kit.Step = {
    kit.Wait(10),
    kit.Click({100, 22}),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !mic_ok || mic_ctx.peak >= 0 && mic_ctx.peak <= 1.0001 }, "the peak is a value from 0 to 1"),
}
