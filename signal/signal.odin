package signal

// Godot style signals: an object announces that something happened, anyone can listen, neither knows the other.
//
//     HealthChange :: struct { old, new: f32 }
//     Hud :: struct { bar: ^Bar }                                  // what a listener wants to get back: the "bound" value
//     health_changed: Signal(HealthChange, 8, 16, size_of(Hud))   // payload, connections, deferred emissions waiting, bytes of bound
//
//     SignalConnect(&health_changed, on_health, Hud{bar})                    // on_health :: proc(change: HealthChange, hud: Hud)
//     SignalConnect(&health_changed, on_any_change)                          // proc(change: HealthChange)
//     SignalConnect(&health_changed, on_first_hit, flags = {.ONE_SHOT})      // disconnects itself before the call
//     SignalConnect(&health_changed, on_log, Log{...}, {.DEFERRED})          // called later by SignalFlush
//     SignalEmit(&health_changed, {old = 100, new = 80})
//
// Callable of Godot:   connect(callable.bind(args))  ->  the bound value, a struct of your own, given after the payload
//                      callable.unbind(n)            ->  a callback that takes fewer parameters
//                      callable with the signal's args and the bound ones: proc(payload, bound), proc(payload), proc(bound), proc()
// What the callback takes is checked when you compile: SignalConnect is generic, a callback of another shape, a bound value that does
// not fit or does not match is a compile error that says what was expected (the compiler adds the types and the line of the call).
//
// Godot signals map:   connect / emit / disconnect / is_connected / set_block_signals
//                      -> SignalConnect / SignalEmit / SignalDisconnect / SignalIsConnected / SignalSetBlocked
//                      CONNECT_ONE_SHOT, CONNECT_DEFERRED -> .ONE_SHOT, .DEFERRED (deferred: SignalFlush is the idle frame)
//                      the object is freed, its connections go -> an Owner, see below
//                      signal with several arguments -> a struct as the payload
//
// Memory: nothing allocates. The connections live in a handle map of fixed size inside the Signal and the bound value is copied into
// the connection, BOUND bytes of it (the 4th parameter of Signal, as small as you need, default none). A ConnectionId is a handle
// (index + generation): the id of a connection that is gone is refused even if its slot was reused. Connecting past the capacity
// fails instead of growing. Callbacks are called in the order they were connected.
//
// Safe while emitting, like in Godot: a callback may disconnect itself or others (a disconnected one is not called later in the same
// emit), may connect new ones (they are called from the next emit) and may emit the same signal again.
//
// Dangling pointers. The bound value is a copy, so a pointer inside of it can outlive what it points to. Three ways to stay safe:
//   1. Bind a handle or an index instead of a pointer, and look it up when called: a stale handle finds nothing and the callback
//      does nothing (a handle map refuses an old generation). This is the way that cannot go wrong.
//   2. Give the connection an Owner (any non zero u64: a handle, an id of a scene run) and call SignalDisconnectOwner when the owner
//      goes. Your own Owner id can also be checked on every emit: set signal.owner_alive, a connection whose owner is not alive
//      anymore is removed instead of called.
//   3. Bind pointers to memory that lives as long as the signal (game memory, a scene arena) and disconnect when that ends.
//
// Hot reload. A connection holds proc pointers, which point into the code, and that code is replaced by a reload. The data of the
// signal stays (connections, order, waiting deferred calls, bound values) when it lives in the game memory, only the procs have to
// be given again, and that is what a Key is for: a connection made with a Key can be found again after the reload.
//
//     after the reload:   SignalRebindBegin(&s)                              // every connection is waiting for its new code
//                         SignalRebind(&s, on_health, Hud{bar}, key = KEY_HUD)    // the same arguments as SignalConnect: new procs, new bound
//                         ...
//                         SignalDisconnectStale(&s)                          // what the new code does not know any more is removed
//
// SignalRebind only updates a connection that exists, it does not create one: a one shot that already fired stays gone. A connection
// without a Key cannot be found again, it is removed by SignalDisconnectStale. Until it is rebound a connection is skipped by
// SignalEmit and SignalFlush, nothing calls into the old code.
//
// Builds for js_wasm32, the tests are in signal_test.odin.

