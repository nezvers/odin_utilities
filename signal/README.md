# Signal

Godot style signals with the `Callable` features (bound values, fewer parameters). Generic over the payload type, the number of
connections, the size of the deferred queue and the size of the bound value. No allocations: connections live in a
`core:container/handle_map` inside the `Signal`, a `ConnectionId` is a handle (index + generation) so an id of a removed connection is
refused even if its slot was reused. Full capacity fails instead of growing.

```odin
HealthChange :: struct { old, new: f32 }
Hud :: struct { bar: ^Bar }                                           // the bound value: what the listener wants back
health_changed: signal.Signal(HealthChange, 8, 16, size_of(Hud))      // payload, connections, deferred waiting, bytes of bound

signal.SignalConnect(&health_changed, on_health, Hud{bar})                      // proc(change: HealthChange, hud: Hud)
signal.SignalConnect(&health_changed, on_any_change)                            // proc(change: HealthChange)
signal.SignalConnect(&health_changed, on_first_hit, flags = {.ONE_SHOT})        // disconnects itself before the call
signal.SignalConnect(&health_changed, on_log, Log{}, {.DEFERRED})               // queued, called by SignalFlush
signal.SignalEmit(&health_changed, {old = 100, new = 80})
signal.SignalFlush(&health_changed)                                             // once per frame: Godot's idle
```

| Godot | here |
|---|---|
| `connect`, `emit`, `disconnect` | `SignalConnect`, `SignalEmit`, `SignalDisconnect` (also `...Key`, `...Callback`, `...Owner`, `...All`) |
| `is_connected`, `set_block_signals` | `SignalIsConnected`, `SignalIsConnectionValid`, `SignalSetBlocked` |
| `CONNECT_ONE_SHOT`, `CONNECT_DEFERRED` | `.ONE_SHOT`, `.DEFERRED` |
| `callable.bind(args)` | the bound value, any struct that fits the `BOUND` bytes of the signal, given after the payload |
| `callable.unbind(n)` | a callback with fewer parameters: `proc(payload, bound)`, `proc(payload)`, `proc(bound)`, `proc()` |
| object freed, connections go | an `Owner`, see below |
| several arguments | a struct as the payload, `signal.Empty` for none |

## Mistakes are compile errors
`SignalConnect` is generic: the callback that is called later is made from the callback and the bound value you pass now, so they cannot
disagree. A wrong shape does not compile, with a message that says what was expected, and the compiler adds the types and the line of your call:

```
signal.odin(379:13) Error: Compile time panic: SignalConnect: the first parameter of the callback has to be the payload type of the signal: proc(payload: T, bound: B) (the types are in the 'instantiated as' lines, the last one is your call)
	Called within 'signalTrampoline' :: proc($T=Hit, $C=proc(f32, int), $B=int) -> proc(rawptr, Hit, rawptr)
	main.odin(8:19) instantiated as 'signalConnectBound($S=Signal($T=Hit, $N=4, $Q=4, $BOUND=8), ... $C=proc(f32, int), $B=int)'
```
Also checked: a bound value bigger than the signal has room for (`Signal(T, N, Q, size_of(YourBound))`), a callback that returns something,
more than two parameters. A bound value has to have a type: write `int(3)`, not `3`.

## Dangling pointers
The bound value is a copy, so a pointer inside of it can outlive what it points to.
1. Bind a **handle or index** and look it up when called. A stale handle finds nothing and the callback does nothing. The one that cannot go wrong.
2. Give the connection an **`Owner`** (any non zero `u64`, `OwnerOf(handle)` packs a handle) and `SignalDisconnectOwner` when it goes.
   Or set `signal.owner_alive`: a connection whose owner is gone is removed when emitting reaches it, never called.
3. Bind pointers to memory that lives as long as the signal (game memory, a scene arena).

## Hot reload
A connection holds proc pointers into the code, and a reload replaces the code. The data stays when the signal lives in the game memory
(connections, order, waiting deferred calls, bound values), the procs are given again, found by the `Key` the connection was made with:

```odin
signal.SignalConnect(&s, on_health, hud, key = KEY_HUD)       // when created

// after the reload:
signal.SignalRebindBegin(&s)                                  // every connection waits for its new code, nothing calls the old one
signal.SignalRebind(&s, on_health, hud, key = KEY_HUD)        // same arguments as SignalConnect: new procs, new bound value
signal.SignalDisconnectStale(&s)                              // what the new code does not know any more
```
`SignalRebind` only updates a connection that exists: a one shot that fired stays gone, a connection that was switched off stays off.
Ids, order and the deferred calls that were waiting are kept. A connection without a `Key` cannot be found again and is removed by `SignalDisconnectStale`.
`owner_alive` is code too: set it again.

Callbacks run in connection order. Safe while emitting: a callback can disconnect itself or others (a disconnected one is not called later in
the same emit), connect new ones (called from the next emit) and emit the same signal again.
The same connection twice is refused: the same `Key`, or without a key the same callback with the same bound bytes (zero a bound struct before filling it when it has padding).

`odin test signal -strict-style -vet`

### Demos and tests
`odin run demo_raylib`, `odin run demo_karl2d` (Karl2D needs to be next to the other libraries): the same demo from `demo_common`, written against the demo kit.
A health bar with three listeners (bar, red flash, deferred log) and a one shot one. Space damage, H heal, R revive, 1/2/3 connect and disconnect a listener,
B block the signal, F rebind everything the way a hot reload does.
`odin test signal/demo_common` plays the demo with simulated input and checks (headless), `-define:DEMO_TEST=true` plays it in the window.
