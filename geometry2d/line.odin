package geometry2d

// start = x,y
// end = z, w
Line :: [4]f32

line2D_new::proc(start:vec2, end:vec2)->Line{
	return Line{start.x, start.y, end.x, end.y}
}

// Get vector pointing from start to end
line_vector :: proc(l: Line) -> vec2 {
	start:vec2 = l.xy
	end:vec2 = l.zw
	return {
		end.x - start.x,
		end.y - start.y,
	}
}

// Get length of line
line_length :: proc(l: Line) -> f32 {
	vector:vec2 = line_vector(l)
	return vec2_mag(vector)
}

// Get length of line^2
line_length2 :: proc(l: Line) -> f32 {
	vector:vec2 = line_vector(l)
	return vec2_mag2(vector)
}

// Given a real distance, get point with normalized direction
line_point_norm :: proc(l: Line, distance:f32) -> vec2 {
	vector:vec2 = line_vector(l)
	return l.xy + vec2_norm(vector) * distance
}

// Given a real distance, get point with line multiplier
line_point_mult :: proc(l: Line, multiplier:f32) -> vec2 {
	vector:vec2 = line_vector(l)
	return l.xy + vector * multiplier
}

// Return which side of the line does a point lie
line_side :: proc(l: Line, p:vec2) -> i32 {
	vector:vec2 = line_vector(l)
	cross:f32 = vec2_cross(vector, p - l.xy)
	
	if (cross > epsilon){
		return 1
	} else if (cross < -epsilon){
		return -1
	} else{
		return 0
	}
}

// Returns line equation "mx + a" coefficients where:
// NOTE: Returns {inf, inf} if abs(end.x - start.x) < epsilon:
line_coefficients :: proc(l:Line) -> vec2{
	x1: = l.x
	x2: = l.z
	y1: = l.y
	y2: = l.w

	if (abs(x1 - x2) < epsilon){
		return {INF_F32, INF_F32}
	}
	m: = (y2 - y1) / (x2 - x1)
	return {m, -m * x1 + y1}
}


