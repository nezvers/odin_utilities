#+build !js
// Tests of signal.odin. They are in their own file because the library is used by games with a web build, and core:testing does
// not compile for js_wasm32.
package signal

import "core:testing"

// what the callbacks write: the order they were called in and the sum of the payloads
@(private="file", thread_local)
calls: [32]int
@(private="file", thread_local)
call_count: int
@(private="file", thread_local)
total: int

@(private="file")
record :: proc(tag: int) {
    if call_count < len(calls) {
        calls[call_count] = tag
        call_count += 1
    }
}

@(private="file")
reset :: proc() {
    call_count = 0
    total = 0
}

@(private="file")
a :: proc(payload: int) {
    record(1)
    total += payload
}
@(private="file")
b :: proc(payload: int) {
    record(2)
    total += payload * 10
}
@(private="file")
c :: proc(payload: int) {
    record(3)
    total += payload * 100
}

@(private="file")
IntSignal :: Signal(int, 4, 4)

@(test)
test_emit_calls_in_connection_order_with_the_payload :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    SignalConnect(&signal, a)
    SignalConnect(&signal, b)
    SignalConnect(&signal, c)
    testing.expect_value(t, SignalEmit(&signal, 2), 3)
    testing.expect_value(t, calls[0], 1)
    testing.expect_value(t, calls[1], 2)
    testing.expect_value(t, calls[2], 3)
    testing.expect_value(t, total, 2 + 20 + 200)
    testing.expect_value(t, SignalConnectionCount(&signal), 3)
}

// ---- the shapes of a callback: payload and bound, payload, bound, nothing

@(private="file")
Tint :: struct {
    amount: int,
    scale: f32,
}

@(private="file", thread_local)
seen_tint: Tint
@(private="file", thread_local)
seen_payload: int

@(private="file")
with_both :: proc(payload: int, tint: Tint) {
    seen_payload = payload
    seen_tint = tint
}
@(private="file")
with_bound :: proc(tint: Tint) {
    seen_tint = tint
    total += 1000
}
@(private="file")
with_nothing :: proc() {
    total += 1
}

@(test)
test_all_callback_shapes_get_what_they_ask_for :: proc(t: ^testing.T) {
    reset()
    signal: Signal(int, 8, 4, size_of(Tint))
    SignalConnect(&signal, with_both, Tint{amount = 3, scale = 0.5})
    SignalConnect(&signal, with_bound, Tint{amount = 9, scale = 2})
    SignalConnect(&signal, with_nothing)
    SignalConnect(&signal, a)
    SignalEmit(&signal, 7)
    testing.expect_value(t, seen_payload, 7)
    testing.expect_value(t, seen_tint, Tint{amount = 9, scale = 2})     // with_bound ran after with_both and wrote its own
    testing.expect_value(t, total, 1000 + 1 + 7)

    SignalDisconnectAll(&signal)
    SignalConnect(&signal, with_both, Tint{amount = 3, scale = 0.5})
    SignalEmit(&signal, 5)
    testing.expect_value(t, seen_tint, Tint{amount = 3, scale = 0.5})
    testing.expect_value(t, seen_payload, 5)
}

@(test)
test_bound_value_is_a_copy_made_at_connect_time :: proc(t: ^testing.T) {
    reset()
    signal: Signal(int, 4, 4, size_of(Tint))
    tint: Tint = {amount = 1}
    SignalConnect(&signal, with_bound, tint)
    tint.amount = 99                                    // later changes to the original do not reach the connection
    SignalEmit(&signal, 0)
    testing.expect_value(t, seen_tint.amount, 1)
}

@(test)
test_the_same_callback_with_other_bound_values_are_different_connections :: proc(t: ^testing.T) {
    reset()
    signal: Signal(int, 4, 4, size_of(int))
    _, first := SignalConnect(&signal, add_bound, int(1))
    _, again := SignalConnect(&signal, add_bound, int(1))
    _, other := SignalConnect(&signal, add_bound, int(2))
    testing.expect(t, first)
    testing.expect(t, !again, "same callback, same bound: the same connection")
    testing.expect(t, other)
    SignalEmit(&signal, 0)
    testing.expect_value(t, total, 3)
}

@(private="file")
add_bound :: proc(amount: int) {
    total += amount
}

