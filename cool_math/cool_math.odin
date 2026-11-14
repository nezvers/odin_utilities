package cool_math

import "base:intrinsics"
import "core:math"
import "core:testing"

// Positive is 1
// Negative is -1
// Zero is zero
Sign::proc(x:$T)->T
where intrinsics.type_is_numeric(T)
{
    result:T = x > 0 ? 1 : (x < 0 ? -1 : 0)
    return result
}

// Linear motion
MoveToward::proc(a:$T, b:T, speed:T, t:$F)->T
where intrinsics.type_is_numeric(T)
{
    v: = b - a
    stepDist: = speed * t
    if (stepDist >= abs(v)){
        return b
    }
    return a + Sign(v) * stepDist
}

Lerp::proc(a:$T, b:T, t:T)->T
where intrinsics.type_is_float(T)
{
    return a + (b - a) * t
}

// Frame independent lerp
// decay gives a curve
// dt is delta time
ExpDecay::proc(a:$T, b:T, decay:T, dt:T)->T
where intrinsics.type_is_float(T)
{
    // Freya Holmér "Lerp smoothing is broken" - https://youtu.be/LSNQuFEDOyQ?t=2987
    return b + (a - b) * math.exp(-decay * dt)
}

InverseLerp::proc(a:$T, b:T, t:T)->T
where intrinsics.type_is_numeric(T)
{
    diff:T = b - a
    if diff == 0 {
        return 1
    }
    return (t - a) / diff
}

Remap::proc(iMin:$T, iMax:T, oMin:T, oMax:T, v:T)->T
where intrinsics.type_is_float(T)
{
    t: = InverseLerp(iMin, iMax, v)
    t = clamp(t, 0, 1)
    return Lerp(oMin, oMax, t)
}

// LITTLE ENDIAN only
// Approximated, need to tweak values
FastExp::proc(a:f64)->f64 {
    //https://github.com/ekmett/approximate/blob/c8917831c8a41901009effcb8dd6d664c1222f50/cbits/fast.c#L75
    result:i64 = 6497320848556798 * cast(i64)a + 0x3fef127e83d16f12
    return transmute(f64)result
}

// --- Tests ---

@(private="file")
near :: proc(a, b: f32, epsilon: f32 = 1e-5) -> bool {
    return abs(a - b) <= epsilon
}

@(test)
test_sign_move_toward_lerp :: proc(t: ^testing.T) {
    testing.expect_value(t, Sign(5), 1)
    testing.expect_value(t, Sign(-2.5), f64(-1))
    testing.expect_value(t, Sign(0), 0)

    testing.expect_value(t, MoveToward(f32(0), 10, 2, f32(1)), f32(2))
    testing.expect_value(t, MoveToward(f32(0), 10, 5, f32(3)), f32(10))          // a step longer than the distance stops on the target
    testing.expect_value(t, MoveToward(f32(10), 0, 3, f32(1)), f32(7))           // and it moves down as well
    testing.expect_value(t, MoveToward(f32(4), 4, 3, f32(1)), f32(4))
    testing.expect_value(t, MoveToward(0, 10, 3, 1), 3)                          // integers

    testing.expect_value(t, Lerp(f32(0), 10, 0.25), f32(2.5))
    testing.expect_value(t, Lerp(f64(10), 20, 0), f64(10))
    testing.expect_value(t, Lerp(f64(10), 20, 1), f64(20))
}

@(test)
test_exp_decay_inverse_lerp_remap :: proc(t: ^testing.T) {
    testing.expect_value(t, ExpDecay(f32(10), 0, 1, 0), f32(10))                  // no time passed
    testing.expect(t, near(ExpDecay(f32(10), 0, math.ln(f32(2)), 1), 5))          // decay ln 2 per second halves the distance in one second
    testing.expect(t, ExpDecay(f32(10), 0, 5, 10) < 1e-6, "converges on the target")
    testing.expect(t, near(ExpDecay(f32(0), 8, math.ln(f32(2)), 1), 4))
    // the result does not depend on how the time is cut into frames
    one_step: f32 = ExpDecay(f32(10), 0, 2, 1)
    two_steps: f32 = ExpDecay(ExpDecay(f32(10), 0, 2, 0.5), 0, 2, 0.5)
    testing.expect(t, near(one_step, two_steps))

    testing.expect_value(t, InverseLerp(f32(0), 10, 5), f32(0.5))
    testing.expect_value(t, InverseLerp(f32(10), 20, 25), f32(1.5))                // not clamped
    testing.expect_value(t, InverseLerp(f32(3), 3, 99), f32(1))                    // an empty range

    testing.expect_value(t, Remap(f32(0), 10, 100, 200, 5), f32(150))
    testing.expect_value(t, Remap(f32(0), 10, 100, 200, 20), f32(200))             // clamped
    testing.expect_value(t, Remap(f32(0), 10, 100, 200, -5), f32(100))
    testing.expect_value(t, Remap(f32(10), 0, 0, 1, 2.5), f32(0.75))               // a reversed input range
}

@(test)
test_fast_exp_is_an_approximation :: proc(t: ^testing.T) {
    testing.expect(t, abs(FastExp(0) - 1) < 0.1, "exp(0) is about 1")
    previous: f64 = 0
    for i in 0 ..< 8 {
        value: f64 = FastExp(f64(i))
        testing.expect(t, value > previous, "grows with the exponent")
        previous = value
    }
    testing.expect(t, abs(FastExp(5) / math.exp(f64(5)) - 1) < 0.1, "within 10 percent of exp at a whole number")
}
