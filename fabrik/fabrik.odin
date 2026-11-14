// Forward and Backward Reach Inverse Kinematics
package fabrik
import "core:testing"
import "core:math"

// point_list - set of points that are moved. 0th point is kept in place.
// length_buffer - used to populate magnitude between points, need to be at least _point_count - 1
fabrik::proc(point_list:[]vec2, length_buffer:[]f32, target_pos:vec2, max_itterations:int, error_treshold:f32){
    _point_count:int = len(point_list)
    assert(_point_count > 1)
    assert(len(length_buffer) >= _point_count - 1)
    
    _total_length:f32 = calculate_lengths(point_list, length_buffer)
    _length_to_target:f32 = vec2_mag({target_pos.x - point_list[0].x, target_pos.y - point_list[0].y})
    
    if _total_length < _length_to_target{
        // Too far, just straighten
        _dir:vec2 = vec2_norm({target_pos.x - point_list[0].x, target_pos.y - point_list[0].y})
        stretch(point_list, length_buffer, _dir)
        return
    }
    
    for _ in 0..<max_itterations{
        fabrik_itteration(point_list, length_buffer, target_pos, point_list[0])
        _error_length:f32 = vec2_mag({target_pos.x - point_list[0].x, target_pos.y - point_list[0].y})
        if _error_length < error_treshold{
            break
        }
    }
}


// give a list of points to populate buffer with length between points
calculate_lengths::proc(point_list:[]vec2, length_buffer:[]f32)->(total_length:f32){
    _point_count:int = len(point_list)
    assert(_point_count > 1)
    assert(len(length_buffer) >= _point_count - 1)
    
    for i in 0..<_point_count-1{
        _distance:vec2 = {point_list[i+1].x - point_list[i].x, point_list[i+1].y - point_list[i].y}
        _length:f32 = vec2_mag(_distance)
        total_length += _length
        length_buffer[i] = _length
    }
    return
}

// Stretch points in direction_normal starting from 0 as root
stretch::proc(point_list:[]vec2, length_buffer:[]f32, direction_normal:vec2){
    _point_count:int = len(point_list)
    assert(_point_count > 1)
    assert(len(length_buffer) >= _point_count - 1)
        
    for i in 1..<_point_count{
        _length:f32 = length_buffer[i -1]
        _offset:vec2 = {direction_normal.x * _length, direction_normal.y * _length}
        point_list[i] = {point_list[i - 1].x + _offset.x, point_list[i - 1].y + _offset.y}
    }
    return
}

// One itteration of Forward and Backward Reach Inverse Kinematics
fabrik_itteration::proc(point_list:[]vec2, length_buffer:[]f32, target_pos:vec2, end_position:vec2){
    pull_front(point_list, length_buffer, target_pos)
    pull_back(point_list, length_buffer, end_position)
    return
}

// Pull Back end 0th point as rope segments
pull_back::proc(point_list:[]vec2, length_buffer:[]f32, pos:vec2){
    _point_count:int = len(point_list)
    assert(_point_count > 1)
    assert(len(length_buffer) >= _point_count - 1)
    
    _p:vec2 = pos
    for i in 0..<_point_count-1{
        _length:f32 = length_buffer[i]
        
        _distance_target:vec2 = {point_list[i+1].x - _p.x, point_list[i+1].y - _p.y}
        _dir:vec2 = vec2_norm(_distance_target)
        
        point_list[i] = _p
        _p = {_p.x + _dir.x * _length, _p.y + _dir.y * _length}
    }
    point_list[_point_count-1] = _p
    return
}

// Pull front end (len-1)-th point as rope segments
pull_front::proc(point_list:[]vec2, length_buffer:[]f32, pos:vec2){
    _point_count:int = len(point_list)
    assert(_point_count > 1)
    assert(len(length_buffer) >= _point_count - 1)

    _last:int = _point_count-1
    _p:vec2 = pos
    for i in 0..<_point_count-1{
        _length:f32 = length_buffer[_last - i - 1]

        _distance_target:vec2 = {point_list[_last - i - 1].x - _p.x, point_list[_last - i - 1].y - _p.y}
        _dir:vec2 = vec2_norm(_distance_target)

        point_list[_last - i] = _p
        _p = {_p.x + _dir.x * _length, _p.y + _dir.y * _length}
    }
    point_list[0] = _p
    return
}

// --- Tests ---

@(private="file")
chain_lengths_hold :: proc(points: []vec2, lengths: []f32) -> bool {
    for i in 0 ..< len(points) - 1 {
        if abs(vec2_mag(points[i + 1] - points[i]) - lengths[i]) > 1e-3 { return false }
    }
    return true
}

@(test)
test_fabrik_lengths_and_stretch :: proc(t: ^testing.T) {
    points: [4]vec2 = {{0, 0}, {3, 4}, {3, 4 + 2}, {3, 4 + 2 + 1}}
    lengths: [3]f32
    total: f32 = calculate_lengths(points[:], lengths[:])
    testing.expect_value(t, lengths, [3]f32{5, 2, 1})
    testing.expect_value(t, total, f32(8))

    stretch(points[:], lengths[:], {1, 0})
    testing.expect_value(t, points, [4]vec2{{0, 0}, {5, 0}, {7, 0}, {8, 0}})
}

@(test)
test_fabrik_reaches_a_target_within_range :: proc(t: ^testing.T) {
    points: [4]vec2 = {{0, 0}, {1, 0}, {2, 0}, {3, 0}}
    lengths: [3]f32
    fabrik(points[:], lengths[:], {1.5, 1.5}, 32, 0.001)

    testing.expect_value(t, points[0], vec2{0, 0})                         // the root never moves
    testing.expect(t, vec2_mag(points[3] - vec2{1.5, 1.5}) < 0.01, "the tip reaches the target")
    testing.expect(t, chain_lengths_hold(points[:], lengths[:]), "every segment keeps its length")
}

@(test)
test_fabrik_straightens_toward_an_unreachable_target :: proc(t: ^testing.T) {
    points: [3]vec2 = {{0, 0}, {1, 1}, {2, 0}}
    lengths: [2]f32
    fabrik(points[:], lengths[:], {0, 100}, 8, 0.001)
    testing.expect(t, vec2_mag(points[2] - vec2{0, 2 * math.SQRT_TWO}) < 1e-3, "points straight at the target")
    testing.expect(t, abs(points[1].x) < 1e-3 && points[1].y > 0, "and the middle joint is on the line")
}

@(test)
test_fabrik_pull_passes :: proc(t: ^testing.T) {
    points: [3]vec2 = {{0, 0}, {1, 0}, {2, 0}}
    lengths: [2]f32 = {1, 1}

    pull_back(points[:], lengths[:], {0, 5})                               // drag the root, the rest follows
    testing.expect_value(t, points[0], vec2{0, 5})
    testing.expect(t, chain_lengths_hold(points[:], lengths[:]))

    pull_front(points[:], lengths[:], {4, 4})                              // drag the tip
    testing.expect_value(t, points[2], vec2{4, 4})
    testing.expect(t, chain_lengths_hold(points[:], lengths[:]))
}
