package signal

// Godot style signals: an object announces that something happened, anyone can listen, neither knows the other.
//
//     HealthChange :: struct { old, new: f32 }
//     health_changed: Signal(HealthChange, 8, 16)      // payload, connections, deferred emissions waiting
//
//     SignalConnect(&health_changed, on_health_changed, &hud)                    // proc(payload: HealthChange, user: rawptr)
//     SignalConnect(&health_changed, on_first_hit, nil, {.ONE_SHOT})            // disconnects itself before the call
//     SignalConnect(&health_changed, on_log, &log, {.DEFERRED})                 // called later by SignalFlush
//     SignalEmit(&health_changed, {old = 100, new = 80})
//
// How it maps to Godot:
//     connect / emit / disconnect / is_connected / set_block_signals  ->  SignalConnect / SignalEmit / SignalDisconnect /
//                                                                         SignalIsConnected / SignalSetBlocked
//     CONNECT_ONE_SHOT, CONNECT_DEFERRED                              ->  .ONE_SHOT, .DEFERRED (deferred: SignalFlush is the idle frame)
//     bind(args)                                                      ->  `user`, a pointer the callback gets back
//     the object is freed, its connections go                         ->  SignalDisconnectUser(&signal, object)
//     signal with several arguments                                   ->  a struct as the payload
//
// Memory: nothing allocates. The connections live in a handle map of fixed size inside the Signal, a ConnectionId is a handle
// (index + generation), so an id of a connection that is gone is refused even when its slot was reused. Connecting past the capacity
// fails instead of growing. Callbacks are called in the order they were connected.
//
// Safe while emitting, like in Godot: a callback may disconnect itself or others (a disconnected one is not called later in the same
// emit), may connect new ones (they are called from the next emit) and may emit the same signal again.
//
// A connection holds a proc, which is a pointer into the code: after a hot reload call SignalDisconnectAll and connect again.
//
// Builds for js_wasm32, the tests are in signal_test.odin.

import hm "core:container/handle_map"

ConnectionId :: distinct hm.Handle32

ConnectFlag :: enum u8 {
    ONE_SHOT,       // disconnected right before its first call
    DEFERRED,       // not called by SignalEmit, the payload waits in the queue of the signal until SignalFlush
}
ConnectFlags :: bit_set[ConnectFlag; u8]

// Payload for a signal that carries nothing
Empty :: struct {}

Connection :: struct($T: typeid) {
    handle: ConnectionId,                       // the handle map needs this field
    callback: proc(payload: T, user: rawptr),
    user: rawptr,
    flags: ConnectFlags,
}

Pending :: struct($T: typeid) {
    id: ConnectionId,
    payload: T,
}

// T: the payload of the signal. N: how many connections at most. Q: how many deferred calls can wait for SignalFlush (1 when nothing
// is deferred). The zero value is a signal without connections.
Signal :: struct($T: typeid, $N: uint, $Q: uint)
    where N > 0, Q > 0 {
    connections: hm.Static_Handle_Map(N + 1, Connection(T), ConnectionId),     // + 1: slot 0 is the empty handle
    order: [N]ConnectionId,         // ids in the order they were connected: the handle map reuses slots, it does not keep order
    order_count: u32,               // while emitting, disconnected ids stay in it (skipped) so the positions do not move
    emitting: u32,                  // depth of SignalEmit, emits can be nested
    blocked: bool,
    pending: [Q]Pending(T),         // ring of deferred calls
    pending_head: u32,
    pending_count: u32,
    dropped: u32,                   // deferred calls lost because the queue was full
}

// Listen. `user` is given back to the callback. Fails (ok = false) when the capacity is full, when the same callback with the same
// user is connected already (Godot refuses that too), or when called while emitting and the list has no room left.
SignalConnect :: proc(signal: ^$S/Signal($T, $N, $Q), callback: proc(payload: T, user: rawptr), user: rawptr = nil, flags: ConnectFlags = {}) -> (id: ConnectionId, ok: bool) {
    assert(callback != nil)
    if SignalIsConnected(signal, callback, user) { return }
    if signal.emitting == 0 { signalCompact(signal) }
    if signal.order_count >= u32(N) { return }
    added: ConnectionId
    added, ok = hm.add(&signal.connections, Connection(T){callback = callback, user = user, flags = flags})
    if !ok { return }
    signal.order[signal.order_count] = added
    signal.order_count += 1
    return added, true
}

// Stop listening. False when the id is not a connection of this signal (anymore).
SignalDisconnect :: proc(signal: ^$S/Signal($T, $N, $Q), id: ConnectionId) -> bool {
    if !hm.remove(&signal.connections, id) { return false }
    if signal.emitting == 0 { signalCompact(signal) }
    return true
}

// Stop listening by what was passed to SignalConnect
SignalDisconnectCallback :: proc(signal: ^$S/Signal($T, $N, $Q), callback: proc(payload: T, user: rawptr), user: rawptr = nil) -> bool {
    id, found := signalFind(signal, callback, user)
    if !found { return false }
    return SignalDisconnect(signal, id)
}

// Remove every connection of one object: what an object does when it is freed in Godot. Returns how many were removed.
SignalDisconnectUser :: proc(signal: ^$S/Signal($T, $N, $Q), user: rawptr) -> (removed: int) {
    for i in 0 ..< signal.order_count {
        connection, alive := hm.get(&signal.connections, signal.order[i])
        if !alive || connection.user != user { continue }
        _ = hm.remove(&signal.connections, signal.order[i])
        removed += 1
    }
    if signal.emitting == 0 { signalCompact(signal) }
    return
}

