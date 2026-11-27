#+private file
package demo_common

// Input rebinding: five actions, the squares show when each was pressed (P), is held (D) and was released (R), the arrows of the
// player are read as an axis. Click Rebind and press any key (or a gamepad button or axis) to give the action a new input.
// The input library is glue for a framework (input/raylib, input/karl2d): the demo reaches it through an Adapter that each framework fills.

import "core:fmt"
import kit "../../demo_kit"

@(private="package")
demo_action: kit.Demo = {
    name = "actions",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

ACTION_UP :: 0
ACTION_DOWN :: 1
ACTION_RIGHT :: 2
ACTION_LEFT :: 3
ACTION_JUMP :: 4

Visual :: struct {
    pressed_timer: f32,
    hold_timer: f32,
    release_timer: f32,
}
visuals: [ACTION_COUNT]Visual
selected_rebind: int = -1
player_rect: kit.Rect = {0, 0, 32, 32}
rebinds: int                // how many actions got a new input

init :: proc(ctx: ^kit.Context) {
    assert(adapter.update != nil, "set demo_common.adapter before running the demos")
    adapter.init(ctx)
    visuals = {}
    selected_rebind = -1
    player_rect.x = 500
    player_rect.y = 400
    rebinds = 0
}

update :: proc(ctx: ^kit.Context) {
    // To update pressed / released / down for analog inputs
    adapter.update(ctx)
    update_player(ctx)
    for slot in 0 ..< ACTION_COUNT {
        update_timers(ctx, slot)
    }
    if selected_rebind == -1 { return }
    // TODO: add validation for the new input
    if !adapter.listen_rebind(ctx, selected_rebind) { return }
    selected_rebind = -1
    rebinds += 1
}

REBIND_X :: 275
ROW_HEIGHT :: 25

draw :: proc(ctx: ^kit.Context) {
    kit.DrawRect(ctx, player_rect, kit.GREEN)
    kit.DrawText(ctx, "Name", {10, 10}, 20, kit.BLACK)
    kit.DrawText(ctx, "P", {200, 10}, 20, kit.BLACK)
    kit.DrawText(ctx, "D", {225, 10}, 20, kit.BLACK)
    kit.DrawText(ctx, "R", {250, 10}, 20, kit.BLACK)
    if selected_rebind != -1 {
        kit.DrawText(ctx, fmt.tprintf("%s: press an input", adapter.name(selected_rebind)), {400, 10}, 20, kit.BLACK)
    }
    for slot in 0 ..< ACTION_COUNT {
        y: f32 = 35 + ROW_HEIGHT * f32(slot)
        kit.DrawText(ctx, adapter.name(slot), {10, y}, 20, kit.BLACK)
        kit.DrawRect(ctx, {200, y, 20, 20}, fade(visuals[slot].pressed_timer))
        kit.DrawRect(ctx, {225, y, 20, 20}, fade(visuals[slot].hold_timer))
        kit.DrawRect(ctx, {250, y, 20, 20}, fade(visuals[slot].release_timer))
        // SELECT
        if kit.Button(ctx, {REBIND_X, y, 70, 20}, "Waiting" if selected_rebind == slot else "Rebind") {
            if selected_rebind == -1 { selected_rebind = slot }
        }
    }
    kit.DrawText(ctx, "WASD move the square, space is jump (only shown)", {10, 180}, 18, kit.DARK_GRAY)
}

fade :: proc(timer: f32) -> kit.Color {
    return {0, 228, 48, u8(255 * clamp(timer, 0, 1))}
}

update_timers :: proc(ctx: ^kit.Context, slot: int) {
    visual: ^Visual = &visuals[slot]
    visual.pressed_timer = max(visual.pressed_timer - ctx.delta_time * 4, 0)
    visual.release_timer = max(visual.release_timer - ctx.delta_time * 4, 0)
    visual.hold_timer = max(visual.hold_timer - ctx.delta_time * 10, 0)
    if adapter.pressed(ctx, slot) { visual.pressed_timer = 1 }
    if adapter.released(ctx, slot) { visual.release_timer = 1 }
    if adapter.held(ctx, slot) { visual.hold_timer = 1 }
}

update_player :: proc(ctx: ^kit.Context) {
    x: f32 = adapter.axis(ctx, ACTION_LEFT, ACTION_RIGHT)
    y: f32 = adapter.axis(ctx, ACTION_UP, ACTION_DOWN)
    SPEED :: 200
    player_rect.x += x * SPEED * ctx.delta_time
    player_rect.y += y * SPEED * ctx.delta_time
}

script: []kit.Step = {
    kit.Wait(2),
    kit.Hold(.D, 30),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player_rect.x > 540 }, "D moves the square to the right (action Right)"),
    kit.Tap(.SPACE),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return visuals[ACTION_JUMP].pressed_timer > 0.5 }, "pressing a key lights the pressed square of its action"),
    kit.Wait(40),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return visuals[ACTION_JUMP].pressed_timer == 0 }, "and it fades out"),
    // rebind Right to the key L: click Rebind of the third row, press L
    kit.Click({REBIND_X + 30, 35 + ROW_HEIGHT * ACTION_RIGHT + 10}),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return selected_rebind == ACTION_RIGHT }, "Rebind waits for an input"),
    kit.Tap(.L),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return selected_rebind == -1 && rebinds == 1 }, "the first input released is the new binding"),
    kit.Tap(.D),
    kit.Wait(30),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player_rect.x < 700 }, "D does nothing for Right anymore"),
    kit.Hold(.L, 120),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return player_rect.x > 700 }, "L moves the square to the right now"),
    kit.Wait(2),
    kit.Capture("input_action_end"),
    kit.Wait(1),
}
