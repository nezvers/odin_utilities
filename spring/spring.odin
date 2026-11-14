package spring
// Second-Order System "Spring"

import "core:math"
import "core:testing"

// ==================== INERTIA SPRING ==========================
// I wasn't happy with solutions I found and included bellow
// So I created my solution based on frame independant lerping / expDecay

// Freq above 3 becomes unstable
// Damping around 50 makes settling almost instant
InertiaSpring::proc(position:^f32, velocity:^f32, target:f32, freq:f32, damping:f32, dt:f32){
    distance:f32 = target - position^
    targetVel: = distance * freq
    velocity^ = expDecay(velocity^, targetVel, damping, dt)
    position^ += velocity^
}

// infinite ringing - can create orbiting planets
// start with freq = 0.01, damping = 10000
OscilatingSpring::proc(position:^f32, velocity:^f32, target:f32, freq:f32, damping:f32, dt:f32){
    distance:f32 = target - position^
    targetVel: = distance * freq
    velocity^ += expDecay(velocity^, targetVel, damping, dt)
    position^ += velocity^
}

// Frame independent lerp
expDecay::proc(a:f32, b:f32, decay:f32, dt:f32)->f32{
    // Freya Holmér "Lerp smoothing is broken" - https://youtu.be/LSNQuFEDOyQ?t=2987
    return b + (a - b) * math.exp(-decay * dt)
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


// ========================= DAMPED SPRING =========================
// Checked against the closed form solution in the tests at the bottom
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
        return
    }

    if dampingRatio > 1 + epsilon {
        // over-damped
        za:f32 = -angularFrequency * dampingRatio
        zb:f32 = angularFrequency * math.sqrt(dampingRatio*dampingRatio - 1)
        z1:f32 = za - zb
        z2:f32 = za + zb

        e1:f32 = math.exp(z1 * deltaTime)
        e2:f32 = math.exp(z2 * deltaTime)

        invTwoZb:f32 = 1 / (2 * zb)

        e1_over_twoZb:f32 = e1 * invTwoZb
        e2_over_twoZb:f32 = e2 * invTwoZb

        z1e1_over_twoZb:f32 = z1 * e1_over_twoZb
        z2e2_over_twoZb:f32 = z2 * e2_over_twoZb

        springParams.posPosCoef = e1_over_twoZb * z2 - z2e2_over_twoZb + e2
        springParams.posVelCoef = -e1_over_twoZb + e2_over_twoZb

        springParams.velPosCoef = (z1e1_over_twoZb - z2e2_over_twoZb + e2) * z2
        springParams.velVelCoef = -z1e1_over_twoZb + z2e2_over_twoZb
    } else
    if dampingRatio < 1 - epsilon {
        // under-damped
        omegaZeta:f32 = angularFrequency * dampingRatio
        alpha:f32 = angularFrequency * math.sqrt(1 - dampingRatio * dampingRatio)

        expTerm:f32 = math.exp(-omegaZeta * deltaTime)
        cosTerm:f32 = math.cos(alpha * deltaTime)
        sinTerm:f32 = math.sin(alpha * deltaTime)

        invAlpha:f32 = 1 / alpha

        expSin:f32 = expTerm * sinTerm
        expCos:f32 = expTerm * cosTerm
        expOmegaZetaSin_over_alpha:f32 = expTerm * omegaZeta * sinTerm * invAlpha

        springParams.posPosCoef = expCos + expOmegaZetaSin_over_alpha
        springParams.posVelCoef = expSin * invAlpha

        springParams.velPosCoef = -expSin * alpha - omegaZeta * expOmegaZetaSin_over_alpha
        springParams.velVelCoef = expCos - expOmegaZetaSin_over_alpha
    } else {
        // critically damped
        expTerm:f32 = math.exp( -angularFrequency * deltaTime)
        timeExp:f32 = deltaTime * expTerm
        timeExpFreq:f32 = timeExp * angularFrequency

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

    position^ = oldPos * springParams.posPosCoef + oldVel * springParams.posVelCoef + targetPosition
    velocity^ = oldPos * springParams.velPosCoef + oldVel * springParams.velVelCoef
}

