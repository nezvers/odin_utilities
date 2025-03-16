// Forward and Backward Reach Inverse Kinematics
package constrains


// point_list - set of points that are moved. 0th point is kept in place.
// length_buffer - used to populate magnitude between points, need to be at least _point_count - 1
fabrik::proc(point_list:[]vec2, length_buffer:[]f32, target_pos:vec2, max_itterations:int, error_treshold:f32){
    _point_count:int = len(point_list)
    assert(_point_count > 1)
    assert(len(length_buffer) >= _point_count - 1)
    
    _total_length:f32 = calculate_lengths(point_list, length_buffer)
    _length_to_target:f32 = vec2_mag({target_pos.x - point_list[_point_count - 1].x, target_pos.y - point_list[_point_count - 1].y})
    
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

stretch::proc(point_list:[]vec2, length_buffer:[]f32, direction_normal:vec2){
    _point_count:int = len(point_list)
    assert(_point_count > 1)
    assert(len(length_buffer) >= _point_count - 1)
    
    _last:int = _point_count-1
    
    for i in 0..<_point_count-1{
        _length:f32 = length_buffer[_last - i -1]
        // fmt.println("%v: %v", i, _distance)
        _offset:vec2 = {direction_normal.x * _length, direction_normal.y * _length}
        point_list[_last - i - 1] = {point_list[_last - i].x + _offset.x, point_list[_last - i].y + _offset.y}
    }
    return
}

// One itteration of Forward and Backward Reach Inverse Kinematics
fabrik_itteration::proc(point_list:[]vec2, length_buffer:[]f32, target_pos:vec2, end_position:vec2){
    pull_front(point_list, length_buffer, target_pos)
    pull_back(point_list, length_buffer, end_position)
    return
}

// Pull Back end as rope segments
pull_back::proc(point_list:[]vec2, length_buffer:[]f32, pos:vec2){
    _point_count:int = len(point_list)
    assert(_point_count > 1)
    assert(len(length_buffer) >= _point_count - 1)
    
    _p:vec2 = pos
    for i in 0..<_point_count-1{
        _length:f32 = length_buffer[i]
        // fmt.println("%v: %v", i, _distance)
        
        _distance_target:vec2 = {point_list[i+1].x - _p.x, point_list[i+1].y - _p.y}
        _dir:vec2 = vec2_norm(_distance_target)
        
        point_list[i] = _p
        _p = {_p.x + _dir.x * _length, _p.y + _dir.y * _length}
    }
    point_list[_point_count-1] = _p
    return
}

// Pull front end as rope segments
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
