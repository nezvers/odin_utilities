package tween

import "core:mem"


import hm "core:container/handle_map"
Handle :: hm.Handle32

// Tweens are created by user and removed when finished
// Queues 
TweenSystem :: struct($TWEEN_SIZE: int, $QUEUE_SIZE: int) {
    tweens: hm.Static_Handle_Map(TWEEN_SIZE, Tween, Handle),
    waiting: [QUEUE_SIZE]TweenQueue,
    active: [QUEUE_SIZE]TweenQueue,
}

Tween :: struct {
    handle: Handle,
    next: ^Tween,   // TODO: replace with handle
    t: f32,         // Timer value
    length: f32,    // Value carrying tweening length, useful for interpolation t/length
    user_data:rawptr,
    started: proc(tween: ^Tween),
    finished: proc(tween: ^Tween),
    update: proc(tween: ^Tween, delta_time: f32),
}

// Tweens not yet started
TweenQueue :: struct {
    delay_remaining:f32,
    tween: Tween,
    id: int,
    pool: ^TweenPool,
}


TweenPool :: struct {
    list: []TweenQueue,
    active_count: int,
}

UpdateSystem :: proc(waiting: ^TweenPool, active: ^TweenPool, delta_time:f32, next_overflow:bool = true) {
    for i:int = 0; i < waiting.active_count; i += 1 {
        item: ^TweenQueue = &waiting.list[i]
        item.delay_remaining -= delta_time
        if item.delay_remaining > 0 { continue }

        tween_queue, append_ok: = PoolAppend(active, item)
        if append_ok {
            tween: ^Tween = &tween_queue.tween
            if tween.started != nil { tween.started(tween) }
        }
        if !PoolRemove(waiting, i) {
            // TODO: error
        }
    }

    for i:int = 0; i < active.active_count; i += 1 {
        tween: ^Tween = &active.list[i].tween
        is_finished:bool = UpdateTween(tween, delta_time)
        if is_finished {
            // replace with tween.next
            if tween.next != nil {
                next: ^Tween = tween.next
                if next_overflow {
                    overflow:f32 = tween.t - tween.length - delta_time
                    next.t = overflow
                }
                mem.copy_non_overlapping(tween, next, size_of(Tween))
                if tween.started != nil { tween.started(tween) }
                // repeat in place
                i -= 1
            } else {
                if !PoolRemove(active, i) {
                    // TODO: error
                }
            }
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

PoolRemove :: proc(pool: ^TweenPool, index:int)->(ok:bool) {
    assert(pool.active_count > index)
    if pool.active_count < 1 { return }

    ok = true
    remove: ^TweenQueue = &pool.list[index]
    last: ^TweenQueue = &pool.list[pool.active_count -1]
    pool.active_count -= 1
    if remove != last {
        mem.copy_non_overlapping(remove, last, size_of(TweenQueue))
        // last is at this address, update it's id
        remove.id = index
    }
    return
}

PoolAppend :: proc(pool: ^TweenPool, new_item: ^TweenQueue)->(item: ^TweenQueue, ok:bool) {
    if !(pool.active_count < len(pool.list)) { return }

    ok = true
    item = &pool.list[pool.active_count]
    mem.copy_non_overlapping(item, new_item, size_of(TweenQueue))
    item.id = pool.active_count
    pool.active_count += 1
    return
}

PoolNew :: proc(pool: ^TweenPool)->(item: ^TweenQueue, ok:bool) {
    if !(pool.active_count < len(pool.list)) { return }
    ok = true
    item = &pool.list[pool.active_count]
    item.pool = pool
    item.id = pool.active_count
    pool.active_count += 1
    return
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