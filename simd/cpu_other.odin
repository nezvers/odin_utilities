package simd_utils

import "base:intrinsics"

// No CPUID here. arm64 always has NEON; the web build has SIMD128 when the build asks for it (there is no run time check in WebAssembly: a module that uses the
// instructions does not load without them); everything else is the portable code. (A condition and not a build tag: "everything but x86" cannot be a tag.)
when ODIN_ARCH != .amd64 && ODIN_ARCH != .i386 {
    @(private)
    cpuDetect :: proc "contextless" () -> Cpu {
        cpu: Cpu
        when ODIN_ARCH == .arm64 || ODIN_ARCH == .arm32 {
            cpu.features = {.NEON}
        } else when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
            when intrinsics.has_target_feature("simd128") { cpu.features = {.SIMD128} }
        }
        cpu.level = LevelFromFeatures(cpu.features)
        cpu.family = LevelFamily(cpu.level)
        return cpu
    }
}
