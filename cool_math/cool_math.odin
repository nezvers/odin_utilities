package cool_math

import "core:math"


// Frame independent lerp
expDecay::proc(a:f32, b:f32, decay:f32, dt:f32)->f32{
    // Freya Holmér "Lerp smoothing is broken" - https://youtu.be/LSNQuFEDOyQ?t=2987
    return b + (a - b) * math.exp(-decay * dt)
}

// Linear motion
MoveToward::proc(a:f32, b:f32, speed:f32, dt:f32)->f32{
    v: = b - a
    stepDist: = speed * dt
    if (stepDist >= abs(v)){
        return b
    }
    return a + math.sign(v) * stepDist
}

lerp::proc(a:f32, b:f32, t:f32)->f32{
    return a + (b - a) * t
}

inverseLerp::proc(a:f32, b:f32, t:f32)->f32{
    diff:f32 = b - a
    if diff == 0 {
        return 1
    }
    return (t - a) / diff
}

remap::proc(iMin:f32, iMax:f32, oMin:f32, oMax:f32, v:f32)->f32{
    t: = inverseLerp(iMin, iMax, v)
    t = clamp(t, 0, 1)
    return lerp(oMin, oMax, t)
}

// LITTLE ENDIAN only
fast_exp::proc(a:f64)->f64 {
    //https://github.com/ekmett/approximate/blob/c8917831c8a41901009effcb8dd6d664c1222f50/cbits/fast.c#L75
    result:i64 = 6497320848556798 * cast(i64)a + 0x3fef127e83d16f12
    return transmute(f64)result
}