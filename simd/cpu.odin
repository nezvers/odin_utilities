package simd_utils

// What this machine can run. `CpuGet()` is detected once at start up; `CpuFromFeatures` makes the same record from a list of features (the tests of a ladder, a program that
// reads the features of another machine from a file).

// What CPUID reports, with the operating system's part applied: AVX and the ones above need the system to save the wide registers (XGETBV), so a feature that the CPU
// has but the system does not keep safe is not in the set.
Feature :: enum u8 {
    MMX,
    SSE,
    SSE2,
    SSE3,
    SSSE3,
    SSE41,
    SSE42,
    POPCNT,
    AVX,
    F16C,
    FMA,
    AVX2,
    BMI1,
    BMI2,
    AVX512F,
    AVX512DQ,
    AVX512BW,
    AVX512VL,
    AVX512CD,
    AVX512VNNI,
    AVX512VBMI,
    AVX512VBMI2,                    // Ice Lake and later on Intel (and Zen 4): the first AVX-512 that does not lower the clock (see `Cpu.throttles`)
    AVX512BF16,
    AVX_VNNI,
    NEON,
    NEON_DOTPROD,                   // arm64 SDOT / UDOT (not detected: a program that knows says so with CpuAddFeatures)
    SVE,                            // the same
    FP16,                           // the same
    SIMD128,
}
Features :: bit_set[Feature; u32]

Cpu :: struct {
    features: Features,
    level: Level,                   // the best level of the ladder that this machine runs
    forced: Level,                  // what the program or the environment limited it to (`level` when nothing did)
    was_forced: bool,
    throttles: bool,                // AVX-512 on this CPU lowers the clock of the core: an Intel CPU with AVX-512 but without VBMI2 (Skylake-X, Cascade Lake). AMD Zen 4 and later and Ice Lake and later do not
    family: Family,
    vendor: [12]u8,                 // "GenuineIntel", "AuthenticAMD" ... (x86)
    brand: [48]u8,                  // "AMD Ryzen 9 9950X 16-Core Processor" (x86, zero padded)
    caches: Caches,                 // the sizes of the data caches of one core (x86: CPUID; elsewhere not known, `known` false)
}

// The data caches that an algorithm chooses its block sizes from: bytes of the first level data cache, the second level cache (per core on the CPUs that have it
// per core, per cluster on others: what CPUID says) and the last level (shared), and the length of a line. A size that is 0 is not known. The sizes are what the
// hardware reports, not what a program may use: a hyper threaded core shares its L1 and L2 with the other thread, which halves it for a program that cannot
// know whether the sibling is busy (a 1 MB working set measured 1.15 to 1.20 times slower in odin_plug while it was).
Caches :: struct {
    l1d: u32,
    l2: u32,
    l3: u32,
    line: u32,
    known: bool,                    // the data came from the CPU (CPUID), not from a default or an override
    overridden: bool,               // `SIMD_L1D_KB`, `SIMD_L2_KB`, `SIMD_L3_KB` or `CacheOverride` set at least one size
}

// What one CPUID cache leaf (leaf 4 of Intel, 0x8000001D of AMD: the same layout) says about one cache. `kind` 0 ends the list, 1 is data, 2 instruction, 3 unified.
CacheLeaf :: struct {
    kind: u8,
    level: u8,
    size: u32,
    line: u32,
}

CacheFromLeaf :: proc "contextless" (eax, ebx, ecx: u32) -> CacheLeaf {
    leaf: CacheLeaf
    leaf.kind = u8(eax & 31)
    leaf.level = u8(eax >> 5 & 7)
    if leaf.kind == 0 { return leaf }
    ways: u32 = (ebx >> 22) + 1
    partitions: u32 = (ebx >> 12 & 1023) + 1
    leaf.line = (ebx & 4095) + 1
    sets: u32 = ecx + 1
    leaf.size = ways * partitions * leaf.line * sets
    return leaf
}

