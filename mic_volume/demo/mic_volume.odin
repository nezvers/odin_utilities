#+private file
package demo

import rl "vendor:raylib"
Vector2 :: rl.Vector2
Rectangle :: rl.Rectangle

import mic ".."

@(private="package")
state_mic_volume:State = {
    init,
    finit,
    update,
    draw,
}

mic_ctx:mic.MicContext

init :: proc() {
    _ = mic.Init(&mic_ctx)
}

finit :: proc() {
    mic.Finit(&mic_ctx)
}

update :: proc() {}

draw :: proc() {
    rect:Rectangle = {10, 10, 400, 25}
    for i:u32 = 0; i < mic_ctx.capture_count; i += 1 {
        if i == mic_ctx.current_idx {
            outline:Rectangle = {rect.x -1, rect.y -1, rect.width +2, rect.height +2}
            rl.DrawRectangleRec(outline, rl.BLUE)
        }

        name: cstring = mic.GetDeviceName(&mic_ctx, i)
        if rl.GuiButton(rect, name) {
            mic.SetDevice(&mic_ctx, i)
        }
        rect.y += 30
    }

    peak:Rectangle = {rect.x, rect.y, rect.width * mic_ctx.peak, rect.height}
    rl.DrawRectangleRec(peak, rl.LIME)
    rl.DrawRectangleLinesEx(rect, 1, rl.GRAY)
}