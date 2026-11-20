#+build !js
package simd_example

import "core:testing"
import su ".."

@(private = "file")
fill :: proc(values: []f32, seed: u32) {
    state: u32 = seed
    for &value in values {
        state = state * 1664525 + 1013904223
        value = f32(i32(state >> 8) - (1 << 23)) / f32(1 << 23)
    }
}

// Every level of the table that this machine runs gives the answer of the portable kernel, at every length (the tails and the sizes under one vector)
@(test)
test_every_level_agrees_with_the_reference :: proc(t: ^testing.T) {
    table: DotTable
    DotInit(&table)
    a: [1000]f32
    b: [1000]f32
    fill(a[:], 1)
    fill(b[:], 2)
    checked: int
    for level in su.Level {
        if !su.LevelUsable(level, su.CpuBest()) || !su.TableHas(&table, level) { continue }
        kernel, got, ok := su.TablePick(&table, level)
        testing.expect(t, ok && got == level)
        for length in ([?]int{0, 1, 3, 4, 7, 15, 16, 17, 31, 32, 33, 63, 64, 65, 100, 255, 999, 1000}) {
            expected: f32 = DotScalar(a[:length], b[:length])
            result: f32 = kernel(a[:length], b[:length])
            // the sums are in another order: the error is relative to the size of the terms
            terms: f32 = 0
            for i in 0 ..< length { terms += abs(a[i] * b[i]) }
            testing.expectf(t, abs(result - expected) <= 1e-5 * max(terms, 1), "%v, length %d: %v against %v", level, length, result, expected)
        }
        checked += 1
    }
    testing.expect(t, checked >= 2, "at least the scalar and one vector kernel ran")
}

// The slices do not start on a vector boundary
@(test)
test_kernels_take_slices_that_are_not_aligned :: proc(t: ^testing.T) {
    table: DotTable
    DotInit(&table)
    a: [200]f32
    b: [200]f32
    fill(a[:], 3)
    fill(b[:], 4)
    for level in su.Level {
        if !su.LevelUsable(level, su.CpuBest()) || !su.TableHas(&table, level) { continue }
        kernel, _, _ := su.TablePick(&table, level)
        for offset in 0 ..< 9 {
            expected: f32 = DotScalar(a[offset:offset + 150], b[offset + 1:offset + 151])
            testing.expect(t, abs(kernel(a[offset:offset + 150], b[offset + 1:offset + 151]) - expected) < 1e-3, "offset")
        }
    }
}

// The manager gives each library its kernel
@(test)
test_the_manager_hands_the_kernels_of_the_levels_to_the_clients :: proc(t: ^testing.T) {
    table: DotTable
    DotInit(&table)
    cpu: su.Cpu = su.CpuFromFeatures({.SSE2, .SSE3, .SSSE3, .SSE41, .SSE42, .AVX, .AVX2, .FMA, .AVX512F, .AVX512DQ, .AVX512BW, .AVX512VL})
    manager: su.Manager
    su.ManagerInit(&manager, &cpu)
    audio, _ := su.ManagerRegister(&manager, "audio", priority = 10)
    physics, _ := su.ManagerRegister(&manager, "physics")
    su.ManagerFavor(&manager, audio)
    _, audio_level, _ := su.ManagerSelect(&manager, audio, &table)
    _, physics_level, _ := su.ManagerSelect(&manager, physics, &table)
    when ODIN_ARCH == .amd64 || ODIN_ARCH == .i386 {
        testing.expect_value(t, audio_level, su.Level.AVX512)
        testing.expect_value(t, physics_level, su.Level.AVX2)
    } else {
        _, _ = audio_level, physics_level
    }
}