import "base:intrinsics"
import "base:runtime"
import hm "core:container/handle_map"

ConnectionId :: distinct hm.Handle32

// Finds a connection again after a hot reload, and makes SignalConnect refuse the same one twice. 0: none
Key :: distinct u32

// Who a connection belongs to, see SignalDisconnectOwner. 0: nobody
Owner :: distinct u64

// Pack a handle (up to 8 bytes) as an Owner
OwnerOf :: proc(handle: $H) -> Owner where size_of(H) <= size_of(Owner) {
    value: Owner = 0
    handle := handle
    signalCopy(&value, &handle, size_of(H))
    return value
}

ConnectFlag :: enum u8 {
    ONE_SHOT,       // disconnected right before its first call
    DEFERRED,       // not called by SignalEmit, the payload waits in the queue of the signal until SignalFlush
}
ConnectFlags :: bit_set[ConnectFlag; u8]

// Payload for a signal that carries nothing, and the bound value of a connection that has none
Empty :: struct {}

// A signal with BOUND bytes holds that much for the bound value of each connection
BoundStorage :: struct($BOUND: uint) #align(16) {
    data: [BOUND]u8,
}

Connection :: struct($T: typeid, $BOUND: uint) {
    handle: ConnectionId,                       // the handle map needs this field
    call: proc(callback: rawptr, payload: T, bound: rawptr),    // made for the types of the connection, it puts them back
    callback: rawptr,
    flags: ConnectFlags,
    stale: bool,                                // waits for SignalRebind after a hot reload
    key: Key,
    owner: Owner,
    bound_size: u32,
    bound: BoundStorage(BOUND),
}

Pending :: struct($T: typeid) {
    id: ConnectionId,
    payload: T,
}

// T: the payload of the signal. N: how many connections at most. Q: how many deferred calls can wait for SignalFlush (1 when nothing
// is deferred). BOUND: bytes of the bound value of a connection, the biggest one you bind (0: none). The zero value is a signal
// without connections.
Signal :: struct($T: typeid, $N: uint, $Q: uint, $BOUND: uint = 0)
    where N > 0, Q > 0 {
    connections: hm.Static_Handle_Map(N + 1, Connection(T, BOUND), ConnectionId),     // + 1: slot 0 is the empty handle
    order: [N]ConnectionId,         // ids in the order they were connected: the handle map reuses slots, it does not keep order
    order_count: u32,               // while emitting, disconnected ids stay in it (skipped) so the positions do not move
    emitting: u32,                  // depth of SignalEmit, emits can be nested
    blocked: bool,
    pending: [Q]Pending(T),         // ring of deferred calls
    pending_head: u32,
    pending_count: u32,
    dropped: u32,                   // deferred calls lost because the queue was full
    // Optional: is the owner of a connection still there. A connection of an owner that is gone is removed when emitting reaches it.
    // A proc is code, set it again after a hot reload.
    owner_alive: proc(owner: Owner) -> bool,
}

// Listen. SignalConnect(&signal, callback, bound, flags, key, owner), `bound` can be left out. `callback` is one of proc(payload: T, bound: B), proc(payload: T), proc(bound: B), proc(), B is the type of `bound`.
// Returns ok = false when the capacity is full, when the same connection exists already (the same Key, or without a Key the same
// callback with the same bound bytes), or when called while emitting and the list has no room left.
SignalConnect :: proc{signalConnectBound, signalConnectPlain}

@(private)
signalConnectPlain :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), callback: $C, flags: ConnectFlags = {}, key: Key = 0, owner: Owner = 0) -> (id: ConnectionId, ok: bool) {
    return signalConnectBound(signal, callback, Empty{}, flags, key, owner)
}

