package geometry2d

// pos = x, y
// size = z, w
Rect::[4]f32

rect_new::proc(pos:vec2, size:vec2)->Rect{
	return {pos.x, pos.y, size.x, size.y}
}

rect_middle::proc(r:Rect)->vec2{
	pos:vec2 = r.xy
	size:vec2 = r.zw
	return {pos.x, pos.y} + (size * {0.5, 0.5})
}

// Get line segment from top side of rectangle
rect_top::proc(r:Rect)->Line{
	pos:vec2 = r.xy
	size:vec2 = r.zw
	return LineNew({pos.x, pos.y}, {pos.x + size.x, pos.y})
}

// Get line segment from bottom side of rectangle
rect_bottom::proc(r:Rect)->Line{
	pos:vec2 = r.xy
	size:vec2 = r.zw
	return LineNew({pos.x, pos.y + size.y}, pos + size)
}

// Get line segment from left side of rectangle
rect_left::proc(r:Rect)->Line{
	pos:vec2 = r.xy
	size:vec2 = r.zw
	return LineNew({pos.x, pos.y}, {pos.x, pos.y + size.y})
}

// Get line segment from right side of rectangle
rect_right::proc(r:Rect)->Line{
	pos:vec2 = r.xy
	size:vec2 = r.zw
	return LineNew({pos.x + size.x, pos.y}, pos + size)
}

// Get a line from an indexed side, starting top, going clockwise
rect_side::proc(r:Rect, i:u32)->Line{
	list: = [4]proc(Rect)->Line{rect_top, rect_right, rect_bottom, rect_left}
	return list[i](r)
}

// Get area of rectangle
rect_area::proc(r:Rect)->f32{
	return r.z * r.w
}

// Get perimeter of rectangle
rect_perimeter::proc(r:Rect)->f32{
	return 2.0 * (r.z + r.w)
}

// Returns side count: 4
rect_side_count::proc(r:Rect)->u32{
	return 4
}