@(test)
test_order_is_kept_when_slots_are_reused :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    id_a, _ := SignalConnect(&signal, a)
    SignalConnect(&signal, b)
    SignalDisconnect(&signal, id_a)
    SignalConnect(&signal, c)               // takes the slot of a in the handle map, but it was connected last
    SignalConnect(&signal, a)               // and so is this one
    SignalEmit(&signal, 1)
    testing.expect_value(t, call_count, 3)
    testing.expect_value(t, calls[0], 2)
    testing.expect_value(t, calls[1], 3)
    testing.expect_value(t, calls[2], 1)
}

@(test)
test_one_shot_is_called_once :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    id, _ := SignalConnect(&signal, a, flags = {.ONE_SHOT})
    SignalConnect(&signal, b)
    testing.expect_value(t, SignalEmit(&signal, 1), 2)
    testing.expect(t, !SignalIsConnectionValid(&signal, id))
    testing.expect_value(t, SignalEmit(&signal, 1), 1)
    testing.expect_value(t, SignalConnectionCount(&signal), 1)
}

@(test)
test_deferred_waits_for_the_flush :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    SignalConnect(&signal, a, flags = {.DEFERRED})
    SignalConnect(&signal, b)
    testing.expect_value(t, SignalEmit(&signal, 1), 1)          // only b ran now
    testing.expect_value(t, SignalPendingCount(&signal), 1)
    testing.expect_value(t, calls[0], 2)
    SignalEmit(&signal, 2)
    testing.expect_value(t, SignalFlush(&signal), 2)            // both emits are delivered, in the order they were made
    testing.expect_value(t, total, 10 + 20 + 1 + 2)
    testing.expect_value(t, SignalPendingCount(&signal), 0)
    testing.expect_value(t, SignalFlush(&signal), 0)
}

@(test)
test_deferred_keeps_the_bound_value :: proc(t: ^testing.T) {
    reset()
    signal: Signal(int, 4, 4, size_of(Tint))
    SignalConnect(&signal, with_both, Tint{amount = 4}, {.DEFERRED})
    SignalEmit(&signal, 8)
    SignalFlush(&signal)
    testing.expect_value(t, seen_payload, 8)
    testing.expect_value(t, seen_tint.amount, 4)
}

@(test)
test_deferred_one_shot_and_disconnect_while_waiting :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    SignalConnect(&signal, a, flags = {.DEFERRED, .ONE_SHOT})
    id_c, _ := SignalConnect(&signal, c, flags = {.DEFERRED})
    SignalEmit(&signal, 1)
    SignalEmit(&signal, 1)
    SignalDisconnect(&signal, id_c)                             // gone before it was delivered: skipped
    testing.expect_value(t, SignalFlush(&signal), 1)            // a once (one shot), the second queued call finds it removed
    testing.expect_value(t, total, 1)
}

@(test)
test_deferred_queue_is_a_ring_that_drops_when_full :: proc(t: ^testing.T) {
    reset()
    signal: Signal(int, 2, 3)
    SignalConnect(&signal, a, flags = {.DEFERRED})
    for _ in 0 ..< 5 { SignalEmit(&signal, 1) }
    testing.expect_value(t, SignalPendingCount(&signal), 3)
    testing.expect_value(t, SignalDroppedCount(&signal), 2)
    testing.expect_value(t, SignalFlush(&signal), 3)
    for _ in 0 ..< 2 { SignalEmit(&signal, 1) }                 // the ring wraps around
    testing.expect_value(t, SignalFlush(&signal), 2)
    testing.expect_value(t, total, 5)
}

@(private="file", thread_local)
shared_signal: ^IntSignal
@(private="file", thread_local)
shared_id: ConnectionId

@(private="file")
disconnect_self :: proc(payload: int) {
    record(4)
    SignalDisconnect(shared_signal, shared_id)
}

@(test)
test_a_callback_can_disconnect_itself_and_others :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    shared_signal = &signal
    defer shared_signal = nil
    shared_id, _ = SignalConnect(&signal, disconnect_self)
    SignalConnect(&signal, b)
    SignalEmit(&signal, 1)
    testing.expect_value(t, call_count, 2)
    testing.expect_value(t, SignalConnectionCount(&signal), 1)
    SignalEmit(&signal, 1)
    testing.expect_value(t, call_count, 3)                      // only b the second time
}

