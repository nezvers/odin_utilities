package simd_example

// A dot product with a kernel per level: the pattern that the dsp library of odin_plug uses, written small enough to copy. Every kernel
//   - runs FOUR independent accumulators: a fused multiply add takes four cycles and two can start per cycle, one register of sums uses an eighth of the multipliers
//     (the FIR, the peak meter and the oversampler of odin_plug got 1.5 to 9 times faster from this alone)
//   - loads with `unaligned_load`: a slice has no alignment, and the plain pointer cast makes the compiler assume one
//   - is its own procedure with its own `@(enable_target_feature)` and no `#force_inline` helper shared with another level: at -o:none and -o:minimal an inline helper is a
//     call, and a 256 bit value that crosses a call into a procedure without the same feature loses its upper half
//   - uses `simd.fma` only in procedures that have the fma feature (without it the compiler calls libm fmaf for every lane: 3 to 28 times slower)
// `DotTable` holds them, `DotInit` fills it, the plan or the state that calls the dot product keeps the kernel it got from the manager.

import "base:intrinsics"
import "core:simd"
import su ".."

DotProc :: #type proc "contextless" (a: []f32, b: []f32) -> f32

DotTable :: su.Table(DotProc)

// The kernels this build has, in a table
DotInit :: proc(table: ^DotTable) {
    su.TableSet(table, .SCALAR, DotScalar)
    su.TableSet(table, .SSE2, Dot4)          // core:simd with 4 lanes is baseline code on every target: the SSE2 kernel is also the one of NEON and SIMD128
    su.TableSet(table, .NEON, Dot4)
    su.TableSet(table, .SIMD128, Dot4)
    when ODIN_ARCH == .amd64 || ODIN_ARCH == .i386 {
        su.TableSet(table, .AVX, DotAvx)
        su.TableSet(table, .AVX2, DotAvx2)
        su.TableSet(table, .AVX512, DotAvx512)
    }
}

// The reference: every other kernel is tested against it
DotScalar :: proc "contextless" (a: []f32, b: []f32) -> f32 {
    count: int = min(len(a), len(b))
    s0, s1, s2, s3: f32
    i: int
    for ; i + 4 <= count; i += 4 {
        s0 += a[i] * b[i]
        s1 += a[i + 1] * b[i + 1]
        s2 += a[i + 2] * b[i + 2]
        s3 += a[i + 3] * b[i + 3]
    }
    for ; i < count; i += 1 { s0 += a[i] * b[i] }
    return (s0 + s1) + (s2 + s3)
}

// 128 bit, multiply and add (no fma: baseline x86-64 has none, and the fused forms of NEON and SIMD128 round differently)
Dot4 :: proc "contextless" (a: []f32, b: []f32) -> f32 {
    count: int = min(len(a), len(b))
    V :: #simd[4]f32
    s0, s1, s2, s3: V
    i: int
    for ; i + 16 <= count; i += 16 {
        s0 += intrinsics.unaligned_load(cast(^V)&a[i]) * intrinsics.unaligned_load(cast(^V)&b[i])
        s1 += intrinsics.unaligned_load(cast(^V)&a[i + 4]) * intrinsics.unaligned_load(cast(^V)&b[i + 4])
        s2 += intrinsics.unaligned_load(cast(^V)&a[i + 8]) * intrinsics.unaligned_load(cast(^V)&b[i + 8])
        s3 += intrinsics.unaligned_load(cast(^V)&a[i + 12]) * intrinsics.unaligned_load(cast(^V)&b[i + 12])
    }
    total: f32 = simd.reduce_add_ordered((s0 + s1) + (s2 + s3))
    for ; i < count; i += 1 { total += a[i] * b[i] }
    return total
}

when ODIN_ARCH == .amd64 || ODIN_ARCH == .i386 {

// 256 bit, no fma and no 256 bit integers: Sandy Bridge, Ivy Bridge, Bulldozer
@(enable_target_feature = su.FEATURES_AVX)
DotAvx :: proc "contextless" (a: []f32, b: []f32) -> f32 {
    count: int = min(len(a), len(b))
    V :: #simd[8]f32
    s0, s1, s2, s3: V
    i: int
    for ; i + 32 <= count; i += 32 {
        s0 += intrinsics.unaligned_load(cast(^V)&a[i]) * intrinsics.unaligned_load(cast(^V)&b[i])
        s1 += intrinsics.unaligned_load(cast(^V)&a[i + 8]) * intrinsics.unaligned_load(cast(^V)&b[i + 8])
        s2 += intrinsics.unaligned_load(cast(^V)&a[i + 16]) * intrinsics.unaligned_load(cast(^V)&b[i + 16])
        s3 += intrinsics.unaligned_load(cast(^V)&a[i + 24]) * intrinsics.unaligned_load(cast(^V)&b[i + 24])
    }
    total: f32 = simd.reduce_add_ordered((s0 + s1) + (s2 + s3))
    for ; i < count; i += 1 { total += a[i] * b[i] }
    return total
}

@(enable_target_feature = su.FEATURES_AVX2)
DotAvx2 :: proc "contextless" (a: []f32, b: []f32) -> f32 {
    count: int = min(len(a), len(b))
    V :: #simd[8]f32
    s0, s1, s2, s3: V
    i: int
    for ; i + 32 <= count; i += 32 {
        s0 = simd.fma(intrinsics.unaligned_load(cast(^V)&a[i]), intrinsics.unaligned_load(cast(^V)&b[i]), s0)
        s1 = simd.fma(intrinsics.unaligned_load(cast(^V)&a[i + 8]), intrinsics.unaligned_load(cast(^V)&b[i + 8]), s1)
        s2 = simd.fma(intrinsics.unaligned_load(cast(^V)&a[i + 16]), intrinsics.unaligned_load(cast(^V)&b[i + 16]), s2)
        s3 = simd.fma(intrinsics.unaligned_load(cast(^V)&a[i + 24]), intrinsics.unaligned_load(cast(^V)&b[i + 24]), s3)
    }
    total: f32 = simd.reduce_add_ordered((s0 + s1) + (s2 + s3))
    for ; i < count; i += 1 { total = intrinsics.fused_mul_add(a[i], b[i], total) }
    return total
}

@(enable_target_feature = su.FEATURES_AVX512)
DotAvx512 :: proc "contextless" (a: []f32, b: []f32) -> f32 {
    count: int = min(len(a), len(b))
    V :: #simd[16]f32
    s0, s1, s2, s3: V
    i: int
    for ; i + 64 <= count; i += 64 {
        s0 = simd.fma(intrinsics.unaligned_load(cast(^V)&a[i]), intrinsics.unaligned_load(cast(^V)&b[i]), s0)
        s1 = simd.fma(intrinsics.unaligned_load(cast(^V)&a[i + 16]), intrinsics.unaligned_load(cast(^V)&b[i + 16]), s1)
        s2 = simd.fma(intrinsics.unaligned_load(cast(^V)&a[i + 32]), intrinsics.unaligned_load(cast(^V)&b[i + 32]), s2)
        s3 = simd.fma(intrinsics.unaligned_load(cast(^V)&a[i + 48]), intrinsics.unaligned_load(cast(^V)&b[i + 48]), s3)
    }
    total: f32 = simd.reduce_add_ordered((s0 + s1) + (s2 + s3))
    for ; i < count; i += 1 { total = intrinsics.fused_mul_add(a[i], b[i], total) }
    return total
}

}
