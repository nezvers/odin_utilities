# Constrains

Set of algorithms for constraining points
Influenced by - https://zalo.github.io/blog/constraints/

## Forward and Backward Reaching Inverse Kinematic

### Example
```ruby
fabrik::proc(point_list:[]vec2, length_buffer:[]f32, target_pos:vec2, max_itterations:int, error_treshold:f32)
```

Usable internal algorithms
```ruby
total_length:f32 = constrains.calculate_lengths(point_list[:], length_buffer[:])
constrains.pull_back(point_list[:], length_buffer[:], mouse_position)
```