@(private="file")
disconnect_next :: proc(payload: int) {
    record(5)
    SignalDisconnectCallback(shared_signal, b)
}

@(test)
test_a_disconnected_one_is_not_called_later_in_the_same_emit :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    shared_signal = &signal
    defer shared_signal = nil
    SignalConnect(&signal, disconnect_next)
    SignalConnect(&signal, b)
    SignalConnect(&signal, c)
    testing.expect_value(t, SignalEmit(&signal, 1), 2)
    testing.expect_value(t, calls[0], 5)
    testing.expect_value(t, calls[1], 3)
}

@(private="file")
connect_more :: proc(payload: int) {
    record(6)
    SignalConnect(shared_signal, c)
}

@(test)
test_connecting_while_emitting_waits_for_the_next_emit :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    shared_signal = &signal
    defer shared_signal = nil
    SignalConnect(&signal, connect_more, flags = {.ONE_SHOT})
    testing.expect_value(t, SignalEmit(&signal, 1), 1)
    testing.expect_value(t, SignalConnectionCount(&signal), 1)
    testing.expect_value(t, SignalEmit(&signal, 1), 1)
    testing.expect_value(t, calls[1], 3)
}

@(private="file")
depth: int

@(private="file")
emit_again :: proc(payload: int) {
    record(7)
    if payload > 0 { SignalEmit(shared_signal, payload - 1) }
    depth += 1
}

@(test)
test_a_callback_can_emit_the_same_signal :: proc(t: ^testing.T) {
    reset()
    depth = 0
    signal: IntSignal
    shared_signal = &signal
    defer shared_signal = nil
    SignalConnect(&signal, emit_again)
    SignalConnect(&signal, a)
    SignalEmit(&signal, 2)
    testing.expect_value(t, depth, 3)
    testing.expect_value(t, signal.emitting, 0)
    testing.expect_value(t, SignalConnectionCount(&signal), 2)
}

@(test)
test_capacity_duplicates_and_stale_ids :: proc(t: ^testing.T) {
    reset()
    signal: Signal(int, 2, 1)
    first, first_ok := SignalConnect(&signal, a)
    testing.expect(t, first_ok)
    _, duplicate_ok := SignalConnect(&signal, a)
    testing.expect(t, !duplicate_ok, "the same callback twice is refused")
    _, second_ok := SignalConnect(&signal, b)
    testing.expect(t, second_ok)
    _, full_ok := SignalConnect(&signal, c)
    testing.expect(t, !full_ok, "full: fails instead of growing")

    testing.expect(t, SignalDisconnect(&signal, first))
    testing.expect(t, !SignalDisconnect(&signal, first), "already gone")
    third, third_ok := SignalConnect(&signal, c)                // takes the slot of the removed one
    testing.expect(t, third_ok)
    testing.expect(t, !SignalIsConnectionValid(&signal, first), "the old id does not point at the new connection")
    testing.expect(t, SignalIsConnectionValid(&signal, third))
    testing.expect(t, !SignalDisconnect(&signal, first))
    testing.expect_value(t, SignalConnectionCount(&signal), 2)
}

@(test)
test_blocked_signal_does_nothing :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    SignalConnect(&signal, a)
    SignalSetBlocked(&signal, true)
    testing.expect(t, SignalIsBlocked(&signal))
    testing.expect_value(t, SignalEmit(&signal, 1), 0)
    testing.expect_value(t, call_count, 0)
    SignalSetBlocked(&signal, false)
    testing.expect_value(t, SignalEmit(&signal, 1), 1)
}

@(test)
test_disconnect_by_callback_key_and_all :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    SignalConnect(&signal, a)
    SignalConnect(&signal, b, key = 7)
    SignalConnect(&signal, c)
    testing.expect_value(t, SignalDisconnectCallback(&signal, a), 1)
    testing.expect(t, !SignalIsConnected(&signal, a))
    testing.expect(t, SignalIsKeyConnected(&signal, 7))
    testing.expect(t, SignalDisconnectKey(&signal, 7))
    testing.expect(t, !SignalDisconnectKey(&signal, 7))
    SignalEmit(&signal, 1)
    testing.expect_value(t, calls[0], 3)

    SignalConnect(&signal, a, flags = {.DEFERRED})
    SignalEmit(&signal, 1)
    SignalDisconnectAll(&signal)
    testing.expect_value(t, SignalConnectionCount(&signal), 0)
    testing.expect_value(t, SignalPendingCount(&signal), 0)
    testing.expect_value(t, SignalEmit(&signal, 1), 0)
    testing.expect_value(t, SignalFlush(&signal), 0)
}

