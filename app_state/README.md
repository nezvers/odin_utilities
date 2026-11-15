# App State

A state machine of procs: `AppState{enter, exit, update, draw, name}` and `AppStateChange(&current, &new_state)`, which exits the state being left and enters the new one. Any proc may be nil. Plain data, no allocations.
Tests: `odin test app_state -strict-style -vet`.

## Demos and tests
`odin run demo_raylib`, `odin run demo_karl2d` (Karl2D needs to be next to the other libraries): the same demos from `demo_common`, written once against the
demo kit (`odin_utilities/demo_kit`). Each demo has a script of simulated input with checks:
`odin test demo_common -strict-style -vet` plays it headless, `odin run demo_raylib -define:DEMO_TEST=true` plays it in the window.
