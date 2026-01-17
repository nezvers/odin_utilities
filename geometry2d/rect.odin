package geometry2d

// pos = x, y
// size = z, w
Rect::[4]f32

RectNew::proc(pos:vec2, size:vec2)->Rect{
	return {pos.x, pos.y, size.x, size.y}
}

RectMiddle::proc(r:Rect)->vec2{
	pos:vec2 = r.xy
	size:vec2 = r.zw
	return {pos.x, pos.y} + (size * {0.5, 0.5})
}

// Get line segment from top side of rectangle
RectTop::proc(r:Rect)->Line{
	pos:vec2 = r.xy
	size:vec2 = r.zw
	return LineNew({pos.x, pos.y}, {pos.x + size.x, pos.y})
}

// Get line segment from bottom side of rectangle
RectBottom::proc(r:Rect)->Line{
	pos:vec2 = r.xy
	size:vec2 = r.zw
	return LineNew({pos.x, pos.y + size.y}, pos + size)
}

// Get line segment from left side of rectangle
RectLeft::proc(r:Rect)->Line{
	pos:vec2 = r.xy
	size:vec2 = r.zw
	return LineNew({pos.x, pos.y}, {pos.x, pos.y + size.y})
}

// Get line segment from right side of rectangle
RectRight::proc(r:Rect)->Line{
	pos:vec2 = r.xy
	size:vec2 = r.zw
	return LineNew({pos.x + size.x, pos.y}, pos + size)
}

// Get a line from an indexed side, starting top, going clockwise
RectSide::proc(r:Rect, i:u32)->Line{
	list: = [4]proc(Rect)->Line{RectTop, RectRight, RectBottom, RectLeft}
	return list[i](r)
}

// Get area of rectangle
RectArea::proc(r:Rect)->f32{
	return r.z * r.w
}

// Get perimeter of rectangle
RectPerimeter::proc(r:Rect)->f32{
	return 2.0 * (r.z + r.w)
}

// Returns side count: 4
RectSideCount::proc(r:Rect)->u32{
	return 4
}



