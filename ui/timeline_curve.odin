package ui

import "core:math"

// The shapes of the curve between two points of an automation, as functions: x from 0 to 1 along the segment, the answer from 0 to 1 (the part of the way from the value of the first
// point to the value of the second). One function for everything that needs them: the line the lane draws, the value the program reads for a time (TimelineAutomationValue) and
// the audio thread's block renderer (timeline_automation.odin), so what is drawn is what plays.
//
// The shapes are cheap on purpose: no pow, no exp, no log. LINEAR and HOLD are free, SMOOTH is a cubic (two multiplies and a subtract more than linear), CURVE and S_CURVE are the
// rational functions of Schlick (the bias and the gain function): one division, always monotonic, the end points are exact, and a single number says how bent the curve is.

CurveShape :: enum u8 {
    LINEAR,             // a straight line
    HOLD,               // the value of the first point until the second one: a step
    SMOOTH,             // 3x^2 - 2x^3: slow at both ends, no bend to set
    CURVE,              // Schlick's bias: `curve` above 0 goes fast first and slows down (ease out), below 0 starts slowly and speeds up (ease in), 0 is a line
    S_CURVE,            // Schlick's gain: `curve` above 0 is steeper in the middle and flat at both ends, below 0 is flat in the middle, 0 is a line
    EXP,                // an exponential: `curve` above 0 grows slowly first and fast at the end (the way pitch and decibels are heard), below 0 the other way, 0 is a line (see CURVE_EXP_RANGE)
    // The shapes that repeat: `curve` is not a bend but how many times (CurveCount: 1 to 30, growing with the square of `curve` so the small counts are easy to set).
    STAIRS,             // that many steps (at least 2) from the first value to the second
    SMOOTH_STAIRS,      // the same steps, each one eased
    PULSE,              // a square wave of that many cycles between the two values, below 0 it starts at the second value
    TRIANGLE,           // a line that goes there and back (an odd number of runs, so it ends at the second value)
    WAVE,               // the same with a cosine ease: a sine like wave
}

// The exponent of EXP at the limit of `curve`: the steepness e^8 is a factor of about 3000 between the end and the start of the curve (70 dB).
CURVE_EXP_RANGE :: f32(8)

CURVE_LIMIT :: f32(0.98)            // `curve` is kept within -CURVE_LIMIT .. CURVE_LIMIT: at 1 the bias is a jump

// The number a segment keeps for its shape (compute it once for a segment, it costs a division): the coefficient of Schlick's bias for CURVE, that of the shape number one minus it for S_CURVE
// (the gain is two such curves), 0 for the others. The bias of x for a shape number `a` in (0, 1) is x / ((1 / a - 2) * (1 - x) + 1): 0.5 is the identity, and it is the cheap form
// of x ^ (log a / log 0.5).
CurveCoefficient :: proc(shape: CurveShape, curve: f32) -> f32 {
    a: f32 = 0.5 + 0.5 * clamp(curve, -CURVE_LIMIT, CURVE_LIMIT)
    #partial switch shape {
    case .CURVE: return 1 / a - 2
    case .S_CURVE: return 1 / (1 - a) - 2
    case .EXP: return CURVE_EXP_RANGE * clamp(curve, -CURVE_LIMIT, CURVE_LIMIT)       // the exponent: (e^(c x) - 1) / (e^c - 1)
    case .STAIRS, .SMOOTH_STAIRS, .PULSE, .TRIANGLE, .WAVE:
        // the count, negative when `curve` is (the variant of a pulse)
        return f32(CurveCount(curve)) * (-1 if curve < 0 else 1)
    }
    return 0
}

// How many steps, cycles or runs a `curve` number means for the shapes that repeat (1 at 0, 30 at the limit).
CurveCount :: proc(curve: f32) -> int {
    c: f32 = clamp(curve, -CURVE_LIMIT, CURVE_LIMIT)
    return 1 + int(c * c * 31)
}

// Whether the `curve` number of a shape is a count (the shapes that repeat) and not a bend.
CurveIsCounted :: proc(shape: CurveShape) -> bool {
    return shape >= .STAIRS
}

// Whether a segment of the shape has a handle that sets its `curve` (a step has nothing to bend).
CurveHasHandle :: proc(shape: CurveShape) -> bool {
    return shape != .HOLD
}

CURVE_EXP_LINEAR :: f32(1e-4)       // an exponent this small is a line (the division by e^c - 1 would lose everything)

@(private)
bias :: proc(x: f32, coefficient: f32) -> f32 {
    return x / (coefficient * (1 - x) + 1)
}