@(private)
signalConnectBound :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), callback: $C, bound: $B, flags: ConnectFlags = {}, key: Key = 0, owner: Owner = 0) -> (id: ConnectionId, ok: bool) {
    #assert(size_of(B) <= BOUND, "SignalConnect: the bound value is bigger than the Signal has room for. Declare the signal with more bytes: Signal(T, N, Q, size_of(YourBound)) (the types are in the 'instantiated as' lines, the last one is your call)")
    #assert(align_of(B) <= 16, "SignalConnect: the bound value needs a bigger alignment than 16 bytes (the types are in the 'instantiated as' lines, the last one is your call)")
    #assert(intrinsics.type_is_proc(C), "SignalConnect: `callback` is not a proc. Expected proc(payload: T, bound: B), proc(payload: T), proc(bound: B) or proc() (the types are in the 'instantiated as' lines, the last one is your call)")
    assert(callback != nil)
    call: proc(callback: rawptr, payload: T, bound: rawptr) = signalTrampoline(T, C, B)
    callback_pointer: rawptr = cast(rawptr)callback

    if key != 0 {
        if _, found := signalFindKey(signal, key); found { return }
    } else if signalIsConnectedBound(signal, callback_pointer, bound) {
        return
    }
    if signal.emitting == 0 { signalCompact(signal) }
    if signal.order_count >= u32(N) { return }
    added: ConnectionId
    added, ok = hm.add(&signal.connections, Connection(T, BOUND){})
    if !ok { return }
    connection: ^Connection(T, BOUND) = hm.get(&signal.connections, added)
    signalFill(connection, call, callback_pointer, bound, flags, key, owner)
    signal.order[signal.order_count] = added
    signal.order_count += 1
    return added, true
}

// ------------------------------------------------------------------------------------------------------------------------
// Hot reload

// Mark every connection as waiting for its new procs. Until SignalRebind gives them they are skipped by SignalEmit and SignalFlush.
// The owner_alive check is code too, set it again.
SignalRebindBegin :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND)) {
    signal.owner_alive = nil
    for i in 0 ..< signal.order_count {
        connection, alive := hm.get(&signal.connections, signal.order[i])
        if alive { connection.stale = true }
    }
}

// Give the connection with this Key its procs and bound value from the new code. The arguments are the ones of SignalConnect, a
// Key is required. It keeps the id, the place in the order and the waiting deferred calls. False when there is no such connection
// (it was a one shot that fired, or was disconnected): nothing is created.
SignalRebind :: proc{signalRebindBound, signalRebindPlain}

@(private)
signalRebindPlain :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), callback: $C, flags: ConnectFlags = {}, key: Key, owner: Owner = 0) -> bool {
    return signalRebindBound(signal, callback, Empty{}, flags, key, owner)
}

@(private)
signalRebindBound :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), callback: $C, bound: $B, flags: ConnectFlags = {}, key: Key, owner: Owner = 0) -> bool {
    #assert(size_of(B) <= BOUND, "SignalRebind: the bound value is bigger than the Signal has room for. Declare the signal with more bytes: Signal(T, N, Q, size_of(YourBound)) (the types are in the 'instantiated as' lines, the last one is your call)")
    #assert(align_of(B) <= 16, "SignalRebind: the bound value needs a bigger alignment than 16 bytes (the types are in the 'instantiated as' lines, the last one is your call)")
    #assert(intrinsics.type_is_proc(C), "SignalRebind: `callback` is not a proc. Expected proc(payload: T, bound: B), proc(payload: T), proc(bound: B) or proc() (the types are in the 'instantiated as' lines, the last one is your call)")
    assert(callback != nil)
    assert(key != 0, "SignalRebind needs the Key the connection was made with")
    existing, found := signalFindKey(signal, key)
    if !found { return false }
    signalFill(existing, signalTrampoline(T, C, B), cast(rawptr)callback, bound, flags, key, owner)
    return true
}

// Remove what the new code did not give its procs back to. Returns how many were removed.
SignalDisconnectStale :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND)) -> (removed: int) {
    for i in 0 ..< signal.order_count {
        connection, alive := hm.get(&signal.connections, signal.order[i])
        if !alive || !connection.stale { continue }
        _ = hm.remove(&signal.connections, signal.order[i])
        removed += 1
    }
    if signal.emitting == 0 { signalCompact(signal) }
    return
}

