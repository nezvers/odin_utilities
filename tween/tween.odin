package tween

import hm "core:container/handle_map"
Handle :: hm.Handle32
HandleNone :Handle: {}
HandleMap :: hm.Static_Handle_Map(512, Tween, Handle)

// Tweens are created by user and removed when finished
// Queues 
TweenSystem :: struct($TWEEN_SIZE: int, $QUEUE_SIZE: int) {
    tweens: HandleMap,
    waiting: [dynamic; QUEUE_SIZE]TweenQueue,
    active: [dynamic; QUEUE_SIZE]TweenQueue,
}

Tween :: struct {
    handle: Handle,
    next: Handle,   // TODO: replace with handle
    t: f32,         // Timer value
    length: f32,    // Value carrying tweening length, useful for interpolation t/length
    user_data:rawptr,
    started: proc(tween: ^Tween),
    finished: proc(tween: ^Tween),
    update: proc(tween: ^Tween, delta_time: f32),
}

// Tweens not yet started
TweenQueue :: struct {
    delay_sec:f32,
    handle: Handle,
    id: int,        // index of array it is in
}

/* handle example
{ // static map
	entities: hm.Static_Handle_Map(1024, Entity, Handle)

	h1 := hm.add(&entities, Entity{pos = {1,  4}})
	h2 := hm.add(&entities, Entity{pos = {9, 16}})

	if e, ok := hm.get(&entities, h2); ok {
		e.pos.x += 32
	}

	hm.remove(&entities, h1)

	h3 := hm.add(&entities, Entity{pos = {6, 7}})
	assert(hm.is_valid(entities, h3))

	it := hm.iterator_make(&entities)
	for e, h in hm.iterate(&it) {
		assert(hm.is_valid(entities, h))
		e.pos += {1, 2}
	}
}
*/

// 
TweenNew :: proc(tween_system: ^TweenSystem($T, $Q)) -> (result:^Tween, ok:bool) {
    handle := hm.add(&tween_system.tweens, Tween{})
    return hm.static_get(&tween_system.tweens, handle)
}

TweenGet :: proc(tween_system: ^TweenSystem($T, $Q), handle: Handle) -> (result:^Tween, ok:bool) {
    return hm.static_get(&tween_system.tweens, handle)
}

TweenRemove :: proc(tween_system: ^TweenSystem($T, $Q), handle: Handle)->(ok:bool) {
    return hm.remove(&entities, handle)
}

TweenStart :: proc(tween_system: ^TweenSystem($T, $Q), handle: Handle, delay_sec:f32 = 0)->(ok:bool) {
    if (len(tween_system.waiting) < cap(tween_system.waiting)) {
        i:int = len(tween_system.waiting)
        queue: TweenQueue = {
            delay_sec = delay_sec,
            handle = handle,
        }
        id, err: = append(&tween_system.waiting, queue)
        if err { return }
        tween_system.waiting[i].id = id
    }
    return
}

// Next time system is updated the tween will be removed from waiting or active queue
TweenStop :: proc(tween_system: ^TweenSystem($T, $Q), handle: Handle)->(ok:bool) {
    return hm.remove(&tween_system.tweens, handle)
}

UpdateSystem :: proc(tween_system: ^TweenSystem($T, $Q), delta_time:f32, next_overflow:bool = true) {
    waiting: []TweenQueue = tween_system.waiting[:]
    active: []TweenQueue = tween_system.active[:]

    for i:int = len(waiting) -1; i > 0; i -= 1 {
        // itterate from end to be able remove by swapping with last
        item: ^TweenQueue = &waiting[i]
        item.delay_sec -= delta_time
        if item.delay_sec > 0 { continue }

        tween: ^Tween
        handle_ok: bool
        tween, handle_ok = hm.static_get(tween_system, item.handle)
        if !handle_ok {
            unordered_remove(&tween_system.waiting, i)
            continue
        }

        num_appended, err: = append(active, item)
        if err != nil {
            if tween.started != nil { tween.started(tween) }
        }

        overflow:f32 = -delta_time
        if next_overflow {
            overflow -= item.delay_sec
        }
        tween.t = overflow
        unordered_remove(&tween_system.waiting, i)
    }

    for i:int = len(active) -1; i > 0; i -= 1 {
        tween: ^Tween
        handle_ok: bool
        tween, handle_ok = hm.get(&tween_system.tweens, active[i].handle)
        if !handle_ok {
            unordered_remove(&tween_system.active, i)
            continue
        }
        
        is_finished:bool = UpdateTween(tween, delta_time)
        if is_finished {
            // replace with tween.next
            if tween.next != HandleNone {
                next: ^Tween
                next_ok:bool
                next, next_ok = hm.get(&tween_system.tweens, tween.next)
                if next_ok {
                    active[i].handle = next.handle
                    if next.started != nil { next.started(next) }
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
        if tween.update != nil { tween.update(tween, t) }
        return
    }

    done = true
    if tween.update != nil { tween.update(tween, 1) }
    if tween.finished != nil { tween.finished(tween) }
    return
}
