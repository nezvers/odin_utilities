package tween

import hm "core:container/handle_map"

// Pool of Tweens for a local group, like animating menu buttons.
// It is a value type without allocations, can be placed inside of your own struct.
// Usable capacity is TWEEN_SIZE - 1
TweenSystem :: struct($TWEEN_SIZE: uint) {
    tweens: hm.Static_Handle_Map(TWEEN_SIZE, Tween, Handle),
}

// Create new Tween in the pool. The tween is ready to receive steps, call TweenPlay to start it
SystemNew :: proc(tween_system: ^TweenSystem($N)) -> (result: ^Tween, ok: bool) {
    handle: Handle
    handle, ok = hm.add(&tween_system.tweens, TweenMake())
    if !ok {
        return
    }
    result = hm.get(&tween_system.tweens, handle) or_return
    return
}

// Returns false if tween was removed
SystemGet :: proc(tween_system: ^TweenSystem($N), handle: Handle) -> (result: ^Tween, ok: bool) {
    return hm.get(&tween_system.tweens, handle)
}

// Remove tween from the pool. Handle becomes invalid
SystemKill :: proc(tween_system: ^TweenSystem($N), handle: Handle) -> bool {
    return hm.remove(&tween_system.tweens, handle)
}

// Remove all tweens
SystemClear :: proc(tween_system: ^TweenSystem($N)) {
    hm.clear(&tween_system.tweens)
}

SystemLen :: proc(tween_system: ^TweenSystem($N)) -> uint {
    return hm.len(tween_system.tweens)
}

// Update all playing tweens. Finished tweens are removed unless `keep` is set
SystemUpdate :: proc(tween_system: ^TweenSystem($N), delta_time: f32) {
    it: = hm.iterator_make(&tween_system.tweens)
    for tween, handle in hm.iterate(&it) {
        if tween.state != .PLAYING {
            continue
        }
        finished: bool = TweenUpdate(tween, delta_time)
        if finished && !tween.keep {
            hm.remove(&tween_system.tweens, handle)
        }
    }
}
