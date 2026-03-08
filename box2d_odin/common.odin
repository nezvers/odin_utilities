package box2d_odin

import b2 "vendor:box2d"

vec2 :: [2]f32

Rect :: struct {
    x:f32,
    y:f32,
    w:f32,
    h:f32,
}

// convert a rectangle corner position to box2D center position
pos_to_b2 :: proc(pos: vec2, size: vec2) -> b2.Vec2 {
	return {pos.x + size.x * 0.5, -pos.y - size.y * 0.5}
}

// convert a box2D center position to corner position
b2_to_pos :: proc(pos: b2.Vec2, size: vec2) -> vec2 {
	return {pos.x - size.x * 0.5, -pos.y - size.y * 0.5}
}