// Godot like property tweening without allocations.
// Tween holds a fixed array of steps, so it can live in the user's own struct or in a TweenSystem pool.
package tween

import "core:math/ease"
import hm "core:container/handle_map"

Handle :: hm.Handle32
HandleNone :Handle: {}

// Maximum amount of steps in single Tween. Change with -define:TWEEN_STEPS_MAX=16
TWEEN_STEPS_MAX :: #config(TWEEN_STEPS_MAX, 8)

StepKind :: enum {
    PROPERTY,   // interpolate value behind a pointer
    INTERVAL,   // just wait
    CALLBACK,   // call once
    METHOD,     // call every update with eased 0..1
}

// Equivalent of Godot Tweener
Step :: struct {
    kind: StepKind,
    parallel: bool,     // Starts together with the previous step, otherwise starts after previous steps finish
    relative: bool,     // PROPERTY: `to` is added to the starting value
    has_from: bool,     // PROPERTY: use `from` instead of reading the current value when step starts
    started: bool,      // runtime
    done: bool,         // runtime
    delay: f32,
    duration: f32,
    easing: ease.Ease,
    value_kind: ValueKind,
    ptr: rawptr,        // PROPERTY: target. Has to outlive the tween
    from: Values,
    to: Values,
    callback: proc(tween: ^Tween),              // CALLBACK
    method: proc(tween: ^Tween, t: f32),        // METHOD
}

TweenState :: enum {
    STOPPED,
    PLAYING,
    PAUSED,
    FINISHED,
}

Tween :: struct {
    handle: Handle,         // Set when created by a TweenSystem
    steps: [TWEEN_STEPS_MAX]Step,
    count: int,
    group: int,             // runtime: index of the first step in the running group
    t: f32,                 // runtime: time inside of the running group
    loops: int,             // How many times to play, ignored when `infinite`
    infinite: bool,
    loop_index: int,        // runtime
    speed_scale: f32,
    state: TweenState,
    keep: bool,             // TweenSystem removes finished tweens, unless this is set
    next_parallel: bool,
    user_data: rawptr,      // Generic way to carry user facing data
    on_finish: proc(tween: ^Tween),
    on_loop: proc(tween: ^Tween),
}

// Create tween with default values. Required for tweens that are not created by a TweenSystem
TweenMake :: proc() -> Tween {
    return {
        loops = 1,
        speed_scale = 1,
    }
}

// Removes all steps and resets state, keeps handle and user_data
TweenClear :: proc(tween: ^Tween) {
    tween.steps = {}
    tween.count = 0
    tween.next_parallel = false
    TweenReset(tween)
    tween.state = .STOPPED
}

// 0 = infinite, like in Godot
TweenSetLoops :: proc(tween: ^Tween, loops: int) {
    tween.loops = loops
    tween.infinite = loops <= 0
}

// Next added step will start together with the previous one
TweenParallel :: proc(tween: ^Tween) {
    tween.next_parallel = true
}

// Interpolate property from current (or `from`) value to `to`.
// Steps are sequential, use `parallel` to run it together with the previous step.
// Returns nil when the tween has no space for more steps
TweenProperty :: proc(
    tween: ^Tween,
    ptr: ^$T,
    to: T,
    duration: f32,
    easing: ease.Ease = .Linear,
    delay: f32 = 0,
    parallel: bool = false,
    relative: bool = false,
    from: Maybe(T) = nil,
) -> ^Step {
    step: Step = {
        kind = .PROPERTY,
        parallel = parallel,
        relative = relative,
        delay = delay,
        duration = duration,
        easing = easing,
        value_kind = ValueKindOf(T),
        ptr = ptr,
        to = ValueToStorage(to),
    }
    if from_value, ok := from.?; ok {
        step.has_from = true
        step.from = ValueToStorage(from_value)
    }
    return TweenAddStep(tween, step)
}

TweenInterval :: proc(tween: ^Tween, duration: f32, parallel: bool = false) -> ^Step {
    return TweenAddStep(tween, {kind = .INTERVAL, parallel = parallel, duration = duration})
}

// Called once after delay
TweenCallback :: proc(tween: ^Tween, callback: proc(tween: ^Tween), delay: f32 = 0, parallel: bool = false) -> ^Step {
    return TweenAddStep(tween, {kind = .CALLBACK, parallel = parallel, delay = delay, callback = callback})
}

// Called every update with eased 0..1, last call is always 1
TweenMethod :: proc(
    tween: ^Tween,
    method: proc(tween: ^Tween, t: f32),
    duration: f32,
    easing: ease.Ease = .Linear,
    delay: f32 = 0,
    parallel: bool = false,
) -> ^Step {
    return TweenAddStep(tween, {kind = .METHOD, parallel = parallel, delay = delay, duration = duration, easing = easing, method = method})
}

