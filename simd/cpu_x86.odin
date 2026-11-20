#+build i386, amd64
package simd_utils

import "base:intrinsics"

@(private)
cpuDetect :: proc "contextless" () -> Cpu {
    cpu: Cpu
    max_leaf, vendor_b, vendor_c, vendor_d := intrinsics.x86_cpuid(0, 0)
    // the vendor is spelled in ebx, edx, ecx
    for i in 0 ..< 4 {
        cpu.vendor[i] = u8(vendor_b >> u32(8 * i))
        cpu.vendor[4 + i] = u8(vendor_d >> u32(8 * i))
        cpu.vendor[8 + i] = u8(vendor_c >> u32(8 * i))
    }
    cpu.family = .X86
    max_extended, _, _, _ := intrinsics.x86_cpuid(0x80000000, 0)
    if max_extended >= 0x80000004 {
        for part in 0 ..< 3 {
            a, b, c, d := intrinsics.x86_cpuid(0x80000002 + u32(part), 0)
            registers: [4]u32 = {a, b, c, d}
            for register, r in registers {
                for i in 0 ..< 4 { cpu.brand[part * 16 + r * 4 + i] = u8(register >> u32(8 * i)) }
            }
        }
    }
    if max_leaf < 1 { return cpuFinish(cpu) }
    _, _, ecx1, edx1 := intrinsics.x86_cpuid(1, 0)
    features: Features
    if edx1 >> 23 & 1 != 0 { features += {.MMX} }
    if edx1 >> 25 & 1 != 0 { features += {.SSE} }
    if edx1 >> 26 & 1 != 0 { features += {.SSE2} }
    if ecx1 >> 0 & 1 != 0 { features += {.SSE3} }
    if ecx1 >> 9 & 1 != 0 { features += {.SSSE3} }
    if ecx1 >> 19 & 1 != 0 { features += {.SSE41} }
    if ecx1 >> 20 & 1 != 0 { features += {.SSE42} }
    if ecx1 >> 23 & 1 != 0 { features += {.POPCNT} }
    // the wide registers are only safe when the operating system saves them: OSXSAVE, then the state bits of XCR0 (1 XMM, 2 YMM, 5 opmask, 6 upper ZMM, 7 ZMM16 .. 31)
    osxsave: bool = ecx1 >> 27 & 1 != 0
    xcr0: u32                           // the low half is the state bits
    if osxsave { xcr0, _ = intrinsics.x86_xgetbv(0) }
    ymm_ok: bool = osxsave && xcr0 & 6 == 6
    if ymm_ok {
        if ecx1 >> 28 & 1 != 0 { features += {.AVX} }
        if ecx1 >> 29 & 1 != 0 { features += {.F16C} }
        if ecx1 >> 12 & 1 != 0 { features += {.FMA} }
    }
    if max_leaf >= 7 {
        _, ebx7, ecx7, _ := intrinsics.x86_cpuid(7, 0)
        if ebx7 >> 3 & 1 != 0 { features += {.BMI1} }
        if ebx7 >> 8 & 1 != 0 { features += {.BMI2} }
        if ymm_ok && .AVX in features && ebx7 >> 5 & 1 != 0 { features += {.AVX2} }
        if ymm_ok && xcr0 & 0xE0 == 0xE0 {
            if ebx7 >> 16 & 1 != 0 { features += {.AVX512F} }
            if ebx7 >> 17 & 1 != 0 { features += {.AVX512DQ} }
            if ebx7 >> 28 & 1 != 0 { features += {.AVX512CD} }
            if ebx7 >> 30 & 1 != 0 { features += {.AVX512BW} }
            if ebx7 >> 31 & 1 != 0 { features += {.AVX512VL} }
            if ecx7 >> 1 & 1 != 0 { features += {.AVX512VBMI} }
            if ecx7 >> 11 & 1 != 0 { features += {.AVX512VNNI} }
        }
    }
    cpu.features = features
    return cpuFinish(cpu)
}

@(private)
cpuFinish :: proc "contextless" (cpu: Cpu) -> Cpu {
    result: Cpu = cpu
    result.level = LevelFromFeatures(result.features)
    // a 32 bit x86 build without SSE2 in the build target still runs SSE2 code through the kernels' own feature attributes, so the level is what the CPU has
    return result
}
