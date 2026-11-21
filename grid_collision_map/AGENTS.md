# grid_collision_map: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `grid_collision_map.odin` (`GridMap($X,$Y,$N,$C)`: colliders in `hm.Static_Handle_Map`, per cell fixed `Slot` of Handles; `GridMap*` procs, `Rect*` narrow phase helpers), `grid_collision_map_test.odin` (`odin test .`). Demos in `demo_raylib/` and `demo_karl2d/game/` (`demo_collision.odin`).
- Same "fixed buffers, fail instead of grow" rule as tilemap/tween.