// ==================== MaddHattPatt ======================
// Checked against the stepped spring in the tests at the bottom
// translated from https://youtu.be/H-jRx_E8aZ8?t=745

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
    switch params.category {
    case SpringCategory.UndampedFrictionless:
        sqrt_km: = math.sqrt(params.k / params.m)
        output = x_0 * math.cos(sqrt_km * t) + v_0 / sqrt_km * math.sin(sqrt_km * t)
        break
    case SpringCategory.UnderdampedUnstable:
        omega_damped: = params.omega * math.sqrt(1.0 - params.zeta * params.zeta)
        A: = x_0
        B:f32 = (v_0 + params.zeta * params.omega * x_0) / omega_damped
        // the envelope decays with the undamped frequency, only the oscillation uses the damped one
        output = math.exp(-params.zeta * params.omega * t) * (A * math.cos(omega_damped * t) + B * math.sin(omega_damped * t))
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

// --- Tests ---

@(private="file")
simulate :: proc(params: DampedSpringMotionParams, start, target: f32, steps: int) -> (position: f32, peak: f32) {
    params := params
    position = start
    velocity: f32
    peak = start
    for _ in 0 ..< steps {
        UpdateDampedSpringMotion(&position, &velocity, target, &params)
        peak = max(peak, position)
    }
    return
}

@(test)
test_exp_decay_is_frame_rate_independent :: proc(t: ^testing.T) {
    testing.expect_value(t, expDecay(10, 0, 5, 0), f32(10))
    testing.expect(t, abs(expDecay(10, 0, math.ln(f32(2)), 1) - 5) < 1e-4, "half way after one half-life")
    once: f32 = expDecay(10, 0, 3, 1)
    twice: f32 = expDecay(expDecay(10, 0, 3, 0.5), 0, 3, 0.5)
    testing.expect(t, abs(once - twice) < 1e-5)
}

@(test)
test_inertia_spring_settles :: proc(t: ^testing.T) {
    position, velocity: f32 = 0, 0
    for _ in 0 ..< 600 { InertiaSpring(&position, &velocity, 10, 1, 20, 1.0 / 60) }
    testing.expect(t, abs(position - 10) < 0.05, "arrives at the target")
    testing.expect(t, abs(velocity) < 0.05, "and stops there")
}

@(test)
test_box2d_spring_damper :: proc(t: ^testing.T) {
    testing.expect_value(t, SpringDamper(2, 0.5, 0, 0, 1.0 / 60), f32(0))         // at rest on the target
    testing.expect(t, SpringDamper(2, 0.5, 1, 0, 1.0 / 60) < 0, "pushed back toward the target")
    testing.expect(t, SpringDamper(2, 0.5, -1, 0, 1.0 / 60) > 0)

    length, velocity: f32 = 3, 0
    for _ in 0 ..< 600 {
        velocity = SpringDamper(1, 1, length - 1, velocity, 1.0 / 60)
        length += velocity / 60
    }
    testing.expect(t, abs(length - 1) < 0.01, "a critically damped spring settles on its rest length")
}

@(test)
test_damped_spring_params_edge_cases :: proc(t: ^testing.T) {
    params: DampedSpringMotionParams
    CalcDampedSpringMotionParams(&params, 0.1, 0, 1)                               // no frequency: nothing moves
    testing.expect_value(t, params.posPosCoef, f32(1))
    testing.expect_value(t, params.velVelCoef, f32(0))

    for ratio in ([]f32{0.3, 1, 3}) {
        CalcDampedSpringMotionParams(&params, 0, 10, ratio)                        // no time passed: identity
        testing.expect(t, abs(params.posPosCoef - 1) < 1e-5 && abs(params.velVelCoef - 1) < 1e-5)
        testing.expect(t, abs(params.posVelCoef) < 1e-5 && abs(params.velPosCoef) < 1e-5)
    }
}

@(test)
test_damped_spring_regimes :: proc(t: ^testing.T) {
    params: DampedSpringMotionParams

    CalcDampedSpringMotionParams(&params, 1.0 / 60, 10, 1)                         // critically damped
    position, peak := simulate(params, 0, 1, 600)
    testing.expect(t, abs(position - 1) < 1e-3, "critical: arrives")
    testing.expect(t, peak <= 1 + 1e-4, "critical: never overshoots")

    CalcDampedSpringMotionParams(&params, 1.0 / 60, 10, 3)                         // over damped
    position, peak = simulate(params, 0, 1, 1200)
    testing.expect(t, abs(position - 1) < 1e-3, "over damped: arrives")
    testing.expect(t, peak <= 1 + 1e-4, "over damped: never overshoots")

    CalcDampedSpringMotionParams(&params, 1.0 / 60, 10, 0.2)                       // under damped
    position, peak = simulate(params, 0, 1, 1200)
    testing.expect(t, abs(position - 1) < 1e-3, "under damped: arrives")
    testing.expect(t, peak > 1.2, "under damped: overshoots")
}

@(test)
test_damped_spring_matches_closed_form :: proc(t: ^testing.T) {
    // the stepped spring and the analytic solution describe the same motion
    omega: f32 = 8
    cases: []struct { ratio: f32, category: SpringCategory } = {
        {0.25, .UnderdampedUnstable},
        {1, .CriticallyDamped},
        {2.5, .Overdamped},
    }
    for c in cases {
        params: DampedSpringMotionParams
        CalcDampedSpringMotionParams(&params, 1.0 / 60, omega, c.ratio)
        position: f32 = 1                                                          // one unit away from the target at 0
        velocity: f32 = 0
        for _ in 0 ..< 30 { UpdateDampedSpringMotion(&position, &velocity, 0, &params) }

        closed: SpringParams = {k = omega * omega, m = 1, zeta = c.ratio, omega = omega, category = c.category}
        expected: f32 = SpringMaddHattPatt(&closed, 0.5, 1, 0)
        testing.expect(t, abs(position - expected) < 1e-3, "same position after half a second")
    }
}

@(test)
test_spring_closed_form_starts_at_x0 :: proc(t: ^testing.T) {
    for category in SpringCategory {
        zeta: f32 = 0.5
        if category == .CriticallyDamped { zeta = 1 }
        if category == .Overdamped { zeta = 2 }
        if category == .UndampedFrictionless { zeta = 0 }
        params: SpringParams = {k = 100, m = 1, zeta = zeta, omega = 10, category = category}
        testing.expect(t, abs(SpringMaddHattPatt(&params, 0, 2, 0) - 2) < 1e-4, "the spring starts at x0")
    }
    frictionless: SpringParams = {k = 100, m = 1, zeta = 0, omega = 10, category = .UndampedFrictionless}
    testing.expect(t, abs(SpringMaddHattPatt(&frictionless, math.TAU / 10, 2, 0) - 2) < 1e-3, "and comes back after one period")
}
