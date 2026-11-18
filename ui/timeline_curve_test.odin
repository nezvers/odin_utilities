#+build !js
package ui

import "core:testing"

@(test)
test_every_shape_starts_at_0_ends_at_1_and_never_goes_backwards :: proc(t: ^testing.T) {
    shapes: [5]CurveShape = {.LINEAR, .HOLD, .SMOOTH, .CURVE, .S_CURVE}
    curves: [7]f32 = {-1, -0.7, -0.2, 0, 0.2, 0.7, 1}
    for shape in shapes {
        for curve in curves {
            testing.expect_value(t, CurveEval(shape, curve, 0), 0)
            testing.expect_value(t, CurveEval(shape, curve, 1), 1)
            previous: f32 = 0
            for i in 0 ..= 200 {
                value: f32 = CurveEval(shape, curve, f32(i) / 200)
                testing.expectf(t, value >= previous - 1e-6 && value >= 0 && value <= 1.000001, "%v %v at %d: %v after %v", shape, curve, i, value, previous)
                previous = value
            }
        }
    }
}

@(test)
test_the_shapes_have_the_form_they_are_named_for :: proc(t: ^testing.T) {
    near :: proc(a: f32, b: f32) -> bool { return abs(a - b) < 1e-5 }
    testing.expect(t, near(CurveEval(.LINEAR, 0.9, 0.3), 0.3), "linear has no bend")
    testing.expect(t, CurveEval(.HOLD, 0, 0.99) == 0 && CurveEval(.HOLD, 0, 1) == 1, "hold keeps the first value until the end")
    testing.expect(t, near(CurveEval(.SMOOTH, 0, 0.5), 0.5) && near(CurveEval(.SMOOTH, 0, 0.25), 0.15625), "3x^2 - 2x^3")
    // CURVE: 0 is a line, above 0 goes fast first (above the line), below 0 starts slowly (under the line)
    testing.expect(t, near(CurveEval(.CURVE, 0, 0.3), 0.3))
    testing.expect(t, CurveEval(.CURVE, 0.6, 0.3) > 0.3 && CurveEval(.CURVE, 0.6, 0.8) > 0.8)
    testing.expect(t, CurveEval(.CURVE, -0.6, 0.3) < 0.3 && CurveEval(.CURVE, -0.6, 0.8) < 0.8)
    // the amount asked for: 0.5 + 0.5 * curve is the number a of the bias; the bias of 0.5 is a (the curve passes through (0.5, a))
    testing.expect(t, near(CurveEval(.CURVE, 0.6, 0.5), 0.8), "the bias at the middle is its shape number")
    // S_CURVE: symmetric around the middle, steeper there for curve > 0, flat there for curve < 0
    for x in ([4]f32{0.1, 0.25, 0.4, 0.5}) {
        testing.expect(t, near(CurveEval(.S_CURVE, 0.5, x) + CurveEval(.S_CURVE, 0.5, 1 - x), 1), "point symmetric")
    }
    testing.expect(t, CurveEval(.S_CURVE, 0.6, 0.25) < 0.25 && CurveEval(.S_CURVE, 0.6, 0.75) > 0.75)
    testing.expect(t, CurveEval(.S_CURVE, -0.6, 0.25) > 0.25 && CurveEval(.S_CURVE, -0.6, 0.75) < 0.75)
    testing.expect(t, near(CurveEval(.S_CURVE, 0, 0.3), 0.3))
    // the limit keeps a curve of 1 from being a jump (no division by zero, a finite value)
    testing.expect(t, CurveEval(.CURVE, 1, 0.01) <= 1 && CurveEval(.CURVE, -1, 0.99) >= 0)
    testing.expect_value(t, CurveShapeNext(.LINEAR), CurveShape.SMOOTH)
    s: CurveShape = .LINEAR
    for _ in 0 ..< 5 { s = CurveShapeNext(s) }
    testing.expect_value(t, s, CurveShape.LINEAR)                       // a full turn
}

@(test)
test_a_segment_becomes_straight_pieces_that_end_at_the_next_point :: proc(t: ^testing.T) {
    out: [128]Vec2
    a: Vec2 = {10, 100}
    b: Vec2 = {210, 20}
    line := CurveSegmentPoints(.LINEAR, 0, a, b, out[:])
    testing.expect(t, len(line) == 1 && line[0] == b)
    hold := CurveSegmentPoints(.HOLD, 0, a, b, out[:])
    testing.expect(t, len(hold) == 2 && hold[0] == Vec2{210, 100} && hold[1] == b, "across, then up")
    for shape in ([3]CurveShape{.SMOOTH, .CURVE, .S_CURVE}) {
        curved := CurveSegmentPoints(shape, 0.5, a, b, out[:])
        testing.expect(t, len(curved) >= 4 && len(curved) <= 64)
        testing.expect_value(t, curved[len(curved) - 1], b)
        for i in 1 ..< len(curved) {
            testing.expect(t, curved[i].x > curved[i - 1].x && curved[i].y <= curved[i - 1].y, "forward in time, up in value (the screen y goes down)")
        }
    }
    narrow := CurveSegmentPoints(.SMOOTH, 0, {0, 0}, {3, 10}, out[:])
    testing.expect_value(t, len(narrow), 4)                              // at least 4 pieces
    wide := CurveSegmentPoints(.SMOOTH, 0, {0, 0}, {5000, 10}, out[:])
    testing.expect_value(t, len(wide), 64)                               // at most 64
    short_buffer: [2]Vec2
    cut := CurveSegmentPoints(.CURVE, 0.5, a, b, short_buffer[:])
    testing.expect_value(t, len(cut), 2)                                 // as many as fit, never past the buffer
}

@(test)
test_the_handle_of_a_segment_is_where_the_curve_is_and_gives_the_curve_back :: proc(t: ^testing.T) {
    for shape in ([2]CurveShape{.CURVE, .S_CURVE}) {
        for curve in ([6]f32{-0.9, -0.5, -0.1, 0.2, 0.6, 0.9}) {
            along, covered := CurveHandle(shape, curve)
            testing.expect(t, along == 0.5 || shape == .S_CURVE)
            back: f32 = CurveFromHandle(shape, covered)
            testing.expectf(t, abs(back - curve) < 1e-4, "%v %v: the handle at %v gives %v back", shape, curve, covered, back)
        }
    }
    along, covered := CurveHandle(.LINEAR, 0)
    testing.expect(t, along == 0.5 && covered == 0.5)
}
