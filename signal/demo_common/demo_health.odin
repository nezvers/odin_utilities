#+private file
package demo_common

import "core:fmt"
import kit "../../demo_kit"

@(private="package")
demo_health: kit.Demo = {
    name = "health",
    init = init,
    update = update,
    draw = draw,
    script = script,
}

model: Model

init :: proc(ctx: ^kit.Context) {
    model_init(&model)
}

update :: proc(ctx: ^kit.Context) {
    input: ^kit.Input = &ctx.input
    if kit.KeyPressed(input, .SPACE) { model_damage(&model, 15) }
    if kit.KeyPressed(input, .H) { model_heal(&model, 10) }
    if kit.KeyPressed(input, .R) { model_revive(&model) }
    if kit.KeyPressed(input, .N1) { model_toggle_listener(&model, .HUD) }
    if kit.KeyPressed(input, .N2) { model_toggle_listener(&model, .FLASH) }
    if kit.KeyPressed(input, .N3) { model_toggle_listener(&model, .LOG) }
    if kit.KeyPressed(input, .B) { model_toggle_blocked(&model) }
    if kit.KeyPressed(input, .F) { model_rebind(&model) }
    model_update(&model, ctx.delta_time)
}

draw :: proc(ctx: ^kit.Context) {
    // health bar, the red flash is a listener too
    bar: kit.Rect = {ctx.screen.x * 0.5 - 250, 120, 500, 40}
    kit.DrawRect(ctx, bar, kit.LIGHT_GRAY)
    kit.DrawRect(ctx, {bar.x, bar.y, bar.z * model.hud_value / HEALTH_MAX, bar.w}, kit.DARK_GREEN)
    flash: kit.Color = kit.RED
    flash.a = u8(model.flash * 0.7 * 255)
    kit.DrawRect(ctx, bar, flash)
    kit.DrawRectOutline(ctx, bar, 2, kit.DARK_GRAY)
    kit.DrawText(ctx, fmt.tprintf("health %.0f%s", model.health, "   DOWN" if model.is_down else ""), {bar.x, bar.y - 30}, 24, kit.BLACK)

    kit.DrawText(ctx, "Space: damage    H: heal    R: revive    B: block the signal    F: rebind like after a hot reload", {20, 20}, 20, kit.DARK_GRAY)
    names: [3]string = {"1  hud (the bar follows)", "2  flash (red on damage)", "3  log (deferred)"}
    for name, i in names {
        on: bool = model_is_listening(&model, Listener(i))
        kit.DrawText(ctx, fmt.tprintf("%s  %s", name, "connected" if on else "disconnected"), {20, 60 + f32(i) * 26}, 20, kit.DARK_GREEN if on else kit.GRAY)
    }
    kit.DrawText(ctx, fmt.tprintf("connections: %d   signal blocked: %v   rebinds: %d", model_connection_count(&model), model_is_blocked(&model), model.reloads), {20, 150}, 20, kit.DARK_BLUE)

    kit.DrawText(ctx, "log (deferred lines come after the frame, the one shot line comes first)", {20, 220}, 20, kit.DARK_GRAY)
    for i in 0 ..< LOG_LINES {
        kit.DrawText(ctx, model_log_line(&model, i), {40, 250 + f32(i) * 24}, 20, kit.BLACK)
    }
}

// What a person does with this demo, and what has to come out of it
script: []kit.Step = {
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return model.health == HEALTH_MAX && model_connection_count(&model) == 4 }, "starts full with 4 listeners"),
    kit.Tap(.SPACE),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return model.health == 85 && model.flash > 0 && model.hud_target == 85 }, "damage reaches the hud and the flash listener"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return model_connection_count(&model) == 3 }, "the one shot listener is gone after the first change"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return model.log_count == 2 }, "the one shot line and the deferred log line are written"),
    kit.Tap(.N1),
    kit.Tap(.SPACE),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return model.health == 70 && model.hud_target == 85 }, "without the hud listener the bar is not told"),
    kit.Tap(.B),
    kit.Tap(.SPACE),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return model.health == 55 && model.log_count == 3 }, "a blocked signal tells nobody"),
    kit.Tap(.B),
    kit.Tap(.F),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return model.reloads == 1 && model_connection_count(&model) == 2 }, "a rebind keeps what was connected, and does not bring back the one shot"),
    kit.Hold(.SPACE, 1),
    kit.Tap(.SPACE),
    kit.Tap(.SPACE),
    kit.Tap(.SPACE),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return model.is_down && model.health == 0 }, "the died signal puts the player down"),
    kit.Tap(.R),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return !model.is_down && model.health == HEALTH_MAX }, "revive"),
    kit.Wait(2),
    kit.Capture("signal_health_end"),
    kit.Wait(1),
}