// How many connections wait for SignalRebind
SignalStaleCount :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND)) -> (count: int) {
    for i in 0 ..< signal.order_count {
        connection, alive := hm.get(&signal.connections, signal.order[i])
        if alive && connection.stale { count += 1 }
    }
    return
}

// ------------------------------------------------------------------------------------------------------------------------

// Stop listening. False when the id is not a connection of this signal (anymore).
SignalDisconnect :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), id: ConnectionId) -> bool {
    if !hm.remove(&signal.connections, id) { return false }
    if signal.emitting == 0 { signalCompact(signal) }
    return true
}

// Stop listening by the Key it was made with
SignalDisconnectKey :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), key: Key) -> bool {
    existing, found := signalFindKey(signal, key)
    if !found { return false }
    return SignalDisconnect(signal, existing.handle)
}

// Stop listening by the callback: every connection that calls it
SignalDisconnectCallback :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), callback: $C) -> (removed: int) {
    #assert(intrinsics.type_is_proc(C), "SignalDisconnectCallback: `callback` is not a proc (the types are in the 'instantiated as' lines, the last one is your call)")
    callback_pointer: rawptr = cast(rawptr)callback
    for i in 0 ..< signal.order_count {
        connection, alive := hm.get(&signal.connections, signal.order[i])
        if !alive || connection.callback != callback_pointer { continue }
        _ = hm.remove(&signal.connections, signal.order[i])
        removed += 1
    }
    if signal.emitting == 0 { signalCompact(signal) }
    return
}

// Remove every connection of one owner: what an object does when it is freed in Godot. Returns how many were removed.
SignalDisconnectOwner :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), owner: Owner) -> (removed: int) {
    if owner == 0 { return }
    for i in 0 ..< signal.order_count {
        connection, alive := hm.get(&signal.connections, signal.order[i])
        if !alive || connection.owner != owner { continue }
        _ = hm.remove(&signal.connections, signal.order[i])
        removed += 1
    }
    if signal.emitting == 0 { signalCompact(signal) }
    return
}

// Remove everything, also what waits in the deferred queue
SignalDisconnectAll :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND)) {
    for i in 0 ..< signal.order_count {
        _ = hm.remove(&signal.connections, signal.order[i])
    }
    signal.pending_count = 0
    signal.pending_head = 0
    if signal.emitting == 0 { signalCompact(signal) }
}

// Is this callback connected, with any bound value
SignalIsConnected :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), callback: $C) -> bool {
    #assert(intrinsics.type_is_proc(C), "SignalIsConnected: `callback` is not a proc (the types are in the 'instantiated as' lines, the last one is your call)")
    callback_pointer: rawptr = cast(rawptr)callback
    for i in 0 ..< signal.order_count {
        connection, alive := hm.get(&signal.connections, signal.order[i])
        if alive && connection.callback == callback_pointer { return true }
    }
    return false
}

SignalIsKeyConnected :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), key: Key) -> bool {
    _, found := signalFindKey(signal, key)
    return found
}

// Is this connection still there. An id is checked with its generation, the slot of a removed connection may hold another one now.
SignalIsConnectionValid :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), id: ConnectionId) -> bool {
    _, alive := hm.get(&signal.connections, id)
    return alive
}

SignalConnectionCount :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND)) -> (count: int) {
    for i in 0 ..< signal.order_count {
        _, alive := hm.get(&signal.connections, signal.order[i])
        if alive { count += 1 }
    }
    return
}

// While blocked emits do nothing (set_block_signals). Deferred calls that are waiting are still delivered by SignalFlush.
SignalSetBlocked :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), blocked: bool) {
    signal.blocked = blocked
}

SignalIsBlocked :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND)) -> bool {
    return signal.blocked
}

