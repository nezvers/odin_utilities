package geometry2d

Triangle::[3]vec2

TriangleNew::proc(p0:vec2, p1:vec2, p2:vec2)->Triangle{
	return {p0, p1, p2}
}

// Get a line from an indexed side, starting top, going clockwise
TriangleSide::proc(Triangle:Triangle, i:u32)->Line{
	return LineNew(Triangle[i % 3], Triangle[(i +1) % 3])
}

// Get area of Triangle
TriangleArea::proc(Triangle:Triangle)->f32{
	return 0.5 * abs( (Triangle[0].x * (Triangle[1].y - Triangle[2].y)) + (Triangle[1].x * (Triangle[2].y - Triangle[0].y)) + (Triangle[2].x * (Triangle[0].y - Triangle[1].y)) )
}

// Get perimeter of Triangle
TrianglePerimeter::proc(Triangle:Triangle)->f32{
	l1:f32 = LineLength(LineNew(Triangle[0], Triangle[1]))
	l2:f32 = LineLength(LineNew(Triangle[1], Triangle[2]))
	l3:f32 = LineLength(LineNew(Triangle[2], Triangle[0]))
	return l1 + l2 + l3
}

// Returns side count: 3
TriangleSizeCount::proc(Triangle:Triangle)->u32{
	return 3
}