// Fills the record from a list of leaves (the data and unified caches by level: L1 data, L2, L3)
CachesFromLeaves :: proc "contextless" (leaves: []CacheLeaf) -> Caches {
    caches: Caches
    for leaf in leaves {
        if leaf.kind != 1 && leaf.kind != 3 { continue }
        switch leaf.level {
        case 1: if leaf.kind == 1 { caches.l1d = leaf.size }
        case 2: caches.l2 = leaf.size
        case 3: caches.l3 = leaf.size
        }
        if caches.line == 0 { caches.line = leaf.line }
    }
    caches.known = caches.l1d != 0 || caches.l2 != 0 || caches.l3 != 0
    return caches
}

// The ladder of x86: every step needs the one below and its own features. AVX512 asks for F, DQ, BW and VL (Skylake-X and later, Zen 4 and later): Knights Landing, which has
// F, CD, ER and PF only, stays at AVX2.
LevelFromFeatures :: proc "contextless" (features: Features) -> Level {
    if .NEON in features { return .NEON }
    if .SIMD128 in features { return .SIMD128 }
    if .SSE2 not_in features { return .SCALAR }
    level: Level = .SSE2
    if .SSE3 not_in features { return level }
    level = .SSE3
    if .SSSE3 not_in features { return level }
    level = .SSSE3
    if .SSE41 not_in features { return level }
    level = .SSE41
    if .SSE42 not_in features { return level }
    level = .SSE42
    if .AVX not_in features { return level }
    level = .AVX
    if .AVX2 not_in features || .FMA not_in features { return level }
    level = .AVX2
    wide: Features = {.AVX512F, .AVX512DQ, .AVX512BW, .AVX512VL}
    if wide <= features { level = .AVX512 }
    return level
}

// A record from a list of features (and the vendor string, which the throttling rule needs: "GenuineIntel", "AuthenticAMD"; unknown is taken as not throttling)
CpuFromFeatures :: proc "contextless" (features: Features, vendor: string = "") -> (cpu: Cpu) {
    level: Level = LevelFromFeatures(features)
    cpu = {features = features, level = level, forced = level, family = LevelFamily(level)}
    for i in 0 ..< min(len(vendor), len(cpu.vendor)) { cpu.vendor[i] = vendor[i] }
    cpu.throttles = cpuThrottles(&cpu)
    return
}

// The rule that simdutf8 uses to choose its 512 bit kernel: AVX-512 on an Intel CPU before Ice Lake (no VBMI2) lowers the clock of the whole core while it runs, so the wide
// level is for a program that asks for it and not for every library by default. Written from their note; the dev machine (Zen 5) cannot show it.
@(private)
cpuThrottles :: proc "contextless" (cpu: ^Cpu) -> bool {
    return cpu.level == .AVX512 && .AVX512VBMI2 not_in cpu.features && CpuVendor(cpu) == "GenuineIntel"
}

// Does the machine have the feature (the vector extensions that are not a level: F16C, VNNI, BF16, ARM dot products ...)
CpuHas :: proc "contextless" (cpu: ^Cpu, feature: Feature) -> bool {
    return feature in cpu.features
}

// Adds features that were learned elsewhere (an arm64 program that asked the operating system for SVE); the level is made again
CpuAddFeatures :: proc "contextless" (cpu: ^Cpu, features: Features) {
    cpu.features += features
    cpu.level = LevelFromFeatures(cpu.features)
    cpu.throttles = cpuThrottles(cpu)
}

@(private) cpu_global: Cpu
@(private) cpu_ready: bool

// The machine the program runs on, found on first use (and at start up)
CpuGet :: proc "contextless" () -> ^Cpu {
    if !cpu_ready { cpuInit() }
    return &cpu_global
}

@(init, private)
cpuInitAtStart :: proc "contextless" () {
    cpuInit()
}

@(private)
cpuInit :: proc "contextless" () {
    cpu_global = cpuDetect()
    cpu_global.forced = cpu_global.level
    cpuApplyEnvironment(&cpu_global)
    cpu_ready = true
}