// Tell everyone who listens. Returns how many callbacks ran now: deferred ones are queued and counted when they run.
SignalEmit :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), payload: T) -> (called: int) {
    if signal.blocked { return }
    signal.emitting += 1
    count: u32 = signal.order_count     // what is connected from inside a callback is for the next emit
    for i in 0 ..< count {
        connection, alive := hm.get(&signal.connections, signal.order[i])
        if !alive || connection.stale { continue }
        if signalOwnerGone(signal, connection) {
            _ = hm.remove(&signal.connections, connection.handle)
            continue
        }
        if .DEFERRED in connection.flags {
            signalQueue(signal, connection.handle, payload)
            continue
        }
        signalCall(signal, connection, payload)
        called += 1
    }
    signal.emitting -= 1
    if signal.emitting == 0 { signalCompact(signal) }
    return
}

// Deliver the deferred calls, call it where Godot would be idle: once per frame, after the update. Calls queued by the callbacks
// themselves wait for the next flush. Returns how many callbacks ran.
SignalFlush :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND)) -> (called: int) {
    waiting: u32 = signal.pending_count
    for _ in 0 ..< waiting {
        entry: Pending(T) = signal.pending[signal.pending_head]
        signal.pending_head = (signal.pending_head + 1) % u32(Q)
        signal.pending_count -= 1

        connection, alive := hm.get(&signal.connections, entry.id)
        if !alive || connection.stale { continue }      // disconnected while it waited, or the code is being replaced
        if signalOwnerGone(signal, connection) {
            _ = hm.remove(&signal.connections, connection.handle)
            continue
        }
        signalCall(signal, connection, entry.payload)
        called += 1
    }
    if signal.emitting == 0 { signalCompact(signal) }
    return
}

// How many deferred calls were lost because the queue was full
SignalDroppedCount :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND)) -> int {
    return int(signal.dropped)
}

SignalPendingCount :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND)) -> int {
    return int(signal.pending_count)
}

// ------------------------------------------------------------------------------------------------------------------------

// The proc that puts the types back: the callback and the bound value are stored without their types, this one knows them. Made
// when you connect, from the callback and the bound value you passed, so the two cannot disagree.
@(private)
signalTrampoline :: proc($T: typeid, $C: typeid, $B: typeid) -> proc(callback: rawptr, payload: T, bound: rawptr) {
    PARAMETERS :: intrinsics.type_proc_parameter_count(C)
    when intrinsics.type_proc_return_count(C) != 0 {
        #panic("SignalConnect: the callback returns something. A callback is proc(payload: T, bound: B), proc(payload: T), proc(bound: B) or proc(), without a result (the types are in the 'instantiated as' lines, the last one is your call)")
    } else when PARAMETERS == 2 {
        when intrinsics.type_proc_parameter_type(C, 0) != T {
            #panic("SignalConnect: the first parameter of the callback has to be the payload type of the signal: proc(payload: T, bound: B) (the types are in the 'instantiated as' lines, the last one is your call)")
        } else when intrinsics.type_proc_parameter_type(C, 1) != B {
            #panic("SignalConnect: the second parameter of the callback has to be the type of the bound value you pass: proc(payload: T, bound: B) (the types are in the 'instantiated as' lines, the last one is your call)")
        } else {
            return proc(callback: rawptr, payload: T, bound: rawptr) {
                (cast(C)callback)(payload, (cast(^B)bound)^)
            }
        }
    } else when PARAMETERS == 1 {
        when B == Empty && intrinsics.type_proc_parameter_type(C, 0) == T {
            return proc(callback: rawptr, payload: T, bound: rawptr) {
                (cast(C)callback)(payload)
            }
        } else when B != Empty && intrinsics.type_proc_parameter_type(C, 0) == B {
            return proc(callback: rawptr, payload: T, bound: rawptr) {
                (cast(C)callback)((cast(^B)bound)^)
            }
        } else when B == Empty {
            #panic("SignalConnect: a callback with one parameter and no bound value has to take the payload type of the signal: proc(payload: T) (the types are in the 'instantiated as' lines, the last one is your call)")
        } else {
            #panic("SignalConnect: a callback with one parameter and a bound value has to take the type of the bound value: proc(bound: B) (the types are in the 'instantiated as' lines, the last one is your call)")
        }
    } else when PARAMETERS == 0 {
        return proc(callback: rawptr, payload: T, bound: rawptr) {
            (cast(C)callback)()
        }
    } else {
        #panic("SignalConnect: a callback takes at most 2 parameters: proc(payload: T, bound: B) (the types are in the 'instantiated as' lines, the last one is your call)")
    }
}

