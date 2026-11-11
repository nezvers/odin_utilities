# Grid collision map
Uniform grid broad phase and simple AABB narrow phase for 2D. Designed to not allocate: size of the grid, boxes per cell and collider count are compile time parameters, all memory is inside of the `GridMap` value (put it in a global or your own struct).    

`odin run demo` / `odin run demo_karl2d` / `odin test .`    
Demo: screen covering 80x45 grid of 16x16 cells. LMB paint wall (gray), RMB erase, MMB or `E` place player (8x16, lime), `WASD` move at 200 px/s with collision.    

```odin
import gcm "grid_collision_map"

// 80 columns, 45 rows, 8 handles per cell, 4096 colliders (usable 4095)
world: gcm.GridMap(80, 45, 8, 4096)
buffer: [64]gcm.Handle  // query results

gcm.GridMapInit(&world, {0, 0}, {16, 16})
wall, ok := gcm.GridMapAdd(&world, {32, 32, 16, 16})
player, _ := gcm.GridMapAdd(&world, {100, 100, 8, 16})

// every frame
result, _ := gcm.GridMapMoveAndSlide(&world, player, direction * 200 * dt, buffer[:])
count := gcm.GridMapQuery(&world, rect, buffer[:], player)   // overlapping colliders, ignoring player
```

## Parts
- `Collider` - rect + `ptr` for your data. Stored in `core:container/handle_map`, so a `Handle` stays safe after removal.
- `Slot` - fixed list of collider Handles for one cell. A collider is stored in every cell it touches.
- `GridMapAdd` / `Remove` / `Get` / `Move` - fail (return false) instead of growing when a cell or the map is full, nothing is changed.
- `GridMapQueryBroad` - Handles of colliders sharing cells with a rect (unique, not checked for overlap).
- `GridMapQuery` - broad phase + `RectOverlaps` narrow phase.
- `GridMapMoveAndSlide` - moves axis by axis and stops on colliders so it slides along walls. Movement is split into steps smaller than half a cell, so thin colliders can't be skipped.
- `RectOverlaps`, `RectContainsPoint`, `RectPushOut` - narrow phase helpers.

## Notes
- Colliders outside of the grid are clamped into border cells. The grid has no walls of its own.
- Touching edges are not overlapping.
- Results are limited by the size of the buffer you pass.
- Everything is solid; layers/masks and static vs dynamic separation are not implemented.
