# Tween
Property animation like Godot `Tween`, without allocations. Everything lives in fixed arrays, so a `Tween` can be a field in your own struct or be taken from a `TweenSystem` pool.    

`odin run demo_raylib` / `odin run demo_karl2d` / `odin test .`    

```odin
import tw "tween"

// Embedded in your own struct, no pool
tween: tw.Tween = tw.TweenMake()
tw.TweenProperty(&tween, &position, Vec2{200, 100}, 0.5, .Cubic_Out)   // from current value
tw.TweenProperty(&tween, &alpha, 0, 0.3, parallel = true)              // together with previous
tw.TweenInterval(&tween, 0.2)                                          // wait
tw.TweenCallback(&tween, proc(tween: ^tw.Tween) { /* ... */ })
tw.TweenPlay(&tween)
// every frame
tw.TweenUpdate(&tween, delta_time)

// Pool for a group, finished tweens are removed automatically
system: tw.TweenSystem(16)      // usable capacity is 15
t, ok := tw.SystemNew(&system)
tw.TweenProperty(t, &x, 10, 1)
tw.TweenPlay(t)
tw.SystemUpdate(&system, delta_time)
```

## Godot mapping
| Godot | here |
|---|---|
| `create_tween()` | `TweenMake()` or `SystemNew(&system)` |
| `tween_property(obj, "prop", final, duration)` | `TweenProperty(&tween, &prop, final, duration)` |
| `.set_trans().set_ease()` | `easing` argument, any `core:math/ease` `Ease` |
| `.set_delay()` / `.from()` / `.from_current()` / `.as_relative()` | `delay`, `from`, default, `relative` arguments |
| `.parallel()` / `set_parallel` | `parallel = true` argument or `TweenParallel(&tween)` for the next step |
| `chain()` | default, steps run one after another |
| `tween_interval` / `tween_callback` / `tween_method` | `TweenInterval` / `TweenCallback` / `TweenMethod` |
| `set_loops(n)` (0 = infinite) | `TweenSetLoops` |
| `play` / `pause` / `stop` / `kill` | `TweenPlay` / `TweenPause` / `TweenStop` / `SystemKill(&system, handle)` |
| `set_speed_scale` | `tween.speed_scale` |
| `finished` / `loop_finished` | `tween.on_finish` / `tween.on_loop` |

## Rules
- Steps are sequential, a step with `parallel` starts together with the previous one. Time left over after a step carries to the next.
- Property types: `f32`, `f64`, `i32`, `[2]f32`, `[3]f32`, `[4]f32`, `[2]i32`, `[4]u8` (Color). Pass `Color{...}`/`[4]u8` for colors if your Color is a `distinct` type, use a `[4]u8` field.
- Property pointers are stored, the target has to outlive the tween. Tweens in a `TweenSystem` need targets with stable addresses.
- Step limit per Tween is `TWEEN_STEPS_MAX` (default 8, `-define:TWEEN_STEPS_MAX=16`). `TweenProperty` and friends return `nil` when full.
- A `TweenSystem` removes finished tweens unless `tween.keep` is set. Handles of removed tweens become invalid.
