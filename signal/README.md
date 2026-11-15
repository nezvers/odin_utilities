# Signal

Godot style signals: an object announces that something happened, anyone can listen, neither knows the other.
Generic over the payload type, the number of connections and the size of the deferred queue. No allocations: connections live in a
`core:container/handle_map` inside the `Signal`, a `ConnectionId` is a handle (index + generation) so an id of a removed connection is refused
even if its slot was reused. Full capacity fails instead of growing.

```odin
HealthChange :: struct { old, new: f32 }
health_changed: signal.Signal(HealthChange, 8, 16)           // payload, connections, deferred emissions waiting

signal.SignalConnect(&health_changed, on_health, &hud)                       // proc(payload: HealthChange, user: rawptr)
signal.SignalConnect(&health_changed, on_first_hit, nil, {.ONE_SHOT})        // disconnects itself before the call
signal.SignalConnect(&health_changed, on_log, &log, {.DEFERRED})             // queued, called by SignalFlush
signal.SignalEmit(&health_changed, {old = 100, new = 80})
signal.SignalFlush(&health_changed)                                          // once per frame: Godot's idle
```

| Godot | here |
|---|---|
| `connect`, `emit`, `disconnect` | `SignalConnect`, `SignalEmit`, `SignalDisconnect` (also `...Callback`, `...User`, `...All`) |
| `is_connected`, `set_block_signals` | `SignalIsConnected`, `SignalIsConnectionValid`, `SignalSetBlocked` |
| `CONNECT_ONE_SHOT`, `CONNECT_DEFERRED` | `.ONE_SHOT`, `.DEFERRED` |
| `bind(args)` | the `user` pointer |
| object freed, connections go | `SignalDisconnectUser(&signal, object)` |
| several arguments | a struct as the payload, `signal.Empty` for none |

Callbacks run in connection order. Safe while emitting: a callback can disconnect itself or others (a disconnected one is not called later in
the same emit), connect new ones (called from the next emit) and emit the same signal again. The same callback with the same user twice is
refused, like Godot.

A connection holds a proc, a pointer into the code: after a hot reload call `SignalDisconnectAll` and connect again.

`odin test signal -strict-style -vet`

### Demos
`odin run demo_raylib`, `odin run demo_karl2d` (Karl2D needs to be next to the other libraries). A health bar with three listeners
(bar, red flash, deferred log) and a one shot one. Space damage, H heal, R revive, 1/2/3 connect and disconnect a listener, B block the signal.
Shared logic is in `demo_common`.