// Write the arguments of SignalConnect into a connection. The bytes of the bound value are copied, the rest of the room is zero
@(private)
signalFill :: proc(connection: ^Connection($T, $BOUND), call: proc(callback: rawptr, payload: T, bound: rawptr), callback: rawptr, bound: $B, flags: ConnectFlags, key: Key, owner: Owner) {
    connection.call = call
    connection.callback = callback
    connection.flags = flags
    connection.key = key
    connection.owner = owner
    connection.stale = false
    connection.bound_size = u32(size_of(B))
    signalZero(&connection.bound, size_of(connection.bound))
    bound := bound
    signalCopy(&connection.bound, &bound, size_of(B))
}

// Call a connection. The one shot is removed first, the callback may connect again. The bound value is read by the trampoline before
// the callback starts, so removing or reusing the connection from inside of the callback does not change what it gets.
@(private)
signalCall :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), connection: ^Connection(T, BOUND), payload: T) {
    call: proc(callback: rawptr, payload: T, bound: rawptr) = connection.call
    callback: rawptr = connection.callback
    bound: BoundStorage(BOUND) = connection.bound
    if .ONE_SHOT in connection.flags { _ = hm.remove(&signal.connections, connection.handle) }
    call(callback, payload, &bound)
}

@(private)
signalOwnerGone :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), connection: ^Connection(T, BOUND)) -> bool {
    return connection.owner != 0 && signal.owner_alive != nil && !signal.owner_alive(connection.owner)
}

@(private)
signalFindKey :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), key: Key) -> (connection: ^Connection(T, BOUND), found: bool) {
    for i in 0 ..< signal.order_count {
        candidate, alive := hm.get(&signal.connections, signal.order[i])
        if alive && candidate.key == key { return candidate, true }
    }
    return
}

// Same callback and the same bound bytes. Padding inside of the bound struct is copied as it was, a struct with garbage in its
// padding looks different: zero the struct first (`bound := Hud{}`) when it matters.
@(private)
signalIsConnectedBound :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), callback: rawptr, bound: $B) -> bool {
    bound := bound
    for i in 0 ..< signal.order_count {
        connection, alive := hm.get(&signal.connections, signal.order[i])
        if !alive || connection.key != 0 || connection.callback != callback { continue }
        if connection.bound_size != u32(size_of(B)) { continue }
        if signalEqual(&connection.bound, &bound, size_of(B)) { return true }
    }
    return false
}

// Take the ids of removed connections out of the order list. Not while emitting: the positions are in use then.
@(private)
signalCompact :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND)) {
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
signalQueue :: proc(signal: ^$S/Signal($T, $N, $Q, $BOUND), id: ConnectionId, payload: T) {
    if signal.pending_count >= u32(Q) {
        signal.dropped += 1
        return
    }
    slot: u32 = (signal.pending_head + signal.pending_count) % u32(Q)
    signal.pending[slot] = {id = id, payload = payload}
    signal.pending_count += 1
}

// The memory procs are used by generic procs only, which do not count as a use of the import until they are instantiated: these
// small ones make `odin check -vet` of the package itself happy
@(private)
signalCopy :: proc(destination, source: rawptr, size: int) {
    runtime.mem_copy(destination, source, size)
}

@(private)
signalZero :: proc(destination: rawptr, size: int) {
    runtime.mem_zero(destination, size)
}

@(private)
signalEqual :: proc(a, b: rawptr, size: int) -> bool {
    return runtime.memory_equal(a, b, size)
}
