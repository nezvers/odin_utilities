# Forward and Backward Reaching Inverse Kinematic

### Example
`odin run demo`

```ruby
fabrik::proc(point_list:[]vec2, length_buffer:[]f32, target_pos:vec2, max_itterations:int, error_treshold:f32)
```

Usable internal algorithms
```ruby
total_length:f32 = fabrik.calculate_lengths(point_list[:], length_buffer[:])
fabrik.pull_back(point_list[:], length_buffer[:], mouse_position)
```

Influenced by - https://zalo.github.io/blog/constraints/