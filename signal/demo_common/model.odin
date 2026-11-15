package demo_common

// The part of the demo that has nothing to do with a framework: a player who loses and gets health, and three things that listen.
// The demos only read keys, call these procs and draw the model.
//   health_changed -> hud (shows the bar), flash (red on a hit), log (DEFERRED: written when the frame is over)
//   died           -> the player is down
// The first hit also connects a one shot listener, it says "first blood" once.
// Every connection has a Key, so model_rebind can give them their procs again like after a hot reload.

import "core:fmt"
import signal ".."

HealthChange :: struct {
    old, new: f32,
}

LOG_LINES :: 8
LOG_WIDTH :: 64

Model :: struct {
    health: f32,
    // the bound value is a pointer to the model: the model is a global of the demo and lives longer than the signals
    health_changed: signal.Signal(HealthChange, 8, 16, size_of(^Model)),
    died: signal.Signal(signal.Empty, 4, 4, size_of(^Model)),

    // what the listeners wrote
    hud_target: f32,                    // what the hud listener was told, the bar follows it. No listener, no change on the bar
    hud_value: f32,
    flash: f32,
    is_down: bool,
    log: [LOG_LINES][LOG_WIDTH]u8,
    log_lengths: [LOG_LINES]int,
    log_count: int,                     // lines written in total, the newest are the last
    reloads: int,                       // how many times model_rebind ran
}

HEALTH_MAX :: 100

// Keys of the connections: what finds them again after a reload
KEY_HUD :: signal.Key(1)
KEY_FLASH :: signal.Key(2)
KEY_LOG :: signal.Key(3)
KEY_FIRST_BLOOD :: signal.Key(4)
KEY_DIED :: signal.Key(5)

model_init :: proc(model: ^Model) {
    model^ = {}
    model.health = HEALTH_MAX
    model.hud_target = HEALTH_MAX
    model.hud_value = HEALTH_MAX
    signal.SignalConnect(&model.health_changed, on_hud, model, key = KEY_HUD)
    signal.SignalConnect(&model.health_changed, on_flash, model, key = KEY_FLASH)
    signal.SignalConnect(&model.health_changed, on_log, model, {.DEFERRED}, key = KEY_LOG)
    signal.SignalConnect(&model.health_changed, on_first_blood, model, {.ONE_SHOT}, key = KEY_FIRST_BLOOD)
    signal.SignalConnect(&model.died, on_died, model, key = KEY_DIED)
}

// What a game does after a hot reload: the model and its signals are in the memory that was kept, the procs are the ones of the
// old code. Every connection says which proc it wants now. Nothing is created: the one shot that fired is not brought back and a
// connection the user switched off stays off.
model_rebind :: proc(model: ^Model) {
    signal.SignalRebindBegin(&model.health_changed)
    signal.SignalRebindBegin(&model.died)
    signal.SignalRebind(&model.health_changed, on_hud, model, key = KEY_HUD)
    signal.SignalRebind(&model.health_changed, on_flash, model, key = KEY_FLASH)
    signal.SignalRebind(&model.health_changed, on_log, model, {.DEFERRED}, key = KEY_LOG)
    signal.SignalRebind(&model.health_changed, on_first_blood, model, {.ONE_SHOT}, key = KEY_FIRST_BLOOD)
    signal.SignalRebind(&model.died, on_died, model, key = KEY_DIED)
    signal.SignalDisconnectStale(&model.health_changed)
    signal.SignalDisconnectStale(&model.died)
    model.reloads += 1
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

listener_key :: proc(which: Listener) -> signal.Key {
    switch which {
    case .HUD: return KEY_HUD
    case .FLASH: return KEY_FLASH
    case .LOG: return KEY_LOG
    }
    return 0
}

model_is_listening :: proc(model: ^Model, which: Listener) -> bool {
    return signal.SignalIsKeyConnected(&model.health_changed, listener_key(which))
}

model_toggle_listener :: proc(model: ^Model, which: Listener) {
    key: signal.Key = listener_key(which)
    if signal.SignalDisconnectKey(&model.health_changed, key) { return }
    switch which {
    case .HUD: signal.SignalConnect(&model.health_changed, on_hud, model, key = key)
    case .FLASH: signal.SignalConnect(&model.health_changed, on_flash, model, key = key)
    case .LOG: signal.SignalConnect(&model.health_changed, on_log, model, {.DEFERRED}, key = key)
    }
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
log_write :: proc(model: ^Model, format: string, args: ..any) {
    slot: int = model.log_count % LOG_LINES
    text: string = fmt.bprintf(model.log[slot][:], format, ..args)
    model.log_lengths[slot] = len(text)
    model.log_count += 1
}

@(private)
on_hud :: proc(change: HealthChange, model: ^Model) {
    model.hud_target = change.new
}

@(private)
on_flash :: proc(change: HealthChange, model: ^Model) {
    if change.new < change.old { model.flash = 1 }
}

@(private)
on_log :: proc(change: HealthChange, model: ^Model) {
    log_write(model, "health %.0f -> %.0f", change.old, change.new)
}

@(private)
on_first_blood :: proc(change: HealthChange, model: ^Model) {
    log_write(model, "one shot: first change of health")
}

@(private)
on_died :: proc(payload: signal.Empty, model: ^Model) {
    model.is_down = true
    log_write(model, "died: press R")
}