// The best level the machine runs, before any limit
CpuBest :: proc "contextless" () -> Level {
    return CpuGet().level
}

// The level programs use: the best, unless limited by `SIMD_LEVEL` or `CpuForce`
CpuLevel :: proc "contextless" () -> Level {
    cpu: ^Cpu = CpuGet()
    return cpu.forced
}

// Limits every client made or resolved afterwards to `level` (it can only lower: a level the machine does not have is ignored, SCALAR is always allowed). For a program that
// knows a level is broken on its machine, and for measuring one level of a kernel set on a machine that has more. Not for the audio thread.
CpuForce :: proc "contextless" (level: Level) {
    cpu: ^Cpu = CpuGet()
    cpu.forced = LevelClamp(level, cpu.level)
    cpu.was_forced = cpu.forced != cpu.level
    if text_ready { textSelect() }            // the text kernels follow
}

CpuBrand :: proc "contextless" (cpu: ^Cpu) -> string {
    count: int
    for count < len(cpu.brand) && cpu.brand[count] != 0 { count += 1 }
    // the brand string is padded with spaces on one side or the other, depending on the CPU
    start: int
    for start < count && cpu.brand[start] == ' ' { start += 1 }
    for count > start && cpu.brand[count - 1] == ' ' { count -= 1 }
    return string(cpu.brand[start:count])
}

CpuVendor :: proc "contextless" (cpu: ^Cpu) -> string {
    count: int
    for count < len(cpu.vendor) && cpu.vendor[count] != 0 { count += 1 }
    return string(cpu.vendor[:count])
}

FeatureName :: proc "contextless" (feature: Feature) -> string {
    switch feature {
    case .MMX: return "MMX"
    case .SSE: return "SSE"
    case .SSE2: return "SSE2"
    case .SSE3: return "SSE3"
    case .SSSE3: return "SSSE3"
    case .SSE41: return "SSE4.1"
    case .SSE42: return "SSE4.2"
    case .POPCNT: return "POPCNT"
    case .AVX: return "AVX"
    case .F16C: return "F16C"
    case .FMA: return "FMA"
    case .AVX2: return "AVX2"
    case .BMI1: return "BMI1"
    case .BMI2: return "BMI2"
    case .AVX512F: return "AVX512F"
    case .AVX512DQ: return "AVX512DQ"
    case .AVX512BW: return "AVX512BW"
    case .AVX512VL: return "AVX512VL"
    case .AVX512CD: return "AVX512CD"
    case .AVX512VNNI: return "AVX512VNNI"
    case .AVX512VBMI: return "AVX512VBMI"
    case .AVX512VBMI2: return "AVX512VBMI2"
    case .AVX512BF16: return "AVX512BF16"
    case .AVX_VNNI: return "AVX-VNNI"
    case .NEON: return "NEON"
    case .NEON_DOTPROD: return "NEON dot product"
    case .SVE: return "SVE"
    case .FP16: return "FP16"
    case .SIMD128: return "SIMD128"
    }
    return ""
}

// The caches of this machine (what the algorithms that block for a cache read): see `Caches`
CpuCaches :: proc "contextless" () -> Caches {
    return CpuGet().caches
}

// Replaces the sizes that are not 0 (in kilobytes: 0 keeps what the CPU said): a test, a program that knows a machine it cannot ask, `SIMD_L2_KB` in the environment
CacheOverride :: proc "contextless" (caches: ^Caches, l1d_kb, l2_kb, l3_kb: u32) {
    if l1d_kb != 0 { caches.l1d = l1d_kb * 1024 }
    if l2_kb != 0 { caches.l2 = l2_kb * 1024 }
    if l3_kb != 0 { caches.l3 = l3_kb * 1024 }
    if l1d_kb != 0 || l2_kb != 0 || l3_kb != 0 { caches.overridden = true }
}