TweenAddStep :: proc(tween: ^Tween, step: Step) -> ^Step {
    if tween.count >= len(tween.steps) {
        return nil
    }
    result: ^Step = &tween.steps[tween.count]
    result^ = step
    if tween.next_parallel {
        result.parallel = true
        tween.next_parallel = false
    }
    if tween.count == 0 {
        // First step always starts the first group
        result.parallel = false
    }
    tween.count += 1
    return result
}

// Start or restart from the beginning when finished
TweenPlay :: proc(tween: ^Tween) {
    if tween.state == .FINISHED {
        TweenReset(tween)
    }
    tween.state = .PLAYING
}

TweenPause :: proc(tween: ^Tween) {
    if tween.state == .PLAYING {
        tween.state = .PAUSED
    }
}

// Stops and rewinds. Property values are left as they are
TweenStop :: proc(tween: ^Tween) {
    TweenReset(tween)
    tween.state = .STOPPED
}

// Rewind to the first step
TweenReset :: proc(tween: ^Tween) {
    tween.group = 0
    tween.t = 0
    tween.loop_index = 0
    for i: int = 0; i < tween.count; i += 1 {
        tween.steps[i].started = false
        tween.steps[i].done = false
    }
}

TweenIsRunning :: proc(tween: ^Tween) -> bool {
    return tween.state == .PLAYING
}

// Advance tween, returns true when tween finished during this update.
// Time left after finishing a step carries over to the next one.
TweenUpdate :: proc(tween: ^Tween, delta_time: f32) -> (finished: bool) {
    if tween.state != .PLAYING {
        return
    }
    if tween.count == 0 {
        tween.state = .FINISHED
        if tween.on_finish != nil { tween.on_finish(tween) }
        return true
    }

    tween.t += delta_time * tween.speed_scale
    for {
        start: int = tween.group
        end: int = GroupEnd(tween, start)
        length: f32 = GroupLength(tween, start, end)
        GroupApply(tween, start, end, min(tween.t, length))
        if tween.t < length {
            return
        }
        // Tween could be changed by a callback
        if tween.state != .PLAYING {
            return
        }
        tween.t -= length
        if end < tween.count {
            tween.group = end
            continue
        }

        tween.loop_index += 1
        total_loops: int = tween.loops > 0 ? tween.loops : 1
        if tween.infinite || tween.loop_index < total_loops {
            loop_index: int = tween.loop_index
            TweenReset(tween)
            tween.loop_index = loop_index
            if tween.on_loop != nil { tween.on_loop(tween) }
            if tween.state != .PLAYING {
                return
            }
            if length <= 0 {
                // Nothing consumes time, avoid endless loop
                tween.t = 0
                return
            }
            continue
        }

        tween.state = .FINISHED
        tween.t = 0
        if tween.on_finish != nil { tween.on_finish(tween) }
        return true
    }
}

// Group is a sequential step followed by its parallel steps. Returns index after the last step of the group
@(private="file")
GroupEnd :: proc(tween: ^Tween, start: int) -> int {
    end: int = start + 1
    for end < tween.count && tween.steps[end].parallel {
        end += 1
    }
    return end
}

@(private="file")
GroupLength :: proc(tween: ^Tween, start: int, end: int) -> f32 {
    length: f32 = 0
    for i: int = start; i < end; i += 1 {
        step: ^Step = &tween.steps[i]
        length = max(length, step.delay + step.duration)
    }
    return length
}

@(private="file")
GroupApply :: proc(tween: ^Tween, start: int, end: int, group_t: f32) {
    for i: int = start; i < end; i += 1 {
        step: ^Step = &tween.steps[i]
        if step.done { continue }

        local_t: f32 = group_t - step.delay
        if local_t < 0 { continue }

        if !step.started {
            step.started = true
            if step.kind == .PROPERTY && !step.has_from {
                step.from = ValueRead(step.value_kind, step.ptr)
            }
        }

        p: f32 = 1
        if step.duration > 0 {
            p = clamp(local_t / step.duration, 0, 1)
        }
        if p >= 1 {
            step.done = true
        }

        switch step.kind {
        case .PROPERTY:
            target: Values = step.to
            if step.relative {
                target = step.from + step.to
            }
            if p >= 1 {
                ValueWrite(step.value_kind, step.ptr, target)
                continue
            }
            eased: f64 = cast(f64)ease.ease(step.easing, p)
            ValueWrite(step.value_kind, step.ptr, step.from + (target - step.from) * eased)
        case .INTERVAL:
        case .CALLBACK:
            if step.callback != nil { step.callback(tween) }
        case .METHOD:
            if step.method != nil {
                step.method(tween, p >= 1 ? 1 : ease.ease(step.easing, p))
            }
        }
    }
}
