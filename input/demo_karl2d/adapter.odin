package demo_karl2d

// The demo_common adapter over input/karl2d: the real keyboard, mouse and gamepads of Karl2D.

import "../../karl2d"
import kit "../../demo_kit"
import input "../glue_karl2d"
import demo_common "../demo_common"

actions: [demo_common.ACTION_COUNT]input.InputAction = {
    {id = karl2d.Keyboard_Key.W, name = "Up"},
    {id = karl2d.Keyboard_Key.S, name = "Down"},
    {id = karl2d.Keyboard_Key.D, name = "Right"},
    {id = karl2d.Keyboard_Key.A, name = "Left"},
    {id = karl2d.Keyboard_Key.Space, name = "Jump"},
}

karl2d_adapter :: proc() -> demo_common.Adapter {
    return {
        init = proc(ctx: ^kit.Context) {},
        update = proc(ctx: ^kit.Context) { input.UpdateAxis() },        // to read analog inputs as pressed / released / held
        name = proc(slot: int) -> string { return actions[slot].name },
        pressed = proc(ctx: ^kit.Context, slot: int) -> bool { return input.WentDown(actions[slot].id) },
        released = proc(ctx: ^kit.Context, slot: int) -> bool { return input.WentUp(actions[slot].id) },
        held = proc(ctx: ^kit.Context, slot: int) -> bool { return input.IsHeld(actions[slot].id) },
        axis = proc(ctx: ^kit.Context, negative: int, positive: int) -> f32 {
            return input.GetValueAxis(actions[negative].id, actions[positive].id)
        },
        listen_rebind = proc(ctx: ^kit.Context, slot: int) -> bool {
            id, ok := input.ListenRebind()
            if ok { actions[slot].id = id }
            return ok
        },
    }
}
