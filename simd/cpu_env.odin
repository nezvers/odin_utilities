#+build !js
package simd_utils

import "base:runtime"
import "core:os"

// SIMD_LEVEL=scalar | sse2 | sse3 | ssse3 | sse4.1 | sse4.2 | avx | avx2 | avx512 limits the level of the whole program (what `CpuForce` does): the tests and the
// benchmarks of every library that dispatches through this one can be run at each level on one machine. A level the machine does not have is ignored. Not for production.
@(private)
cpuApplyEnvironment :: proc "contextless" (cpu: ^Cpu) {
    context = runtime.default_context()
    value, found := os.lookup_env("SIMD_LEVEL", context.temp_allocator)
    if !found { return }
    level, ok := LevelFromName(value)
    if !ok { return }
    cpu.forced = LevelClamp(level, cpu.level)
    cpu.was_forced = cpu.forced != cpu.level
}
