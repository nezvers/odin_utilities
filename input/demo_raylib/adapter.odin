package demo_raylib

// The demo_common adapter over input/raylib: the real keyboard, mouse and gamepads of raylib. Simulated input of the kit does not reach it,
// raylib reads the devices itself, so this demo has no script.

import rl "vendor:raylib"
import kit "../../demo_kit"
import input "../glue_raylib"
import demo_common "../demo_common"

actions: [demo_common.ACTION_COUNT]input.InputAction = {
    {id = rl.KeyboardKey.W, name = "Up"},
    {id = rl.KeyboardKey.S, name = "Down"},
    {id = rl.KeyboardKey.D, name = "Right"},
    {id = rl.KeyboardKey.A, name = "Left"},
    {id = rl.KeyboardKey.SPACE, name = "Jump"},
}

raylib_adapter :: proc() -> demo_common.Adapter {
    return {
        init = proc(ctx: ^kit.Context) {},
        update = proc(ctx: ^kit.Context) { input.UpdateAxis() },        // to read analog inputs as pressed / released / held
        name = proc(slot: int) -> string { return string(actions[slot].name) },
        pressed = proc(ctx: ^kit.Context, slot: int) -> bool { return input.IsPressed(actions[slot].id) },
        released = proc(ctx: ^kit.Context, slot: int) -> bool { return input.IsReleased(actions[slot].id) },
        held = proc(ctx: ^kit.Context, slot: int) -> bool { return input.IsDown(actions[slot].id) },
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

