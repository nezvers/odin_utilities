#+build !js
package ui

import "core:math"
import "core:testing"

@(test)
test_every_shape_starts_at_0_ends_at_1_and_never_goes_backwards :: proc(t: ^testing.T) {
    shapes: [6]CurveShape = {.LINEAR, .HOLD, .SMOOTH, .CURVE, .S_CURVE, .EXP}  // the counted shapes have their own test
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
    for _ in 0 ..< 12 { s = CurveShapeNext(s) }
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

@(test)
test_the_shapes_that_repeat_count_and_keep_their_ends :: proc(t: ^testing.T) {
    near :: proc(a, b: f32) -> bool { return abs(a - b) < 1e-4 }
    testing.expect_value(t, CurveCount(0), 1)
    testing.expect_value(t, CurveCount(1), 30)                           // limited to the same 0.98 as the bends
    testing.expect_value(t, CurveCount(0.5), 8)
    for shape in ([5]CurveShape{.STAIRS, .SMOOTH_STAIRS, .PULSE, .TRIANGLE, .WAVE}) {
        for curve in ([5]f32{0, 0.3, 0.6, 0.98, -0.5}) {
            testing.expectf(t, CurveEval(shape, curve, 1) == 1 || near(CurveEval(shape, curve, 1), 1), "%v %v ends at the second value", shape, curve)
            if shape != .PULSE || curve >= 0 { testing.expectf(t, near(CurveEval(shape, curve, 0), 0), "%v %v starts at the first value", shape, curve) }
            for i in 0 ..= 200 {
                v: f32 = CurveEval(shape, curve, f32(i) / 200)
                testing.expectf(t, v >= -1e-4 && v <= 1 + 1e-4, "%v %v stays between the values: %v", shape, curve, v)
            }
        }
    }
    // stairs: 4 steps at curve 0.37 (count 1 + int(0.1369 * 31.5) = 5): five steps, the last one is the end value
    count: int = CurveCount(0.37)
    levels: map[f32]bool
    defer delete(levels)
    for i in 0 ..< 1000 { levels[CurveEval(.STAIRS, 0.37, f32(i) / 1000)] = true }
    testing.expect_value(t, len(levels), count)
    // pulse: two values only, below 0 it starts high
    testing.expect(t, CurveEval(.PULSE, 0.6, 0.01) == 0 && CurveEval(.PULSE, -0.6, 0.01) == 1)
    // triangle: goes there and back an odd number of times: one run at 0 is the line
    testing.expect(t, near(CurveEval(.TRIANGLE, 0, 0.3), 0.3) && near(CurveEval(.WAVE, 0, 0.5), 0.5))
    testing.expect(t, near(CurveEval(.TRIANGLE, 0.5, 0.5 / 15), 0.5), "8 cycles: 15 runs, half way of the first run")
    // smooth stairs are monotonic and eased inside a step
    previous: f32
    for i in 0 ..= 400 {
        v: f32 = CurveEval(.SMOOTH_STAIRS, 0.5, f32(i) / 400)
        testing.expect(t, v >= previous - 1e-6)
        previous = v
    }
    // the handle of a counted shape gives its number back
    _, covered := CurveHandle(.STAIRS, 0.6)
    testing.expect(t, near(CurveFromHandle(.STAIRS, covered), 0.6))
    testing.expect(t, !CurveHasHandle(.HOLD) && CurveHasHandle(.PULSE))
}

@(test)
test_the_exponential_grows_by_a_constant_ratio_and_is_a_line_at_zero :: proc(t: ^testing.T) {
    near :: proc(a, b: f32) -> bool { return abs(a - b) < 1e-4 }
    testing.expect(t, near(CurveEval(.EXP, 0, 0.3), 0.3), "0 is a line")
    testing.expect(t, near(CurveEval(.EXP, 0.00001, 0.3), 0.3), "a hair above 0 is a line")
    testing.expect(t, CurveEval(.EXP, 0.6, 0.5) < 0.5 && CurveEval(.EXP, -0.6, 0.5) > 0.5, "above 0 grows late, below 0 early")
    // the shape is e^(c x) with the offset and scale that put the ends at 0 and 1: the ratio of the growth of two equal steps is the same everywhere
    c: f32 = CURVE_EXP_RANGE * 0.5
    offset: f32 = 1 / (math.exp(c) - 1)
    a, b, d, e: f32 = CurveEval(.EXP, 0.5, 0.2) + offset, CurveEval(.EXP, 0.5, 0.3) + offset, CurveEval(.EXP, 0.5, 0.6) + offset, CurveEval(.EXP, 0.5, 0.7) + offset
    testing.expect(t, abs(b / a - e / d) < 1e-3, "equal steps in x multiply by the same ratio")
    // the handle at the middle gives the curve back
    for curve in ([5]f32{-0.9, -0.3, 0.1, 0.5, 0.95}) {
        _, covered := CurveHandle(.EXP, curve)
        testing.expectf(t, abs(CurveFromHandle(.EXP, covered) - curve) < 2e-3, "the handle of %v gives %v back", curve, CurveFromHandle(.EXP, covered))
    }
}

@(test)
test_the_hermite_cubic_has_the_slopes_it_is_given_and_stays_between_the_values :: proc(t: ^testing.T) {
    near :: proc(a, b: f32) -> bool { return abs(a - b) < 1e-4 }
    for x in ([5]f32{0, 0.2, 0.5, 0.8, 1}) {
        testing.expect(t, near(CurveEvalTangents(0, 0, x), x * x * (3 - 2 * x)), "no slopes: the smooth step")
        testing.expect(t, near(CurveEvalTangents(1, 1, x), x), "the slope of the line at both ends: the line")
    }
    for start in ([4]f32{0, 0.5, 1.5, 3}) {
        for end in ([4]f32{0, 0.7, 2, 3}) {
            testing.expect_value(t, CurveEvalTangents(start, end, 0), 0)
            testing.expect(t, near(CurveEvalTangents(start, end, 1), 1))
            previous: f32
            for i in 0 ..= 200 {
                value: f32 = CurveEvalTangents(start, end, f32(i) / 200)
                testing.expectf(t, value >= previous - 1e-5 && value >= -1e-5 && value <= 1 + 1e-5, "%v %v at %d: %v after %v", start, end, i, value, previous)
                previous = value
            }
            // the slope at the ends, by a small step
            testing.expectf(t, abs((CurveEvalTangents(start, end, 0.0001) - 0) / 0.0001 - start) < 0.01, "slope at 0 is %v", start)
            testing.expectf(t, abs((1 - CurveEvalTangents(start, end, 0.9999)) / 0.0001 - end) < 0.01, "slope at 1 is %v", end)
        }
    }
    // the handles are the control points of the Bezier curve: a third of the way, at the height of the slope
    positions, count := CurveHandles(.HERMITE, 0, {2, 0.5}, {0, 100}, {90, 40})
    testing.expect_value(t, count, 2)
    testing.expect(t, near(positions[0].x, 30) && near(positions[0].y, 100 + 2 * (40 - 100) / 3))
    testing.expect(t, near(positions[1].x, 60) && near(positions[1].y, 40 - 0.5 * (40 - 100) / 3))
    _, none := CurveHandles(.HOLD, 0, {}, {0, 0}, {10, 10})
    testing.expect_value(t, none, 0)
    // the line of a segment
    out: [64]Vec2
    line := CurveSegmentPoints(.HERMITE, 0, {0, 0}, {100, 100}, out[:], {1, 1})
    testing.expect(t, len(line) >= 4 && near(line[len(line) / 2 - 1].y, line[len(line) / 2 - 1].x))
}

@(test)
test_every_shape_goes_from_zero_to_one_and_the_counted_ones_are_told_apart :: proc(t: ^testing.T) {
    for shape in CurveShape {
        testing.expect_value(t, CurveIsCounted(shape), shape >= .STAIRS)
        if shape == .HOLD { continue }                                        // a step stays at 0 until the next point
        // a counted shape takes the number of repeats there, the others the bend
        coefficients: [3]f32 = {1, 3, 8} if CurveIsCounted(shape) else {0, 0.3, 0.7}
        for coefficient in coefficients {
            low: f32 = CurveEvalCoefficient(shape, coefficient, 0)
            high: f32 = CurveEvalCoefficient(shape, coefficient, 1)
            if !CurveIsCounted(shape) || shape == .STAIRS || shape == .SMOOTH_STAIRS {
                testing.expectf(t, abs(low) < 0.001, "%v starts at 0 (%v at %v)", shape, low, coefficient)
                testing.expect(t, abs(high - 1) < 0.001, "and ends at 1")           // the pulse, the triangle and the wave return to where they started
            }
            middle: f32 = CurveEvalCoefficient(shape, coefficient, 0.5)
            testing.expect(t, middle >= -1.01 && middle <= 2.01, "stays near the range")
        }
    }
    testing.expect_value(t, CurveEvalCoefficient(.LINEAR, 0, 0.25), 0.25)
    testing.expect_value(t, CurveEvalCoefficient(.HOLD, 0, 0.99), 0)
}
