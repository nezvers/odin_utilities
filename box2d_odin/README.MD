# Box2D Odin
Abstraction and example functions for using Box2D (`vendor:box2d`), including the samples from the Box2D repository ported to Odin.    
`odin run demo_raylib` / `odin run demo_karl2d` / `odin test samples`    

Karl2D should be one directory back, next to this library.    

## Library (`package box2d_odin`)
- `world.odin`, `collider.odin`, `common.odin` - world update with sensor events, body/shape creation helpers with pixel units (used by the platformer demo).
- `helpers.odin` - shape wrappers (`AddBox`, `AddCircle`, `AddCapsule`, `AddSegment`, `AddPolygon`), `CreateGroundSegment`, `CreateBodyAt`, `CreateRevoluteAt`, `MakeShapeDef` ... the setup code that repeats in nearly every sample.
- `camera.odin` - world (meters, y up) to screen mapping, pan and zoom.
- `input.odin`, `ui.odin` - framework agnostic input snapshot and a small immediate mode UI (sliders, checkboxes, buttons) that draws through a `Backend` (rect + text).
- `sample.odin` - `Sample` descriptor, registry, `SampleHost` (browser panel, controls panel, world step, mouse joint, camera, debug drawing). `random.odin` - deterministic random like the C++ samples.
- `raylib/`, `karl2d/` - glue: `InitDebugDraw` (b2.DebugDraw with camera support). Pass `^Camera` as `userContext`, without it world units are pixels with flipped y.

## Samples (`samples/`, package `box2d_samples`)
Each file ports one `sample_*.cpp`. A sample is a set of callbacks registered with `@(init)`:
```odin
b2o.RegisterSample({category = "Bodies", name = "Pivot", create = pivot_create, draw = pivot_draw})
```
State is kept in file private globals, so nothing allocates. `odin test samples` creates and simulates every registered sample for 60 frames without a window.    
Controls in demos: LMB drag bodies, RMB/MMB drag view, wheel zoom, Left/Right arrows previous/next sample, R restart, P pause, O single step, Z reset view, Tab hide UI.

Ported so far (44 samples): Bodies (9), Stacking (10), Restitution (9), Shapes (16, Wind is missing). Not ported yet: joints, events, character/movers, collision, continuous, world, robustness, determinism, geometry, issues, benchmark, replay, car/donut/doohickey.

## Platformer demo
Coins, jump pad, pushable boxes (state `PLATFORMER` in both demos).