@(test)
test_empty_payload_and_struct_payload :: proc(t: ^testing.T) {
    reset()
    ping :: proc(payload: Empty) { total += 1 }
    signal: Signal(Empty, 2, 1)
    SignalConnect(&signal, ping)
    SignalEmit(&signal, {})
    testing.expect_value(t, total, 1)

    HealthChange :: struct { old, new: f32 }
    health: Signal(HealthChange, 4, 4)
    SignalConnect(&health, proc(payload: HealthChange) { total = int(payload.old - payload.new) })
    SignalEmit(&health, {old = 100, new = 75})
    testing.expect_value(t, total, 25)
}

// ---- owners: the answer to a bound value that points at something that is gone

@(private="file")
add_owner_tag :: proc(payload: int, owner_tag: int) {
    total += owner_tag
}

@(test)
test_disconnect_owner_removes_what_an_owner_connected :: proc(t: ^testing.T) {
    reset()
    signal: Signal(int, 4, 4, size_of(int))
    SignalConnect(&signal, add_owner_tag, int(1), owner = 100)
    SignalConnect(&signal, add_owner_tag, int(2), owner = 100)
    SignalConnect(&signal, add_owner_tag, int(4), owner = 200)
    SignalConnect(&signal, a)                                   // no owner
    testing.expect_value(t, SignalDisconnectOwner(&signal, 100), 2)
    testing.expect_value(t, SignalDisconnectOwner(&signal, 0), 0)
    SignalEmit(&signal, 0)
    testing.expect_value(t, total, 4)
    testing.expect_value(t, SignalConnectionCount(&signal), 2)
}

@(private="file", thread_local)
alive_owners: [4]Owner

@(private="file")
owner_is_alive :: proc(owner: Owner) -> bool {
    for alive in alive_owners { if alive == owner { return true } }
    return false
}

@(test)
test_a_connection_of_an_owner_that_is_gone_is_removed_not_called :: proc(t: ^testing.T) {
    reset()
    signal: Signal(int, 4, 4, size_of(int))
    signal.owner_alive = owner_is_alive
    alive_owners = {10, 20, 0, 0}
    SignalConnect(&signal, add_owner_tag, int(1), owner = 10)
    SignalConnect(&signal, add_owner_tag, int(2), owner = 20)
    SignalConnect(&signal, a)
    SignalEmit(&signal, 0)
    testing.expect_value(t, total, 3)

    alive_owners = {20, 0, 0, 0}                                // 10 is freed, nobody told the signal
    SignalEmit(&signal, 0)
    testing.expect_value(t, total, 3 + 2)                       // only owner 20 ran, nothing touched the freed one
    testing.expect_value(t, SignalConnectionCount(&signal), 2)  // and its connection is gone for good

    // deferred: the owner can go while the call waits
    SignalConnect(&signal, add_owner_tag, int(8), {.DEFERRED}, owner = 20)
    SignalEmit(&signal, 0)
    alive_owners = {}
    total = 0
    SignalFlush(&signal)
    testing.expect_value(t, total, 0)
}

@(test)
test_owner_of_a_handle :: proc(t: ^testing.T) {
    Handle :: struct { idx, gen: u32 }
    first: Owner = OwnerOf(Handle{idx = 3, gen = 1})
    again: Owner = OwnerOf(Handle{idx = 3, gen = 1})
    reused: Owner = OwnerOf(Handle{idx = 3, gen = 2})
    testing.expect(t, first == again)
    testing.expect(t, first != reused, "the same slot with another generation is another owner")
    testing.expect(t, first != 0)
}

// ---- hot reload: the data stays, the procs are given again

@(private="file")
old_code :: proc(payload: int, tag: int) {
    total += payload + tag
}
@(private="file")
new_code :: proc(payload: int, tag: int) {
    total += (payload + tag) * 1000
}

