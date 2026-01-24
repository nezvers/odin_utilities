package spring
// Second-Order System "Spring"

import "core:math"

// ========================= DAMPED SPRING =========================
// translated from https://gist.github.com/chadcable/92bc3958af5b171e593e36be57ca36ce

// Cached set of motion parameters that can be used to efficiently update
// multiple springs using the same time step, angular frequency and damping ratio
DampedSpringMotionParams::struct {
    // newPos = posPosCoef*oldPos + posVelCoef*oldVel
    posPosCoef:f32,
    posVelCoef:f32,
    // newVel = velPosCoef*oldPos + velVelCoef*oldVel
    velPosCoef:f32,
    velVelCoef:f32,
}

// Calculate params once per frame
CalcDampedSpringMotionParams::proc(
    springParams:^DampedSpringMotionParams,
    deltaTime:f32,              // simulated time
    angularFrequency:f32,       // angular frequency of motion
    dampingRatio:f32,           // damping ratio of motion
){
    assert(dampingRatio >= 0)
    assert(angularFrequency >= 0)
    epsilon:f32: 0.0001

    if angularFrequency < epsilon {
        springParams.posPosCoef = 1
        springParams.posVelCoef = 0
        springParams.velPosCoef = 0
        springParams.velVelCoef = 0
    }

    if dampingRatio > 1 + epsilon {
        // over-damped
        za: = -angularFrequency * dampingRatio
        zb: = angularFrequency * math.sqrt(dampingRatio*dampingRatio - 1)
        z1: = za - zb
        z2: = za + zb

        e1: = math.exp(z1 * deltaTime)
        e2: = math.exp(z2 * deltaTime)

        invTwoZb: = 1 / (2 * zb)

        e1_over_twoZb: = e1 * invTwoZb
        e2_over_twoZb: = e2 * invTwoZb

        z1e1_over_twoZb: = z1 * e1_over_twoZb
        z2e2_over_twoZb: = z2 * e2_over_twoZb

        springParams.posPosCoef = e1_over_twoZb * z2 - z2e2_over_twoZb + e2
        springParams.posVelCoef = -e1_over_twoZb + e2_over_twoZb

        springParams.velPosCoef = (z1e1_over_twoZb - z2e2_over_twoZb + e2) * z2
        springParams.velVelCoef = -z1e1_over_twoZb + z2e2_over_twoZb
    } else
    if dampingRatio < 1 - epsilon {
        // under-damped
        omegaZeta: = angularFrequency * dampingRatio
        alpha: = angularFrequency * math.sqrt(1 - dampingRatio * dampingRatio)

        expTerm: = math.exp(-omegaZeta * deltaTime)
        cosTerm: = math.cos(alpha * deltaTime)
        sinTerm: = math.sin(alpha * deltaTime)

        invAlpha: = 1 / alpha

        expSin: = expTerm * sinTerm
        expCos: = expTerm * cosTerm
        expOmegaZetaSin_over_alpha: = expTerm * omegaZeta * sinTerm * invAlpha

        springParams.posPosCoef = expCos + expOmegaZetaSin_over_alpha
        springParams.posVelCoef = expSin * invAlpha

        springParams.velPosCoef = -expSin * alpha - omegaZeta * expOmegaZetaSin_over_alpha
        springParams.velVelCoef = expCos - expOmegaZetaSin_over_alpha
    } else {
        // critically damped
        expTerm: = math.exp( -angularFrequency * deltaTime)
        timeExp: = deltaTime * expTerm
        timeExpFreq: = timeExp * angularFrequency

        springParams.posPosCoef = timeExpFreq + expTerm
        springParams.posVelCoef = timeExp

        springParams.velPosCoef = -angularFrequency * timeExpFreq
        springParams.velVelCoef = -timeExpFreq + expTerm
    }
}

// Reuse same params on different springs using same frequency and damping
UpdateDampedSpringMotion::proc(
    position:^f32,
    velocity:^f32,
    targetPosition:f32,
    springParams:^DampedSpringMotionParams,
){
    // update in equilibrium relative space
    oldPos: = position^ - targetPosition
    oldVel: = velocity^

    position^ = oldPos * springParams.posPosCoef + oldVel * springParams.posVelCoef
    velocity^ = oldVel * springParams.velPosCoef + oldVel * springParams.velVelCoef
}

// ======================= Box2D ============================

// Box2D SpringDamper
// One-dimensional mass-spring-damper simulation. Returns the new velocity given the position and time step.
// over 2 hertz becomes unstable
// velocity = sp.SpringDamper(hertz, damping, (current_length - target_length), velocity, delta_time)
// current_length += velocity
SpringDamper::proc(hertz:f32, dampingRatio:f32, position:f32, velocity:f32, timeStep:f32)->(velocity_out:f32) {
    // https://github.com/erincatto/box2d/blob/c05c48738fbe5c27625e36c5f0cfbdaddfc8359a/include/box2d/math_functions.h#L673
    omega:f32 = 2 * math.PI * hertz
    omegaH:f32 = omega * timeStep
    velocity_out = (velocity - omega * omegaH * position) / (1 + 2 * dampingRatio * omegaH + omegaH * omegaH)
    return
}

// ==================== MaddHattPatt ======================

SpringCategory :: enum {
    UndampedFrictionless,
    UnderdampedUnstable,
    CriticallyDamped,
    Overdamped,
}

SpringParams :: struct {
    k:f32, // Spring constant
    m:f32, // mass
    zeta:f32, // damping applied - 0 is no damping, above 1 smooth curve
    omega:f32, // frequency
    category:SpringCategory,
}

SpringMaddHattPatt::proc(params:^SpringParams, t:f32, x_0:f32 = 1., v_0:f32 = 0. )->(output:f32){
    // translated from https://youtu.be/H-jRx_E8aZ8?t=745
    switch params.category {
    case SpringCategory.UndampedFrictionless:
        sqrt_km: = math.sqrt(params.k / params.m)
        output = x_0 * math.cos(sqrt_km * t) + v_0 / sqrt_km * math.sin(sqrt_km * t)
        break
    case SpringCategory.UnderdampedUnstable:
        omega_damped: = params.omega * math.sqrt(1.0 - params.zeta * params.zeta)
        A: = x_0
        B:f32 = (v_0 + params.zeta * params.omega * x_0) / omega_damped
        output = math.exp(-params.zeta * omega_damped * t) * (A * math.cos(omega_damped * t) + B * math.sin(omega_damped * t))
        break
    
    case SpringCategory.CriticallyDamped:
        output = (x_0 + (v_0 + params.omega * x_0) * t) * math.exp(-params.omega * t)
        break
    
    case SpringCategory.Overdamped:
        sq: = math.sqrt(params.zeta * params.zeta - 1.0)
        eigenvalue1: = -params.omega * (params.zeta + sq)
        eigenvalue2: = -params.omega * (params.zeta - sq)
        coefficient1: = (v_0 - eigenvalue2 * x_0) / (eigenvalue1 - eigenvalue2)
        coefficient2: = (eigenvalue1 * x_0 - v_0) / (eigenvalue1 - eigenvalue2)
        output = coefficient1 * math.exp(eigenvalue1 * t) + coefficient2 * math.exp(eigenvalue2 * t)
        break
    }
    return
}


