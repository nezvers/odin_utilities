package simd_utils

// Which vector instructions this machine runs, which of them a library may use, and which kernel it runs: the dispatch layer that the audio library of odin_plug
// (`dsp`) grew by hand, made reusable. Three small parts that work together or alone:
//
//   cpu.odin       `Cpu`: what CPUID and XGETBV say (features, the operating system's part, the `Level` of the machine), found once at start up. `SIMD_LEVEL=avx2` in the
//                  environment lowers it for a whole program (measuring, a broken driver), `CpuForce` does the same in code.
//   table.odin     `Table($P)`: the kernels of one algorithm, one procedure per `Level`. `TablePick` gives the best one at or below a level, so an algorithm that has no
//                  SSE4.1 version runs its SSE2 one on an SSE4.1 machine, and a machine without any of the wide ones runs the portable procedure.
//   manager.odin   `Manager`: the libraries (clients) of a program, each with a priority and the level it wants, and the policy that decides what each one gets. Wide
//                  units are scarce: AVX-512 can lower the clock of the whole core, and the two threads of a core share one set of vector units. The manager gives the
//                  wide level to the clients of highest priority (a number of slots, a queue by priority for the rest), and the others run the best level below it. A
//                  client that finishes releases its slot and the next one in the queue gets it. Algorithms say what level is worth it (`Table.useful`): a kernel that
//                  does not gain from 512 bits does not take a slot at all.
//
// The rules that the research of odin_plug (its README for this library, `docs/SIMD_LEVELS.md` there) turned into code:
//   - the level is chosen when a plan or a state is made and stored in it, never per call: a kernel never changes level in the middle of a block
//   - every wide kernel has a portable reference and a test that they agree (`LevelsAgree` style tests are the user's: see README)
//   - levels are a ladder (a CPU that has a level has all the levels under it), and a level a kernel does not have falls to the next one below
//
// Limits: x86 and x86-64 are detected completely (CPUID leaf 0, 1, 7, XGETBV, the brand string); arm64 has NEON by definition and the web build has SIMD128 only when the
//     build says so (no run time detection exists there); no cache sizes, no topology, no frequency model: the policy is a rule of the program, not a measurement.
//     Nothing allocates and nothing locks: set the manager up on one thread, read `ClientLevel` anywhere (a single byte).

import "base:intrinsics"

// The instruction sets of the ladder. Within a family (x86, ARM, web) a higher level has everything of the lower ones; `SCALAR` is the portable code and is in every family.
Level :: enum u8 {
    SCALAR,         // no vector instructions assumed: the portable code (x87 only builds of 32 bit x86, a target without SIMD)
    SSE2,           // every x86-64 CPU: 128 bit, 4 floats
    SSE3,           // horizontal operations, add / subtract of pairs (2004)
    SSSE3,          // byte shuffles, absolute values (2006)
    SSE41,          // blends, rounding, packed integer maximum (2008)
    SSE42,          // string compare, CRC32, POPCNT (2008): the newest of the 128 bit sets and what `x86-64-v2` means
    AVX,            // 256 bit floats, three operand forms, no FMA and no 256 bit integers (Sandy Bridge, Ivy Bridge, Bulldozer)
    AVX2,           // 256 bit integers and FMA (Haswell, Zen): 8 floats, fused multiply add
    AVX512,         // F, DQ, BW and VL with the operating system saving the ZMM state (Skylake-X, Zen 4): 16 floats
    NEON,           // arm64: 128 bit
    SIMD128,        // the web: 128 bit, only when the build has the feature on
}

Family :: enum u8 {
    NONE,           // scalar only
    X86,
    ARM,
    WEB,
}

LEVEL_COUNT :: len(Level)

LevelFamily :: proc "contextless" (level: Level) -> Family {
    switch level {
    case .SCALAR: return .NONE
    case .SSE2, .SSE3, .SSSE3, .SSE41, .SSE42, .AVX, .AVX2, .AVX512: return .X86
    case .NEON: return .ARM
    case .SIMD128: return .WEB
    }
    return .NONE
}

// The next level down the ladder, SCALAR at the bottom (and for the lone levels of the other families)
LevelBelow :: proc "contextless" (level: Level) -> Level {
    switch level {
    case .SCALAR, .NEON, .SIMD128, .SSE2: return .SCALAR
    case .SSE3: return .SSE2
    case .SSSE3: return .SSE3
    case .SSE41: return .SSSE3
    case .SSE42: return .SSE41
    case .AVX: return .SSE42
    case .AVX2: return .AVX
    case .AVX512: return .AVX2
    }
    return .SCALAR
}

// How many floats one vector of the level holds
LevelLanes :: proc "contextless" (level: Level) -> int {
    switch level {
    case .SCALAR: return 1
    case .SSE2, .SSE3, .SSSE3, .SSE41, .SSE42, .NEON, .SIMD128: return 4
    case .AVX, .AVX2: return 8
    case .AVX512: return 16
    }
    return 1
}

