#+build !js
package simd_utils

import "base:runtime"
import "core:os"
import "core:strconv"

// SIMD_LEVEL=scalar | sse2 | sse3 | ssse3 | sse4.1 | sse4.2 | avx | avx2 | avx512 limits the level of the whole program (what `CpuForce` does): the tests and the
// benchmarks of every library that dispatches through this one can be run at each level on one machine. A level the machine does not have is ignored. Not for production.
// SIMD_L1D_KB, SIMD_L2_KB and SIMD_L3_KB replace the cache sizes (kilobytes): what a library that chooses its blocks from `Cpu.caches` would do on another machine, tried here
// (`Caches.overridden` says so). Not for production either.
@(private)
cpuApplyEnvironment :: proc "contextless" (cpu: ^Cpu) {
    context = runtime.default_context()
    value, found := os.lookup_env("SIMD_LEVEL", context.temp_allocator)
    if found {
        level, ok := LevelFromName(value)
        if ok {
            cpu.forced = LevelClamp(level, cpu.level)
            cpu.was_forced = cpu.forced != cpu.level
        }
    }
    l1d, l2, l3: u32
    if text, has := os.lookup_env("SIMD_L1D_KB", context.temp_allocator); has { number, _ := strconv.parse_uint(text); l1d = u32(number) }
    if text, has := os.lookup_env("SIMD_L2_KB", context.temp_allocator); has { number, _ := strconv.parse_uint(text); l2 = u32(number) }
    if text, has := os.lookup_env("SIMD_L3_KB", context.temp_allocator); has { number, _ := strconv.parse_uint(text); l3 = u32(number) }
    CacheOverride(&cpu.caches, l1d, l2, l3)
}
