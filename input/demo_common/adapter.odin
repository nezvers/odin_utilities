package demo_common

// The input library is glue for one framework (input/raylib, input/karl2d): its inputs are the keys, buttons and axes of that framework.
// The demo calls it through this table of procs, an action is a slot number. demo_raylib and demo_karl2d fill the table with their glue,
// KitAdapter below fills it with the keys of the demo kit so the demo and its script also run headless.

import kit "../../demo_kit"

ACTION_COUNT :: 5

Adapter :: struct {
    init: proc(ctx: ^kit.Context),
    update: proc(ctx: ^kit.Context),
    name: proc(slot: int) -> string,
    pressed: proc(ctx: ^kit.Context, slot: int) -> bool,
    released: proc(ctx: ^kit.Context, slot: int) -> bool,
    held: proc(ctx: ^kit.Context, slot: int) -> bool,
    axis: proc(ctx: ^kit.Context, negative: int, positive: int) -> f32,
    // true when an input was pressed and let go while waiting: the slot has it now
    listen_rebind: proc(ctx: ^kit.Context, slot: int) -> bool,
}

// The adapter the demos use. Set before running them.
adapter: Adapter

// The demo of the rebinding, for a main that adds its own demos to the list
ActionDemo :: proc() -> kit.Demo {
    return demo_action
}

action_names: [ACTION_COUNT]string = {"Up", "Down", "Right", "Left", "Jump"}

// An adapter over the keys of the kit: W S D A and space at the start, any key can be rebound
KitAdapter :: proc() -> Adapter {
    return {
        init = proc(ctx: ^kit.Context) { kit_keys = {.W, .S, .D, .A, .SPACE} },
        update = proc(ctx: ^kit.Context) {},
        name = proc(slot: int) -> string { return action_names[slot] },
        pressed = proc(ctx: ^kit.Context, slot: int) -> bool { return kit.KeyPressed(&ctx.input, kit_keys[slot]) },
        released = proc(ctx: ^kit.Context, slot: int) -> bool { return kit.KeyReleased(&ctx.input, kit_keys[slot]) },
        held = proc(ctx: ^kit.Context, slot: int) -> bool { return kit.KeyDown(&ctx.input, kit_keys[slot]) },
        axis = proc(ctx: ^kit.Context, negative: int, positive: int) -> f32 {
            return f32(int(kit.KeyDown(&ctx.input, kit_keys[positive]))) - f32(int(kit.KeyDown(&ctx.input, kit_keys[negative])))
        },
        listen_rebind = proc(ctx: ^kit.Context, slot: int) -> bool {
            for key in kit.Key {
                if key != .None && key in ctx.input.keys_released {
                    kit_keys[slot] = key
                    return true
                }
            }
            return false
        },
    }
}

@(private)
kit_keys: [ACTION_COUNT]kit.Key
