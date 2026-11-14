package box2d_odin

import b2 "vendor:box2d"
import "core:sync"
import "core:testing"

Vec2 :: b2.Vec2

Rect :: struct {
    x:f32,
    y:f32,
    w:f32,
    h:f32,
}

// Add to sensor ShapeId.userData
Sensor :: struct($T: typeid) {
    entity: rawptr,
    kind: T,
    shape:b2.ShapeId,
}

// Add to ShapeId.userData
Contact :: struct($T: typeid) {
    entity: rawptr,
    kind: T, // bit flags recommended
}

// convert a rectangle corner position to box2D center position
pos_to_b2 :: proc(pos: Vec2, size: Vec2) -> b2.Vec2 {
	return {pos.x + size.x * 0.5, -pos.y - size.y * 0.5}
}

// convert a box2D center position to corner position
b2_to_pos :: proc(pos: b2.Vec2, size: Vec2) -> Vec2 {
	return {pos.x - size.x * 0.5, -pos.y - size.y * 0.5}
}

// --- Tests ---

// Box2D keeps world creation and the random generator in global state, so tests that use them take turns
@(private)
test_box2d_lock: sync.Mutex

@(test)
test_position_conversion_round_trip :: proc(t: ^testing.T) {
    size: Vec2 = {4, 6}
    center: b2.Vec2 = pos_to_b2({10, 20}, size)
    testing.expect_value(t, center, b2.Vec2{12, -23})                                      // the centre of the rectangle, y flipped
    testing.expect_value(t, b2_to_pos(center, size), Vec2{10, 20})                         // and back to the corner

    testing.expect_value(t, b2_to_pos(pos_to_b2({-3, 7}, {10, 2}), {10, 2}), Vec2{-3, 7})
    testing.expect_value(t, b2_to_pos(pos_to_b2({5, 5}, {}), {}), Vec2{5, 5})              // a point has no size to account for
}
