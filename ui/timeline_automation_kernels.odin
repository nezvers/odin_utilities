package ui

// The two loops of the block renderer that run for every sample, one kernel per instruction set level of odin_utilities/simd: the ramp (out[i] = base + i * delta, every linear segment and every
// run between anchors) and the exponential run. The same loops are compiled for the baseline, for AVX2 and for AVX-512: measured on a Zen 5 the ramp costs 0.14 ns a sample built for the
// baseline (SSE2: four lanes) and 0.05 with the 256 bit code (`odin run ui/tool/automation_bench -o:speed`), the rest of a block is the search for the segment. A level without a kernel runs the
// one below it, and SIMD_LEVEL (odin_utilities/simd) picks the level, so the tests of this package run every kernel (`odin run tool/test -- --levels ui`).
// No fused multiply add anywhere: the answers of the levels are the same bit for bit (a test compares them).

import "base:intrinsics"
import "core:math"
import su "../simd"

AutomationRampProc :: #type proc "contextless" (out: []f32, base: f32, delta: f32)
AutomationExpProc :: #type proc "contextless" (out: []f32, growth: f32, ratio: f32, base: f32, scale: f32)

AutomationKernels :: struct {
    ramp: AutomationRampProc,
    exp_run: AutomationExpProc,
}

@(private)
automation_tables: [su.Level]AutomationKernels

@(private)
automation_current: AutomationKernels

@(private, init)
automationKernelsInit :: proc "contextless" () {
    automation_tables[.SCALAR] = {rampBase, expBase}
    automation_tables[.SSE2] = {rampBase, expBase}
    when ODIN_ARCH == .amd64 || ODIN_ARCH == .i386 {
        automation_tables[.AVX2] = {rampAvx2, expAvx2}
        automation_tables[.AVX512] = {rampAvx512, expAvx512}
    }
    for level in su.Level {
        if automation_tables[level].ramp == nil { automation_tables[level] = automation_tables[su.LevelBelow(level)] }
    }
    AutomationKernelsSelect()
}

// Chooses the kernels of the level the machine (or SIMD_LEVEL) gives. Called at start up; a program that forces a level after that calls it again.
AutomationKernelsSelect :: proc "contextless" () {
    automation_current = automation_tables[su.CpuLevel()]
}

// The kernels of a level, for the tests that compare them
AutomationKernelsOf :: proc "contextless" (level: su.Level) -> AutomationKernels {
    return automation_tables[level]
}

// out[i] = base + i * delta: no sample waits for another, nothing adds up
rampBase :: proc "contextless" (out: []f32, base: f32, delta: f32) {
    for i in 0 ..< len(out) { out[i] = base + f32(i) * delta }
}

// out[i] = base + growth * ratio^i * scale: eight lanes, each with its own power of the ratio, all of them multiplied by ratio^8 together (the chain of one multiply a sample, four cycles each,
// becomes one a vector); the powers of the first eight come from a scalar run
expBase :: proc "contextless" (out: []f32, growth: f32, ratio: f32, base: f32, scale: f32) {
    V :: #simd[8]f32
    first: [8]f32
    power: f32 = growth
    for lane in 0 ..< 8 {
        first[lane] = power
        power *= ratio
    }
    grow: V = intrinsics.unaligned_load(cast(^V)&first[0])
    step: V = V(power / growth)
    offset: V = V(base)
    factor: V = V(scale)
    i: int
    for ; i + 8 <= len(out); i += 8 {
        intrinsics.unaligned_store(cast(^V)&out[i], offset + grow * factor)
        grow *= step
    }
    tail: f32 = growth * math.pow(ratio, f32(i))
    for ; i < len(out); i += 1 {
        out[i] = base + tail * scale
        tail *= ratio
    }
}

when ODIN_ARCH == .amd64 || ODIN_ARCH == .i386 {

@(enable_target_feature = su.FEATURES_AVX2)
rampAvx2 :: proc "contextless" (out: []f32, base: f32, delta: f32) {
    for i in 0 ..< len(out) { out[i] = base + f32(i) * delta }
}

@(enable_target_feature = su.FEATURES_AVX512)
rampAvx512 :: proc "contextless" (out: []f32, base: f32, delta: f32) {
    for i in 0 ..< len(out) { out[i] = base + f32(i) * delta }
}

@(enable_target_feature = su.FEATURES_AVX2)
expAvx2 :: proc "contextless" (out: []f32, growth: f32, ratio: f32, base: f32, scale: f32) {
    V :: #simd[8]f32
    first: [8]f32
    power: f32 = growth
    for lane in 0 ..< 8 {
        first[lane] = power
        power *= ratio
    }
    grow: V = intrinsics.unaligned_load(cast(^V)&first[0])
    step: V = V(power / growth)
    offset: V = V(base)
    factor: V = V(scale)
    i: int
    for ; i + 8 <= len(out); i += 8 {
        intrinsics.unaligned_store(cast(^V)&out[i], offset + grow * factor)
        grow *= step
    }
    tail: f32 = growth * math.pow(ratio, f32(i))
    for ; i < len(out); i += 1 {
        out[i] = base + tail * scale
        tail *= ratio
    }
}

@(enable_target_feature = su.FEATURES_AVX512)
expAvx512 :: proc "contextless" (out: []f32, growth: f32, ratio: f32, base: f32, scale: f32) {
    V :: #simd[16]f32
    first: [16]f32
    power: f32 = growth
    for lane in 0 ..< 16 {
        first[lane] = power
        power *= ratio
    }
    grow: V = intrinsics.unaligned_load(cast(^V)&first[0])
    step: V = V(power / growth)
    offset: V = V(base)
    factor: V = V(scale)
    i: int
    for ; i + 16 <= len(out); i += 16 {
        intrinsics.unaligned_store(cast(^V)&out[i], offset + grow * factor)
        grow *= step
    }
    tail: f32 = growth * math.pow(ratio, f32(i))
    for ; i < len(out); i += 1 {
        out[i] = base + tail * scale
        tail *= ratio
    }
}

}
