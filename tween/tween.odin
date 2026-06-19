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

TweenNew :: proc(tween_system: ^TweenSystem($T, $Q), tween: Tween = {}) -> (result:^Tween, ok:bool) {
    handle, add_ok: = hm.add(&tween_system.tweens, tween)
    if !add_ok { return }
    return hm.get(&tween_system.tweens, handle)
}

// Returns pointer for first Tween in the chain    
// Sets handles for Tweens in list to allow referencing inserted Tweens    
// In case of a failure all insertions are aborted - removing already inserted chain Tweens
TweenNewChain :: proc(tween_system: ^TweenSystem($T, $Q), list: []Tween) -> (first: ^Tween, ok:bool) {
    next_handle: = HandleNone
    tween: ^Tween
    for i:int = len(list) -1; i > -1; i -= 1 {
        tween = &list[i]
        handle, add_ok: = hm.add(&tween_system.tweens, tween^)
        if !add_ok {
            // Remove already created
            for j:int = i +1; j < len(list); j += 1 {
                hm.remove(tween_system, list[j].handle )
                list[j].handle = HandleNone
            }
            return
        }
        tween.handle = handle
        tween.next = next_handle
    }
    first = tween
    ok = true
    return
}

TweenGet :: proc(tween_system: ^TweenSystem($T, $Q), handle: Handle) -> (result:^Tween, ok:bool) {
    return hm.get(&tween_system.tweens, handle)
}

// Next time system is updated the tween will be removed from waiting or active queue
TweenRemove :: proc(tween_system: ^TweenSystem($T, $Q), handle: Handle)->(ok:bool) {
    return hm.remove(&tween_system.tweens, handle)
}

// Inserts Tween into system
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
    if !hm.is_valid(handle) { return }
    tween, tw_ok: = hm.get(handle)

    next:Handle
    for tw_ok {
        next = tween.next
        hm.remove(&tween_system.tweens, tween.handle)
        if !hm.is_valid(next) { break }
        tween, tw_ok = hm.get(next)
    }

    ok = true
    return 
}

UpdateSystem :: proc(tween_system: ^TweenSystem($T, $Q), delta_time:f32, next_overflow:bool = true) {
    for i:int = len(tween_system.waiting) -1; i > -1; i -= 1 {
        // itterate from end to be able unordered_remove
        item: ^TweenQueue = &tween_system.waiting[i]
        item.delay_sec -= delta_time
        if item.delay_sec > 0 { continue }

        tween, handle_ok: = hm.get(&tween_system.tweens, item.handle)
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
        tween, handle_ok: = hm.get(&tween_system.tweens, tween_system.active[i].handle)
        if !handle_ok {
            unordered_remove(&tween_system.active, i)
            continue
        }
        
        is_finished:bool = UpdateTween(tween, delta_time)
        if is_finished {
            // replace with tween.next
            next_handle: Handle = tween.next
            TweenRemove(tween_system, tween.handle)

            if hm.is_valid(tween_system.tweens, next_handle) {
                next, next_ok: = hm.get(&tween_system.tweens, next_handle)
                if next_ok {
                    tween_system.active[i].handle = next.handle
                    if next.on_start != nil { next.on_start(next) }
                    if next_overflow {
                        overflow:f32 = tween.t - tween.length - delta_time
                        next.t = overflow
                    }
                    // repeat in place
                    i += 1
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
