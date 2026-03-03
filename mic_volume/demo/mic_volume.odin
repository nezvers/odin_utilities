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
    mic_ctx, _ = mic.Init()
}

finit :: proc() {
    // mic.Finit(&mic_ctx)
}

update :: proc() {}

draw :: proc() {
    // rect:Rectangle = {10, 10, 100, 25}
    // for i:u32 = 0; i < mic_ctx.capture_count; i += 1 {
    //     // name: cstring = mic.GetDeviceName(&mic_ctx, i)
    //     if rl.GuiButton(rect, "") {

    //     }
    //     rect.y += 30
    // }
}