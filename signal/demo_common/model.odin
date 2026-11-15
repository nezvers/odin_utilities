package demo_common

// The part of the demo that has nothing to do with a framework: a player who loses and gets health, and three things that listen.
// The demos only read keys, call these procs and draw the model.
//   health_changed -> hud (shows the bar), flash (red on a hit), log (DEFERRED: written when the frame is over)
//   died           -> the player is down
// The first hit also connects a one shot listener, it says "first blood" once.

import "core:fmt"
import signal ".."

HealthChange :: struct {
    old, new: f32,
}

LOG_LINES :: 8
LOG_WIDTH :: 64

Model :: struct {
    health: f32,
    health_changed: signal.Signal(HealthChange, 8, 16),
    died: signal.Signal(signal.Empty, 4, 4),

    // what the listeners wrote
    hud_target: f32,                    // what the hud listener was told, the bar follows it. No listener, no change on the bar
    hud_value: f32,
    flash: f32,
    is_down: bool,
    log: [LOG_LINES][LOG_WIDTH]u8,
    log_lengths: [LOG_LINES]int,
    log_count: int,                     // lines written in total, the newest are the last
}

HEALTH_MAX :: 100

model_init :: proc(model: ^Model) {
    model^ = {}
    model.health = HEALTH_MAX
    model.hud_target = HEALTH_MAX
    model.hud_value = HEALTH_MAX
    signal.SignalConnect(&model.health_changed, on_hud, model)
    signal.SignalConnect(&model.health_changed, on_flash, model)
    signal.SignalConnect(&model.health_changed, on_log, model, {.DEFERRED})
    signal.SignalConnect(&model.health_changed, on_first_blood, model, {.ONE_SHOT})
    signal.SignalConnect(&model.died, on_died, model)
}

model_set_health :: proc(model: ^Model, value: f32) {
    clamped: f32 = clamp(value, 0, HEALTH_MAX)
    if clamped == model.health { return }
    change: HealthChange = {old = model.health, new = clamped}
    model.health = clamped
    signal.SignalEmit(&model.health_changed, change)
    if clamped == 0 { signal.SignalEmit(&model.died, {}) }
}

model_damage :: proc(model: ^Model, amount: f32) {
    if model.is_down { return }
    model_set_health(model, model.health - amount)
}

model_heal :: proc(model: ^Model, amount: f32) {
    if model.is_down { return }
    model_set_health(model, model.health + amount)
}

model_revive :: proc(model: ^Model) {
    model.is_down = false
    model_set_health(model, HEALTH_MAX)
}

// Once per frame, after the input: the deferred calls are delivered now, like Godot does at idle
model_update :: proc(model: ^Model, delta_time: f32) {
    signal.SignalFlush(&model.health_changed)
    signal.SignalFlush(&model.died)
    model.hud_value += (model.hud_target - model.hud_value) * min(1, delta_time * 8)
    model.flash = max(0, model.flash - delta_time * 3)
}

// The listeners that can be switched on and off by the demo
Listener :: enum {
    HUD,
    FLASH,
    LOG,
}

model_is_listening :: proc(model: ^Model, which: Listener) -> bool {
    return signal.SignalIsConnected(&model.health_changed, listener_proc(which), model)
}

model_toggle_listener :: proc(model: ^Model, which: Listener) {
    callback: proc(payload: HealthChange, user: rawptr) = listener_proc(which)
    if signal.SignalIsConnected(&model.health_changed, callback, model) {
        signal.SignalDisconnectCallback(&model.health_changed, callback, model)
        return
    }
    flags: signal.ConnectFlags = {.DEFERRED} if which == .LOG else {}
    signal.SignalConnect(&model.health_changed, callback, model, flags)
}

model_toggle_blocked :: proc(model: ^Model) {
    signal.SignalSetBlocked(&model.health_changed, !signal.SignalIsBlocked(&model.health_changed))
}

model_is_blocked :: proc(model: ^Model) -> bool {
    return signal.SignalIsBlocked(&model.health_changed)
}

model_connection_count :: proc(model: ^Model) -> int {
    return signal.SignalConnectionCount(&model.health_changed)
}

// Line `index` of the visible log, 0 is the oldest of the last LOG_LINES
model_log_line :: proc(model: ^Model, index: int) -> string {
    first: int = max(0, model.log_count - LOG_LINES)
    line: int = first + index
    if line >= model.log_count { return "" }
    slot: int = line % LOG_LINES
    return string(model.log[slot][:model.log_lengths[slot]])
}

@(private)
listener_proc :: proc(which: Listener) -> proc(payload: HealthChange, user: rawptr) {
    switch which {
    case .HUD: return on_hud
    case .FLASH: return on_flash
    case .LOG: return on_log
    }
    return nil
}

@(private)
log_write :: proc(model: ^Model, format: string, args: ..any) {
    slot: int = model.log_count % LOG_LINES
    text: string = fmt.bprintf(model.log[slot][:], format, ..args)
    model.log_lengths[slot] = len(text)
    model.log_count += 1
}

@(private)
on_hud :: proc(change: HealthChange, user: rawptr) {
    (cast(^Model)user).hud_target = change.new
}

@(private)
on_flash :: proc(change: HealthChange, user: rawptr) {
    model: ^Model = cast(^Model)user
    if change.new < change.old { model.flash = 1 }
}

@(private)
on_log :: proc(change: HealthChange, user: rawptr) {
    log_write(cast(^Model)user, "health %.0f -> %.0f", change.old, change.new)
}

@(private)
on_first_blood :: proc(change: HealthChange, user: rawptr) {
    log_write(cast(^Model)user, "one shot: first change of health")
}

@(private)
on_died :: proc(payload: signal.Empty, user: rawptr) {
    model: ^Model = cast(^Model)user
    model.is_down = true
    log_write(model, "died: press R")
}