// Remove everything, also what waits in the deferred queue
SignalDisconnectAll :: proc(signal: ^$S/Signal($T, $N, $Q)) {
    for i in 0 ..< signal.order_count {
        _ = hm.remove(&signal.connections, signal.order[i])
    }
    signal.pending_count = 0
    signal.pending_head = 0
    if signal.emitting == 0 { signalCompact(signal) }
}

SignalIsConnected :: proc(signal: ^$S/Signal($T, $N, $Q), callback: proc(payload: T, user: rawptr), user: rawptr = nil) -> bool {
    _, found := signalFind(signal, callback, user)
    return found
}

// Is this connection still there. An id is checked with its generation, the slot of a removed connection may hold another one now.
SignalIsConnectionValid :: proc(signal: ^$S/Signal($T, $N, $Q), id: ConnectionId) -> bool {
    _, alive := hm.get(&signal.connections, id)
    return alive
}

SignalConnectionCount :: proc(signal: ^$S/Signal($T, $N, $Q)) -> (count: int) {
    for i in 0 ..< signal.order_count {
        _, alive := hm.get(&signal.connections, signal.order[i])
        if alive { count += 1 }
    }
    return
}

// While blocked emits do nothing (set_block_signals). Deferred calls that are waiting are still delivered by SignalFlush.
SignalSetBlocked :: proc(signal: ^$S/Signal($T, $N, $Q), blocked: bool) {
    signal.blocked = blocked
}

SignalIsBlocked :: proc(signal: ^$S/Signal($T, $N, $Q)) -> bool {
    return signal.blocked
}

// Tell everyone who listens. Returns how many callbacks ran now: deferred ones are queued and counted when they run.
SignalEmit :: proc(signal: ^$S/Signal($T, $N, $Q), payload: T) -> (called: int) {
    if signal.blocked { return }
    signal.emitting += 1
    count: u32 = signal.order_count     // what is connected from inside a callback is for the next emit
    for i in 0 ..< count {
        connection, alive := hm.get(&signal.connections, signal.order[i])
        if !alive { continue }
        if .DEFERRED in connection.flags {
            signalQueue(signal, connection.handle, payload)
            continue
        }
        // copied first: the connection may be removed (one shot, or by the callback itself) before the call
        callback: proc(payload: T, user: rawptr) = connection.callback
        user: rawptr = connection.user
        if .ONE_SHOT in connection.flags { _ = hm.remove(&signal.connections, connection.handle) }
        callback(payload, user)
        called += 1
    }
    signal.emitting -= 1
    if signal.emitting == 0 { signalCompact(signal) }
    return
}

// Deliver the deferred calls, call it where Godot would be idle: once per frame, after the update. Calls queued by the callbacks
// themselves wait for the next flush. Returns how many callbacks ran.
SignalFlush :: proc(signal: ^$S/Signal($T, $N, $Q)) -> (called: int) {
    waiting: u32 = signal.pending_count
    for _ in 0 ..< waiting {
        entry: Pending(T) = signal.pending[signal.pending_head]
        signal.pending_head = (signal.pending_head + 1) % u32(Q)
        signal.pending_count -= 1

        connection, alive := hm.get(&signal.connections, entry.id)
        if !alive { continue }          // disconnected while it waited
        callback: proc(payload: T, user: rawptr) = connection.callback
        user: rawptr = connection.user
        if .ONE_SHOT in connection.flags { _ = hm.remove(&signal.connections, connection.handle) }
        callback(entry.payload, user)
        called += 1
    }
    if signal.emitting == 0 { signalCompact(signal) }
    return
}

// How many deferred calls were lost because the queue was full
SignalDroppedCount :: proc(signal: ^$S/Signal($T, $N, $Q)) -> int {
    return int(signal.dropped)
}

SignalPendingCount :: proc(signal: ^$S/Signal($T, $N, $Q)) -> int {
    return int(signal.pending_count)
}

@(private)
signalFind :: proc(signal: ^$S/Signal($T, $N, $Q), callback: proc(payload: T, user: rawptr), user: rawptr) -> (id: ConnectionId, found: bool) {
    for i in 0 ..< signal.order_count {
        connection, alive := hm.get(&signal.connections, signal.order[i])
        if alive && connection.callback == callback && connection.user == user { return connection.handle, true }
    }
    return
}

// Take the ids of removed connections out of the order list. Not while emitting: the positions are in use then.
@(private)
signalCompact :: proc(signal: ^$S/Signal($T, $N, $Q)) {
    kept: u32 = 0
    for i in 0 ..< signal.order_count {
        id: ConnectionId = signal.order[i]
        _, alive := hm.get(&signal.connections, id)
        if !alive { continue }
        signal.order[kept] = id
        kept += 1
    }
    for i in kept ..< signal.order_count { signal.order[i] = {} }
    signal.order_count = kept
}

@(private)
signalQueue :: proc(signal: ^$S/Signal($T, $N, $Q), id: ConnectionId, payload: T) {
    if signal.pending_count >= u32(Q) {
        signal.dropped += 1
        return
    }
    slot: u32 = (signal.pending_head + signal.pending_count) % u32(Q)
    signal.pending[slot] = {id = id, payload = payload}
    signal.pending_count += 1
}
