package cool_math

import "base:intrinsics"

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
    return a + math.sign(v) * stepDist
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
    t: = inverseLerp(iMin, iMax, v)
    t = clamp(t, 0, 1)
    return lerp(oMin, oMax, t)
}

// LITTLE ENDIAN only
// Approximated, need to tweak values
FastExp::proc(a:f64)->f64 {
    //https://github.com/ekmett/approximate/blob/c8917831c8a41901009effcb8dd6d664c1222f50/cbits/fast.c#L75
    result:i64 = 6497320848556798 * cast(i64)a + 0x3fef127e83d16f12
    return transmute(f64)result
}