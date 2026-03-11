package box2d_odin

import b2 "vendor:box2d"

Vec2 :: b2.Vec2

Rect :: struct {
    x:f32,
    y:f32,
    w:f32,
    h:f32,
}

// Add to sensor ShapeId.userData
Sensor :: struct {
    entity: rawptr,
    kind: u32,
    shape:b2.ShapeId,
}

// Add to ShapeId.userData
Contact :: struct {
    entity: rawptr,
    kind: u32, // bit flags recommended
}

// convert a rectangle corner position to box2D center position
pos_to_b2 :: proc(pos: Vec2, size: Vec2) -> b2.Vec2 {
	return {pos.x + size.x * 0.5, -pos.y - size.y * 0.5}
}

// convert a box2D center position to corner position
b2_to_pos :: proc(pos: b2.Vec2, size: Vec2) -> Vec2 {
	return {pos.x - size.x * 0.5, -pos.y - size.y * 0.5}
}