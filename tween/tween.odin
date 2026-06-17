package tween

import hm "core:container/handle_map"
Handle :: hm.Handle32
HandleNone :Handle: {}

// Holds state of Tween management    
// Need to be updated through UpdateSystem    
// Since it's possible to chain, multiple tweens can be used with the same queue
TweenSystem :: struct($TWEEN_SIZE: uint, $QUEUE_SIZE: int) {
    tweens: hm.Static_Handle_Map(TWEEN_SIZE, Tween, Handle),
    waiting: [dynamic; QUEUE_SIZE]TweenQueue,
    active: [dynamic; QUEUE_SIZE]TweenQueue,
}

Tween :: struct {
    handle: Handle,
    next: Handle,   // After finishing current Tween will be replaced with next
    t: f32,         // Timer value
    length: f32,    // Value carrying tweening length, needed for interpolation t/length
    user_data:rawptr, // Generic way to carry user facing data
    on_start: proc(tween: ^Tween),
    on_finish: proc(tween: ^Tween),
    on_update: proc(tween: ^Tween, delta_time: f32),
}

TweenQueue :: struct {
    delay_sec:f32,
    handle: Handle,
}

TweenNew :: proc(tween_system: ^TweenSystem($T, $Q)) -> (result:^Tween, ok:bool) {
    handle := hm.static_add(&tween_system.tweens, Tween{})
    return hm.static_get(&tween_system.tweens, handle)
}

TweenGet :: proc(tween_system: ^TweenSystem($T, $Q), handle: Handle) -> (result:^Tween, ok:bool) {
    return hm.static_get(&tween_system.tweens, handle)
}

TweenRemove :: proc(tween_system: ^TweenSystem($T, $Q), handle: Handle)->(ok:bool) {
    return hm.static_remove(&tween_system.tweens, handle)
}

TweenStart :: proc(tween_system: ^TweenSystem($T, $Q), handle: Handle, delay_sec:f32 = 0)->(ok:bool) {
    if (len(tween_system.waiting) < cap(tween_system.waiting)) {
        queue: TweenQueue = {
            delay_sec = delay_sec,
            handle = handle,
        }

        if append(&tween_system.waiting, queue) == 0 {
            // TODO: error
            return
        }
        ok = true
    }
    return
}

// Next time system is updated the tween will be removed from waiting or active queue
TweenStop :: proc(tween_system: ^TweenSystem($T, $Q), handle: Handle)->(ok:bool) {
    return hm.static_remove(&tween_system.tweens, handle)
}

UpdateSystem :: proc(tween_system: ^TweenSystem($T, $Q), delta_time:f32, next_overflow:bool = true) {
    for i:int = len(tween_system.waiting) -1; i > -1; i -= 1 {
        // itterate from end to be able unordered_remove
        item: ^TweenQueue = &tween_system.waiting[i]
        item.delay_sec -= delta_time
        if item.delay_sec > 0 { continue }

        tween, handle_ok: = hm.static_get(&tween_system.tweens, item.handle)
        if !handle_ok {
            unordered_remove(&tween_system.waiting, i)
            continue
        }

        if append(&tween_system.active, item^) != 0 {
            if tween.on_start != nil { tween.on_start(tween) }
        }

        overflow:f32 = -delta_time
        if next_overflow {
            overflow -= item.delay_sec
        }
        tween.t = overflow
        unordered_remove(&tween_system.waiting, i)
    }

    for i:int = len(tween_system.active) -1; i > -1; i -= 1 {
        tween, handle_ok: = hm.static_get(&tween_system.tweens, tween_system.active[i].handle)
        if !handle_ok {
            unordered_remove(&tween_system.active, i)
            continue
        }
        
        is_finished:bool = UpdateTween(tween, delta_time)
        if is_finished {
            // replace with tween.next
            next_handle: Handle = tween.next
            TweenRemove(tween_system, tween.handle)

            if next_handle != HandleNone {
                next, next_ok: = hm.static_get(&tween_system.tweens, next_handle)
                if next_ok {
                    tween_system.active[i].handle = next.handle
                    if next.on_start != nil { next.on_start(next) }
                    if next_overflow {
                        overflow:f32 = tween.t - tween.length - delta_time
                        next.t = overflow
                    }
                    // repeat in place
                    i -= 1
                    continue
                }
            }
            unordered_remove(&tween_system.active, i)
        }
    }
}

UpdateTween :: proc(tween: ^Tween, delta_time:f32)->(done:bool) {
    tween.t += delta_time
    if tween.t < tween.length {
        t: = tween.t/tween.length
        // Leave easing to user
        if tween.on_update != nil { tween.on_update(tween, t) }
        return
    }

    done = true
    if tween.on_update != nil { tween.on_update(tween, 1) }
    if tween.on_finish != nil { tween.on_finish(tween) }
    return
}
