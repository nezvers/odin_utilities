package verlet2d

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