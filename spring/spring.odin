package spring
// Second-Order System "Spring"

import "core:math"


// translated from https://youtu.be/H-jRx_E8aZ8?t=745

SpringCategory :: enum {
    UndampedFrictionless,
    UnderdampedStable,
    UnderdampedUnstable,
    CriticallyDamped,
    Overdamped,
    Undefined,
}

// r = response curve, negative anticipate, above 1 overshoot, 2 is typical for mechanic movement
SpringParams :: struct {
    k:f32, // Spring constant
    m:f32, // mass
    zeta:f32, // damping applied - 0 is no damping, above 1 smooth curve
    omega:f32, // frequency
    category:SpringCategory,
}

Spring::proc(params:^SpringParams, t:f32, x_0:f32 = 1., v_0:f32 = 0. )->(output:f32){
    switch params.category {
    case SpringCategory.UndampedFrictionless:
        sqrt_km: = math.sqrt(params.k / params.m)
        output = x_0 * math.cos(sqrt_km * t) + v_0 / sqrt_km * math.sin(sqrt_km * t)
        break
    
    case SpringCategory.UnderdampedStable:
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
    
    case SpringCategory.Undefined:
        output = 1.0
        break
    }
    return
}

