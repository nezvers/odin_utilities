# Forward and Backward Reaching Inverse Kinematic

### Example
`odin run demo_raylib`

```ruby
fabrik::proc(point_list:[]vec2, length_buffer:[]f32, target_pos:vec2, max_itterations:int, error_treshold:f32)
```

Usable internal algorithms
```ruby
total_length:f32 = fabrik.calculate_lengths(point_list[:], length_buffer[:])
fabrik.pull_back(point_list[:], length_buffer[:], mouse_position)
```

Influenced by - https://zalo.github.io/blog/constraints/

## Demos and tests
`odin run demo_raylib`, `odin run demo_karl2d` (Karl2D needs to be next to the other libraries): the same demos from `demo_common`, written once against the
demo kit (`odin_utilities/demo_kit`). Each demo has a script of simulated input with checks:
`odin test demo_common -strict-style -vet` plays it headless, `odin run demo_raylib -define:DEMO_TEST=true` plays it in the window.
