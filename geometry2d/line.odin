package geometry2d

// start = x,y
// end = z, w
Line :: [4]f32

LineNew::proc(start:vec2, end:vec2)->Line{
	return Line{start.x, start.y, end.x, end.y}
}

// Get vector pointing from start to end
LineVector :: proc(l: Line) -> vec2 {
	start:vec2 = l.xy
	end:vec2 = l.zw
	return {
		end.x - start.x,
		end.y - start.y,
	}
}

// Get length of line
LineLength :: proc(l: Line) -> f32 {
	vector:vec2 = LineVector(l)
	return Vec2Mag(vector)
}

// Get length of line^2
LineLength2 :: proc(l: Line) -> f32 {
	vector:vec2 = LineVector(l)
	return Vec2Mag2(vector)
}

// Given a real distance, get point with normalized direction
LinePointNormal :: proc(l: Line, distance:f32) -> vec2 {
	vector:vec2 = LineVector(l)
	return l.xy + Vec2Norm(vector) * distance
}

// Given a real distance, get point with line multiplier
LinePointMult :: proc(l: Line, multiplier:f32) -> vec2 {
	vector:vec2 = LineVector(l)
	return l.xy + vector * multiplier
}

// Return which side of the line does a point lie
LineSide :: proc(l: Line, p:vec2) -> i32 {
	vector:vec2 = LineVector(l)
	cross:f32 = Vec2Cross(vector, p - l.xy)
	
	if (cross > epsilon){
		return 1
	} else if (cross < -epsilon){
		return -1
	} else{
		return 0
	}
}

// Returns line equation "mx + a" coefficients where:
// NOTE: Returns {inf, inf} if distance < epsilon:
LineCoeficient :: proc(l:Line) -> vec2{
	x1: = l.x
	x2: = l.z
	y1: = l.y
	y2: = l.w

	if (Abs(x1 - x2) < epsilon){
		return {INF_F32, INF_F32}
	}
	m: = (y2 - y1) / (x2 - x1)
	return {m, -m * x1 + y1}
}


