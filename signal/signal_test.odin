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
a :: proc(payload: int, user: rawptr) {
    record(1)
    total += payload
}
@(private="file")
b :: proc(payload: int, user: rawptr) {
    record(2)
    total += payload * 10
}
@(private="file")
c :: proc(payload: int, user: rawptr) {
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

@(test)
test_user_pointer_comes_back :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    holder: int = 7
    SignalConnect(&signal, proc(payload: int, user: rawptr) {
        (cast(^int)user)^ += payload
    }, &holder)
    SignalEmit(&signal, 5)
    testing.expect_value(t, holder, 12)
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
    id, _ := SignalConnect(&signal, a, nil, {.ONE_SHOT})
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
    SignalConnect(&signal, a, nil, {.DEFERRED})
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
test_deferred_one_shot_and_disconnect_while_waiting :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    SignalConnect(&signal, a, nil, {.DEFERRED, .ONE_SHOT})
    id_c, _ := SignalConnect(&signal, c, nil, {.DEFERRED})
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
    SignalConnect(&signal, a, nil, {.DEFERRED})
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
disconnect_self :: proc(payload: int, user: rawptr) {
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
disconnect_next :: proc(payload: int, user: rawptr) {
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
connect_more :: proc(payload: int, user: rawptr) {
    record(6)
    SignalConnect(shared_signal, c)
}

@(test)
test_connecting_while_emitting_waits_for_the_next_emit :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    shared_signal = &signal
    defer shared_signal = nil
    SignalConnect(&signal, connect_more, nil, {.ONE_SHOT})
    testing.expect_value(t, SignalEmit(&signal, 1), 1)
    testing.expect_value(t, SignalConnectionCount(&signal), 1)
    testing.expect_value(t, SignalEmit(&signal, 1), 1)
    testing.expect_value(t, calls[1], 3)
}

@(private="file")
depth: int

@(private="file")
emit_again :: proc(payload: int, user: rawptr) {
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
    testing.expect(t, !duplicate_ok, "the same callback and user twice is refused")
    marker: int
    _, other_user_ok := SignalConnect(&signal, a, &marker)
    testing.expect(t, other_user_ok, "same callback, another object is fine")
    _, full_ok := SignalConnect(&signal, b)
    testing.expect(t, !full_ok, "full: fails instead of growing")

    testing.expect(t, SignalDisconnect(&signal, first))
    testing.expect(t, !SignalDisconnect(&signal, first), "already gone")
    second, second_ok := SignalConnect(&signal, b)              // takes the slot of the removed one
    testing.expect(t, second_ok)
    testing.expect(t, !SignalIsConnectionValid(&signal, first), "the old id does not point at the new connection")
    testing.expect(t, SignalIsConnectionValid(&signal, second))
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
test_disconnect_user_and_all :: proc(t: ^testing.T) {
    reset()
    signal: IntSignal
    first_object, second_object: int
    SignalConnect(&signal, a, &first_object)
    SignalConnect(&signal, b, &first_object)
    SignalConnect(&signal, c, &second_object)
    testing.expect_value(t, SignalDisconnectUser(&signal, &first_object), 2)
    testing.expect_value(t, SignalConnectionCount(&signal), 1)
    SignalEmit(&signal, 1)
    testing.expect_value(t, calls[0], 3)

    SignalConnect(&signal, a, nil, {.DEFERRED})
    SignalEmit(&signal, 1)
    SignalDisconnectAll(&signal)
    testing.expect_value(t, SignalConnectionCount(&signal), 0)
    testing.expect_value(t, SignalPendingCount(&signal), 0)
    testing.expect_value(t, SignalEmit(&signal, 1), 0)
    testing.expect_value(t, SignalFlush(&signal), 0)
}

@(test)
test_disconnect_callback_and_empty_payload :: proc(t: ^testing.T) {
    reset()
    signal: Signal(Empty, 2, 1)
    ping :: proc(payload: Empty, user: rawptr) { total += 1 }
    SignalConnect(&signal, ping)
    SignalEmit(&signal, {})
    testing.expect_value(t, total, 1)
    testing.expect(t, SignalDisconnectCallback(&signal, ping))
    testing.expect(t, !SignalDisconnectCallback(&signal, ping))
    testing.expect_value(t, SignalEmit(&signal, {}), 0)
}

@(test)
test_a_struct_payload_and_a_signal_is_plain_memory :: proc(t: ^testing.T) {
    reset()
    HealthChange :: struct { old, new: f32 }
    signal: Signal(HealthChange, 4, 4)
    seen: f32
    SignalConnect(&signal, proc(payload: HealthChange, user: rawptr) {
        (cast(^f32)user)^ = payload.old - payload.new
    }, &seen)
    SignalEmit(&signal, {old = 100, new = 75})
    testing.expect_value(t, seen, 25)
    // copyable, so it can live in a struct of the game that is copied or saved (the procs are code pointers, see the header)
    copy_of_it: Signal(HealthChange, 4, 4) = signal
    seen = 0
    SignalEmit(&copy_of_it, {old = 10, new = 5})
    testing.expect_value(t, seen, 5)
}
