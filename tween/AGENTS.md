# tween: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `tween.odin` (Tween + Step builder + `TweenUpdate`), `tween_value.odin` (property types), `tween_system.odin` (static pool `TweenSystem($N)`, `System*` procs), `tween_test.odin` (`odin test .`).
- Zero allocations: fixed step array per Tween, handle-map pool. Demos in `demo_raylib/` (raylib) and `demo_karl2d/game/` follow the same state pattern as tilemap.