LevelName :: proc "contextless" (level: Level) -> string {
    switch level {
    case .SCALAR: return "scalar"
    case .SSE2: return "SSE2"
    case .SSE3: return "SSE3"
    case .SSSE3: return "SSSE3"
    case .SSE41: return "SSE4.1"
    case .SSE42: return "SSE4.2"
    case .AVX: return "AVX"
    case .AVX2: return "AVX2 + FMA"
    case .AVX512: return "AVX-512"
    case .NEON: return "NEON"
    case .SIMD128: return "SIMD128"
    }
    return ""
}

// A level by the name an environment variable or a command line gives it ("avx2", "sse4.1", "sse41", "scalar" ...), without regard to case
LevelFromName :: proc "contextless" (name: string) -> (level: Level, ok: bool) {
    lower: [16]u8
    if len(name) > len(lower) { return }
    for i in 0 ..< len(name) {
        c: u8 = name[i]
        lower[i] = c + 32 if c >= 'A' && c <= 'Z' else c
    }
    text: string = string(lower[:len(name)])
    switch text {
    case "scalar", "baseline", "none": return .SCALAR, true
    case "sse2": return .SSE2, true
    case "sse3": return .SSE3, true
    case "ssse3": return .SSSE3, true
    case "sse4.1", "sse41": return .SSE41, true
    case "sse4.2", "sse42", "sse4": return .SSE42, true
    case "avx": return .AVX, true
    case "avx2", "avx2+fma": return .AVX2, true
    case "avx512", "avx-512": return .AVX512, true
    case "neon": return .NEON, true
    case "simd128": return .SIMD128, true
    }
    return
}

// `a` can run on a machine whose best level is `best`: the portable code always can, other levels when they are in the same family and not above it
LevelUsable :: proc "contextless" (level: Level, best: Level) -> bool {
    if level == .SCALAR { return true }
    return LevelFamily(level) == LevelFamily(best) && level <= best
}

// `level` limited to what a machine of best level `best` runs: a level of another family (an x86 wish on an ARM machine) means "the best there is"
LevelClamp :: proc "contextless" (level: Level, best: Level) -> Level {
    if level == .SCALAR { return .SCALAR }
    if LevelFamily(level) != LevelFamily(best) { return best }
    return min(level, best)
}

// The `enable_target_feature` strings of the levels, for the kernels that are compiled for one (a constant, so it can be an attribute):
//
//     @(enable_target_feature = simd_utils.FEATURES_AVX2)
//     sum_avx2 :: proc(values: []f32) -> f32 { ... }
//
// `-slow-unaligned-mem-32` is part of the 256 and 512 bit ones: the generic x86-64 tuning splits every unaligned 256 bit load and store into two halves, which cost
// 1.3 to 2.5 times in the FFT and FIR kernels of odin_plug. The AVX2 set also has FMA (a Haswell has both); a kernel for the AVX level that must not use FMA or 256 bit
// integers is written with the AVX set below and plain multiply and add.
FEATURES_SSE3 :: "sse3"
FEATURES_SSSE3 :: "sse3,ssse3"
FEATURES_SSE41 :: "sse3,ssse3,sse4.1"
FEATURES_SSE42 :: "sse3,ssse3,sse4.1,sse4.2"
FEATURES_AVX :: "sse3,ssse3,sse4.1,sse4.2,avx,-slow-unaligned-mem-32"
FEATURES_AVX2 :: "sse3,ssse3,sse4.1,sse4.2,avx,avx2,fma,-slow-unaligned-mem-32"
FEATURES_AVX512 :: "sse3,ssse3,sse4.1,sse4.2,avx,avx2,fma,avx512f,avx512dq,avx512bw,avx512vl,-slow-unaligned-mem-32"

// The highest level the build itself targets (`-microarch`): kernels of that level and below need no `enable_target_feature` and no run time check
LevelBuild :: proc "contextless" () -> Level {
    when ODIN_ARCH == .amd64 || ODIN_ARCH == .i386 {
        when intrinsics.has_target_feature("avx512f") && intrinsics.has_target_feature("avx512dq") && intrinsics.has_target_feature("avx512bw") && intrinsics.has_target_feature("avx512vl") { return .AVX512 }
        else when intrinsics.has_target_feature("avx2") && intrinsics.has_target_feature("fma") { return .AVX2 }
        else when intrinsics.has_target_feature("avx") { return .AVX }
        else when intrinsics.has_target_feature("sse4.2") { return .SSE42 }
        else when intrinsics.has_target_feature("sse4.1") { return .SSE41 }
        else when intrinsics.has_target_feature("ssse3") { return .SSSE3 }
        else when intrinsics.has_target_feature("sse3") { return .SSE3 }
        else when intrinsics.has_target_feature("sse2") { return .SSE2 }
        else { return .SCALAR }
    } else when ODIN_ARCH == .arm64 || ODIN_ARCH == .arm32 {
        return .NEON
    } else when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 {
        when intrinsics.has_target_feature("simd128") { return .SIMD128 } else { return .SCALAR }
    } else {
        return .SCALAR
    }
}