@(test)
test_rebind_gives_a_connection_its_new_code_and_keeps_everything_else :: proc(t: ^testing.T) {
    reset()
    signal: Signal(int, 4, 4, size_of(int))
    id_hud, _ := SignalConnect(&signal, old_code, int(1), key = 1)
    id_log, _ := SignalConnect(&signal, old_code, int(2), {.DEFERRED}, key = 2)
    SignalConnect(&signal, a)
    SignalEmit(&signal, 10)                                     // a log call is waiting in the queue
    testing.expect_value(t, SignalPendingCount(&signal), 1)
    testing.expect_value(t, total, 11 + 10)

    // --- the reload
    SignalRebindBegin(&signal)
    testing.expect_value(t, SignalStaleCount(&signal), 3)
    reset()
    testing.expect_value(t, SignalEmit(&signal, 5), 0)          // nothing calls into the old code
    testing.expect_value(t, call_count, 0)

    testing.expect(t, SignalRebind(&signal, new_code, int(1), key = 1))
    testing.expect(t, SignalRebind(&signal, new_code, int(2), {.DEFERRED}, key = 2))
    testing.expect(t, !SignalRebind(&signal, new_code, int(3), key = 3), "no connection with that key: nothing is created")
    testing.expect_value(t, SignalDisconnectStale(&signal), 1)  // `a` had no key, the new code does not know it
    testing.expect_value(t, SignalStaleCount(&signal), 0)

    testing.expect(t, SignalIsConnectionValid(&signal, id_hud), "the ids are the same")
    testing.expect(t, SignalIsConnectionValid(&signal, id_log))
    testing.expect_value(t, SignalFlush(&signal), 1)            // the call that waited is delivered to the new code
    testing.expect_value(t, total, (10 + 2) * 1000)
    reset()
    testing.expect_value(t, SignalEmit(&signal, 5), 1)
    testing.expect_value(t, total, (5 + 1) * 1000)
}

@(test)
test_rebind_does_not_bring_back_a_one_shot_that_fired :: proc(t: ^testing.T) {
    reset()
    signal: Signal(int, 4, 4, size_of(int))
    SignalConnect(&signal, old_code, int(1), {.ONE_SHOT}, key = 1)
    SignalConnect(&signal, old_code, int(2), key = 2)
    SignalEmit(&signal, 0)
    testing.expect_value(t, SignalConnectionCount(&signal), 1)

    SignalRebindBegin(&signal)
    testing.expect(t, !SignalRebind(&signal, new_code, int(1), {.ONE_SHOT}, key = 1))
    testing.expect(t, SignalRebind(&signal, new_code, int(2), key = 2))
    testing.expect_value(t, SignalDisconnectStale(&signal), 0)
    testing.expect_value(t, SignalConnectionCount(&signal), 1)
}

@(test)
test_rebind_replaces_the_bound_value_and_the_owner_check :: proc(t: ^testing.T) {
    reset()
    signal: Signal(int, 4, 4, size_of(int))
    signal.owner_alive = owner_is_alive
    alive_owners = {50, 0, 0, 0}
    SignalConnect(&signal, old_code, int(1), key = 1, owner = 50)

    SignalRebindBegin(&signal)
    testing.expect(t, signal.owner_alive == nil, "a proc of the old code is dropped")
    SignalRebind(&signal, new_code, int(7), key = 1, owner = 50)     // the new code has another bound value
    signal.owner_alive = owner_is_alive
    SignalEmit(&signal, 1)
    testing.expect_value(t, total, 8 * 1000)
}

@(test)
test_a_key_is_one_connection :: proc(t: ^testing.T) {
    reset()
    signal: Signal(int, 4, 4, size_of(int))
    _, first := SignalConnect(&signal, old_code, int(1), key = 5)
    _, same_key := SignalConnect(&signal, new_code, int(2), key = 5)
    testing.expect(t, first)
    testing.expect(t, !same_key)
}

@(test)
test_the_signal_is_plain_memory_that_can_be_copied :: proc(t: ^testing.T) {
    reset()
    signal: Signal(int, 4, 4, size_of(int))
    SignalConnect(&signal, add_bound, int(5), key = 1)
    saved: Signal(int, 4, 4, size_of(int)) = signal             // game memory that is copied or kept over a reload
    SignalEmit(&saved, 0)
    testing.expect_value(t, total, 5)
    testing.expect_value(t, size_of(BoundStorage(0)), 0)
}