// The shape at x (0 .. 1) with the coefficient of CurveCoefficient.
CurveEvalCoefficient :: proc(shape: CurveShape, coefficient: f32, x: f32) -> f32 {
    switch shape {
    case .LINEAR: return x
    case .HOLD: return 0 if x < 1 else 1
    case .SMOOTH: return x * x * (3 - 2 * x)
    case .CURVE: return bias(x, coefficient)
    case .S_CURVE:
        if x < 0.5 { return 0.5 * bias(2 * x, coefficient) }
        return 1 - 0.5 * bias(2 - 2 * x, coefficient)
    case .EXP:
        if abs(coefficient) < CURVE_EXP_LINEAR { return x }
        return (math.exp(coefficient * x) - 1) / (math.exp(coefficient) - 1)
    case .STAIRS:
        n: f32 = max(abs(coefficient), 2)
        return min(math.floor(x * n) / (n - 1), 1)
    case .SMOOTH_STAIRS:
        n: f32 = abs(coefficient)
        k: f32 = min(math.floor(x * n), n - 1)
        f: f32 = x * n - k
        return (k + f * f * (3 - 2 * f)) / n
    case .PULSE:
        if x >= 1 { return 1 }
        n: f32 = abs(coefficient)
        high: bool = x * n - math.floor(x * n) >= 0.5
        return 1 if high == (coefficient >= 0) else 0
    case .TRIANGLE, .WAVE:
        runs: f32 = 2 * abs(coefficient) - 1
        p: f32 = x * runs
        k: f32 = min(math.floor(p), runs - 1)
        f: f32 = p - k
        if shape == .WAVE { f = 0.5 - 0.5 * math.cos(math.PI * f) }
        return f if int(k) % 2 == 0 else 1 - f
    }
    return x
}

// The shape at x for a `curve` number (-1 .. 1); for many x of one segment use CurveCoefficient once and CurveEvalCoefficient.
CurveEval :: proc(shape: CurveShape, curve: f32, x: f32) -> f32 {
    return CurveEvalCoefficient(shape, CurveCoefficient(shape, curve), clamp(x, 0, 1))
}

// The next shape of a list a click cycles through.
CurveShapeNext :: proc(shape: CurveShape) -> CurveShape {
    switch shape {
    case .LINEAR: return .SMOOTH
    case .SMOOTH: return .CURVE
    case .CURVE: return .S_CURVE
    case .S_CURVE: return .EXP
    case .EXP: return .STAIRS
    case .STAIRS: return .SMOOTH_STAIRS
    case .SMOOTH_STAIRS: return .PULSE
    case .PULSE: return .TRIANGLE
    case .TRIANGLE: return .WAVE
    case .WAVE: return .HOLD
    case .HOLD: return .LINEAR
    }
    return .LINEAR
}

// The line of a segment as straight pieces between the screen points `a` and `b` (the value and the time are mapped linearly onto the screen): HOLD is the corner, LINEAR one piece, the
// curved shapes as many pieces as their width allows (about every 4 pixels, at least 4, at most 64). Writes the points after `a` into `out` (so the line starts at `a`) and returns them.
CurveSegmentPoints :: proc(shape: CurveShape, curve: f32, a: Vec2, b: Vec2, out: []Vec2) -> []Vec2 {
    switch shape {
    case .HOLD:
        if len(out) < 2 { return out[:0] }
        out[0], out[1] = {b.x, a.y}, b
        return out[:2]
    case .LINEAR:
        if len(out) < 1 { return out[:0] }
        out[0] = b
        return out[:1]
    case .SMOOTH, .CURVE, .S_CURVE, .EXP, .STAIRS, .SMOOTH_STAIRS, .PULSE, .TRIANGLE, .WAVE:
        // a counted shape needs a piece for every edge: at least 8 per cycle (a step or a pulse is cut at its edges by the sampling, which is fine for a line on a screen)
        pieces: int = clamp(int(abs(b.x - a.x) / 4), 4, 64)
        if CurveIsCounted(shape) { pieces = clamp(CurveCount(curve) * 8, pieces, len(out)) }
        pieces = min(pieces, len(out))
        coefficient: f32 = CurveCoefficient(shape, curve)
        for i in 1 ..= pieces {
            x: f32 = f32(i) / f32(pieces)
            out[i - 1] = {a.x + (b.x - a.x) * x, a.y + (b.y - a.y) * CurveEvalCoefficient(shape, coefficient, x)}
        }
        return out[:pieces]
    }
    return out[:0]
}

// Where the handle that bends a segment is: a part of the way along the segment, and the part of the value that the curve has covered there (0 .. 1). In the middle for the bias, a quarter of
// the way for the S shape (at the middle it is always at half way, a handle there would not move).
CurveHandle :: proc(shape: CurveShape, curve: f32) -> (along: f32, covered: f32) {
    // a counted shape: the handle is in the middle and its height is the count (more cycles higher), the position of the line there means nothing
    if CurveIsCounted(shape) { return 0.5, abs(clamp(curve, -CURVE_LIMIT, CURVE_LIMIT)) }
    along = 0.25 if shape == .S_CURVE else 0.5
    return along, CurveEvalCoefficient(shape, CurveCoefficient(shape, curve), along)
}

// The `curve` number that puts the handle of a segment at the part `covered` of the value (the inverse of CurveHandle for CURVE and S_CURVE: at the middle the bias is its own shape number,
// at a quarter the gain is half of the opposite number).
CurveFromHandle :: proc(shape: CurveShape, covered: f32) -> f32 {
    if CurveIsCounted(shape) { return clamp(covered, 0, CURVE_LIMIT) }
    // at the middle the exponential is 1 / (e^(c / 2) + 1)
    if shape == .EXP { return clamp(2 * math.ln(1 / clamp(covered, 0.001, 0.999) - 1) / CURVE_EXP_RANGE, -CURVE_LIMIT, CURVE_LIMIT) }
    if shape == .S_CURVE { return clamp(1 - 4 * covered, -CURVE_LIMIT, CURVE_LIMIT) }
    return clamp(2 * covered - 1, -CURVE_LIMIT, CURVE_LIMIT)
}
