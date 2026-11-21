#+build !js
package simd_utils

import "core:testing"

FULL_X86: Features : {.MMX, .SSE, .SSE2, .SSE3, .SSSE3, .SSE41, .SSE42, .POPCNT, .AVX, .F16C, .FMA, .AVX2, .BMI1, .BMI2, .AVX512F, .AVX512DQ, .AVX512BW, .AVX512VL}

@(test)
test_the_ladder_needs_every_step_and_its_own_features :: proc(t: ^testing.T) {
    testing.expect_value(t, LevelFromFeatures({}), Level.SCALAR)
    testing.expect_value(t, LevelFromFeatures({.MMX, .SSE}), Level.SCALAR)                       // no SSE2: the x87 build
    testing.expect_value(t, LevelFromFeatures({.SSE2}), Level.SSE2)
    testing.expect_value(t, LevelFromFeatures({.SSE2, .SSE3}), Level.SSE3)
    testing.expect_value(t, LevelFromFeatures({.SSE2, .SSE3, .SSSE3}), Level.SSSE3)
    testing.expect_value(t, LevelFromFeatures({.SSE2, .SSE3, .SSSE3, .SSE41}), Level.SSE41)
    testing.expect_value(t, LevelFromFeatures({.SSE2, .SSE3, .SSSE3, .SSE41, .SSE42}), Level.SSE42)
    // a hole stops the ladder: SSE4.2 without SSSE3 is not a CPU, the answer is what is complete
    testing.expect_value(t, LevelFromFeatures({.SSE2, .SSE3, .SSE41, .SSE42}), Level.SSE3)
    base: Features = {.SSE2, .SSE3, .SSSE3, .SSE41, .SSE42}
    testing.expect_value(t, LevelFromFeatures(base + {.AVX}), Level.AVX)
    testing.expect_value(t, LevelFromFeatures(base + {.AVX, .AVX2}), Level.AVX)                  // AVX2 without FMA (no such CPU, but the rule is explicit)
    testing.expect_value(t, LevelFromFeatures(base + {.AVX, .FMA}), Level.AVX)                   // FMA without AVX2 (Piledriver)
    testing.expect_value(t, LevelFromFeatures(base + {.AVX, .AVX2, .FMA}), Level.AVX2)
    testing.expect_value(t, LevelFromFeatures(base + {.AVX, .AVX2, .FMA, .AVX512F}), Level.AVX2)                     // Knights Landing style: not enough
    testing.expect_value(t, LevelFromFeatures(base + {.AVX, .AVX2, .FMA, .AVX512F, .AVX512DQ, .AVX512BW}), Level.AVX2)
    testing.expect_value(t, LevelFromFeatures(FULL_X86), Level.AVX512)
    testing.expect_value(t, LevelFromFeatures({.NEON}), Level.NEON)
    testing.expect_value(t, LevelFromFeatures({.SIMD128}), Level.SIMD128)
    cpu: Cpu = CpuFromFeatures(FULL_X86)
    testing.expect_value(t, cpu.level, Level.AVX512)
    testing.expect_value(t, cpu.family, Family.X86)
    testing.expect_value(t, CpuFromFeatures({.NEON}).family, Family.ARM)
}

@(test)
test_levels_go_down_the_ladder_and_are_limited_to_the_machine :: proc(t: ^testing.T) {
    chain: [dynamic]Level
    defer delete(chain)
    for level := Level.AVX512; ; level = LevelBelow(level) {
        append(&chain, level)
        if level == .SCALAR { break }
    }
    testing.expect_value(t, len(chain), 9)
    testing.expect_value(t, chain[1], Level.AVX2)
    testing.expect_value(t, LevelBelow(.NEON), Level.SCALAR)
    testing.expect(t, LevelUsable(.SSE3, .AVX2))
    testing.expect(t, !LevelUsable(.AVX2, .SSE42))
    testing.expect(t, LevelUsable(.SCALAR, .SCALAR))
    testing.expect(t, !LevelUsable(.NEON, .AVX2), "another family")
    testing.expect_value(t, LevelClamp(.AVX512, .AVX2), Level.AVX2)
    testing.expect_value(t, LevelClamp(.SSE2, .AVX2), Level.SSE2)
    testing.expect_value(t, LevelClamp(.AVX2, .NEON), Level.NEON)              // an x86 wish on an ARM machine: the best there
    testing.expect_value(t, LevelClamp(.SCALAR, .AVX2), Level.SCALAR)
    testing.expect_value(t, LevelLanes(.SCALAR), 1)
    testing.expect_value(t, LevelLanes(.SSE41), 4)
    testing.expect_value(t, LevelLanes(.AVX2), 8)
    testing.expect_value(t, LevelLanes(.AVX512), 16)
    for expected in ([?]struct { name: string, level: Level } {{"avx2", .AVX2}, {"AVX2", .AVX2}, {"SSE4.1", .SSE41}, {"sse42", .SSE42}, {"Scalar", .SCALAR}, {"baseline", .SCALAR}, {"avx-512", .AVX512}, {"neon", .NEON}}) {
        level, ok := LevelFromName(expected.name)
        testing.expectf(t, ok && level == expected.level, "%s", expected.name)
    }
    _, ok := LevelFromName("avx3")
    testing.expect(t, !ok)
    _, ok = LevelFromName("a name that is much too long to be one")
    testing.expect(t, !ok)
}

@(test)
test_this_machine_is_found_and_the_levels_agree_with_it :: proc(t: ^testing.T) {
    cpu: ^Cpu = CpuGet()
    testing.expect(t, cpu.level == LevelFromFeatures(cpu.features), "the level is the one the features give")
    testing.expect(t, cpu.forced <= cpu.level || LevelFamily(cpu.forced) != LevelFamily(cpu.level))
    when ODIN_ARCH == .amd64 {
        testing.expect(t, cpu.level >= .SSE2, "every x86-64 CPU has SSE2")
        testing.expect_value(t, cpu.family, Family.X86)
        testing.expect(t, len(CpuVendor(cpu)) == 12, "the vendor string")
        // AVX2 implies AVX, AVX-512 implies AVX2: the operating system part is applied the same way
        if .AVX2 in cpu.features { testing.expect(t, .AVX in cpu.features) }
        if .AVX512F in cpu.features { testing.expect(t, .AVX2 in cpu.features) }
        // what the build targets is never above what the CPU has when the program runs
        testing.expect(t, LevelBuild() <= cpu.level, "the build target is a level the CPU runs")
    }
    when ODIN_ARCH == .arm64 {
        testing.expect_value(t, cpu.level, Level.NEON)
    }
}

@(test)
test_a_table_picks_the_best_kernel_at_or_below_the_level :: proc(t: ^testing.T) {
    Kernel :: #type proc "contextless" (x: int) -> int
    table: Table(Kernel)
    _, _, ok := TablePick(&table, .AVX512)
    testing.expect(t, !ok, "an empty table has nothing")
    TableSet(&table, .SCALAR, proc "contextless" (x: int) -> int { return x })
    TableSet(&table, .SSE2, proc "contextless" (x: int) -> int { return x + 1 })
    TableSet(&table, .AVX2, proc "contextless" (x: int) -> int { return x + 2 })
    testing.expect(t, TableHas(&table, .AVX2) && !TableHas(&table, .AVX))
    testing.expect_value(t, TableLevels(&table), bit_set[Level]{.SCALAR, .SSE2, .AVX2})
    check :: proc(t: ^testing.T, table: ^Table(Kernel), level: Level, expected_level: Level, expected: int) {
        kernel, got, ok := TablePick(table, level)
        testing.expectf(t, ok && got == expected_level && kernel(10) == expected, "at %v: got %v", level, got)
    }
    check(t, &table, .AVX512, .AVX2, 12)                // no 16 lane kernel yet: the AVX2 one
    check(t, &table, .AVX2, .AVX2, 12)
    check(t, &table, .AVX, .SSE2, 11)                   // no AVX kernel: the 128 bit one
    check(t, &table, .SSE42, .SSE2, 11)
    check(t, &table, .SSE2, .SSE2, 11)
    check(t, &table, .SCALAR, .SCALAR, 10)
    check(t, &table, .NEON, .SCALAR, 10)                // another family: the portable one
    // a table without the portable kernel and a level under all of its kernels
    wide_only: Table(Kernel)
    TableSet(&wide_only, .AVX2, proc "contextless" (x: int) -> int { return x })
    _, _, ok = TablePick(&wide_only, .SSE42)
    testing.expect(t, !ok)
    // useful: never above the level that pays
    TableUseful(&table, .SSE2)
    kernel, got, found := TablePickFor(&table, .AVX512)
    _ = kernel
    when ODIN_ARCH == .amd64 {
        testing.expect(t, found && got <= .SSE2)
    }
    TableUseful(&table, .SCALAR)
    _, got, found = TablePickFor(&table, .AVX512)
    testing.expect(t, found && got == .SCALAR, "scalar is a level a kernel can be best at (a gather that does not pay)")
}

@(private = "file")
audioCpu :: proc() -> Cpu {
    return CpuFromFeatures(FULL_X86)
}

@(test)
test_without_a_policy_every_client_gets_the_best_it_asked_for :: proc(t: ^testing.T) {
    cpu: Cpu = audioCpu()
    manager: Manager
    ManagerInit(&manager, &cpu)
    audio, _ := ManagerRegister(&manager, "audio", priority = 100)
    physics, _ := ManagerRegister(&manager, "physics", priority = 10)
    images, _ := ManagerRegister(&manager, "images", priority = 1, wants = .AVX2)
    codec, _ := ManagerRegister(&manager, "codec", wants = .SSE41, ceiling = .SSE2)
    testing.expect_value(t, ClientLevel(&manager, audio), Level.AVX512)
    testing.expect_value(t, ClientLevel(&manager, physics), Level.AVX512)
    testing.expect_value(t, ClientLevel(&manager, images), Level.AVX2)
    testing.expect_value(t, ClientInfo(&manager, images).reason, Reason.WANTED)
    testing.expect_value(t, ClientLevel(&manager, codec), Level.SSE2)
    testing.expect_value(t, ClientInfo(&manager, codec).reason, Reason.CEILING)
    testing.expect_value(t, ClientLevel(&manager, 0), Level.SCALAR)
    testing.expect_value(t, ClientLevel(&manager, 9), Level.SCALAR)
    // the same programs on an AVX2 machine: what they ask for is limited to what it has
    avx2: Cpu = CpuFromFeatures(FULL_X86 - {.AVX512F, .AVX512DQ, .AVX512BW, .AVX512VL})
    small: Manager
    ManagerInit(&small, &avx2)
    first, _ := ManagerRegister(&small, "first", wants = .AVX512)
    testing.expect_value(t, ClientLevel(&small, first), Level.AVX2)
    testing.expect_value(t, ClientInfo(&small, first).reason, Reason.MACHINE)
    // and on a machine of another family
    arm: Cpu = CpuFromFeatures({.NEON})
    other: Manager
    ManagerInit(&other, &arm)
    third, _ := ManagerRegister(&other, "third", wants = .AVX2)
    testing.expect_value(t, ClientLevel(&other, third), Level.NEON)
}

@(test)
test_the_favored_client_takes_the_wide_slot_and_the_others_queue_by_priority :: proc(t: ^testing.T) {
    cpu: Cpu = audioCpu()
    manager: Manager
    ManagerInit(&manager, &cpu)
    images, _ := ManagerRegister(&manager, "images", priority = 1)
    physics, _ := ManagerRegister(&manager, "physics", priority = 10)
    audio, _ := ManagerRegister(&manager, "audio", priority = 5)
    generation: u32 = ManagerGeneration(&manager)
    ManagerFavor(&manager, audio)
    testing.expect(t, ManagerGeneration(&manager) > generation, "a change counts a generation")
    testing.expect_value(t, ClientLevel(&manager, audio), Level.AVX512)
    testing.expect(t, ClientInfo(&manager, audio).wide && ClientInfo(&manager, audio).priority > 10, "the favored one is first")
    // the others run the level below wide, in the queue in the order of priority
    testing.expect_value(t, ClientLevel(&manager, physics), Level.AVX2)
    testing.expect_value(t, ClientLevel(&manager, images), Level.AVX2)
    testing.expect_value(t, ClientInfo(&manager, physics).reason, Reason.QUEUED)
    testing.expect_value(t, ClientInfo(&manager, physics).queue, 1)
    testing.expect_value(t, ClientInfo(&manager, images).queue, 2)
    // no change, no new generation
    generation = ManagerGeneration(&manager)
    ManagerResolve(&manager)
    testing.expect_value(t, ManagerGeneration(&manager), generation)
    // the favored one stops: its slot goes to the next in the queue, and the one after still waits
    ManagerRelease(&manager, audio)
    testing.expect_value(t, ClientLevel(&manager, audio), Level.SCALAR)
    testing.expect_value(t, ClientInfo(&manager, audio).reason, Reason.IDLE)
    testing.expect_value(t, ClientLevel(&manager, physics), Level.AVX512)
    testing.expect(t, ClientInfo(&manager, physics).wide && ClientInfo(&manager, physics).queue == 0)
    testing.expect_value(t, ClientLevel(&manager, images), Level.AVX2)
    testing.expect_value(t, ClientInfo(&manager, images).queue, 1)
    // it starts again: it has the higher priority and takes the slot back
    ManagerAcquire(&manager, audio)
    testing.expect_value(t, ClientLevel(&manager, audio), Level.AVX512)
    testing.expect_value(t, ClientLevel(&manager, physics), Level.AVX2)
    // more slots: two wide at once
    ManagerSetPolicy(&manager, {wide = .AVX512, slots = 2})
    testing.expect_value(t, ClientLevel(&manager, physics), Level.AVX512)
    testing.expect_value(t, ClientLevel(&manager, images), Level.AVX2)
    // a client that wants no more than AVX2 never needs a slot
    ManagerSetWants(&manager, images, .AVX2)
    testing.expect_value(t, ClientInfo(&manager, images).queue, 0)
    testing.expect_value(t, ClientInfo(&manager, images).reason, Reason.WANTED)
    // a late client of higher priority than everyone: it takes a slot from the lowest of the holders
    late, _ := ManagerRegister(&manager, "late", priority = 500)
    testing.expect_value(t, ClientLevel(&manager, late), Level.AVX512)
    testing.expect_value(t, ClientLevel(&manager, audio), Level.AVX512)
    testing.expect_value(t, ClientLevel(&manager, physics), Level.AVX2)
}

@(test)
test_a_machine_without_the_wide_level_has_nothing_to_queue_and_a_forced_level_limits_everyone :: proc(t: ^testing.T) {
    avx2: Cpu = CpuFromFeatures(FULL_X86 - {.AVX512F, .AVX512DQ, .AVX512BW, .AVX512VL})
    manager: Manager
    ManagerInit(&manager, &avx2)
    first, _ := ManagerRegister(&manager, "first", priority = 2)
    second, _ := ManagerRegister(&manager, "second", priority = 1)
    ManagerFavor(&manager, first)
    testing.expect_value(t, ClientLevel(&manager, first), Level.AVX2)
    testing.expect_value(t, ClientLevel(&manager, second), Level.AVX2)
    testing.expect_value(t, ClientInfo(&manager, second).queue, 0)
    // SIMD_LEVEL or CpuForce lowered the machine: reason FORCED, and a client that asked for less keeps its own
    avx2.forced = .SSE42
    ManagerResolve(&manager)
    testing.expect_value(t, ClientLevel(&manager, first), Level.SSE42)
    testing.expect_value(t, ClientInfo(&manager, first).reason, Reason.FORCED)
    ManagerSetWants(&manager, second, .SSE3)
    testing.expect_value(t, ClientLevel(&manager, second), Level.SSE3)
    avx2.forced = .SCALAR
    ManagerResolve(&manager)
    testing.expect_value(t, ClientLevel(&manager, first), Level.SCALAR)
    // too many clients
    full: Manager
    ManagerInit(&full, &avx2)
    for _ in 0 ..< MANAGER_CLIENTS {
        _, ok := ManagerRegister(&full, "x")
        testing.expect(t, ok)
    }
    _, ok := ManagerRegister(&full, "one too many")
    testing.expect(t, !ok)
}

@(test)
test_a_client_selects_the_kernel_of_its_level_and_not_above_what_the_algorithm_is_worth :: proc(t: ^testing.T) {
    Kernel :: #type proc "contextless" (x: int) -> int
    wide: Table(Kernel)
    TableSet(&wide, .SCALAR, proc "contextless" (x: int) -> int { return 0 })
    TableSet(&wide, .AVX2, proc "contextless" (x: int) -> int { return 2 })
    TableSet(&wide, .AVX512, proc "contextless" (x: int) -> int { return 5 })
    gather: Table(Kernel)
    TableSet(&gather, .SCALAR, proc "contextless" (x: int) -> int { return 0 })
    TableSet(&gather, .AVX2, proc "contextless" (x: int) -> int { return 2 })
    TableUseful(&gather, .SCALAR)                       // the scalar four sums beat the gather kernel
    cpu: Cpu = audioCpu()
    manager: Manager
    ManagerInit(&manager, &cpu)
    audio, _ := ManagerRegister(&manager, "audio", priority = 9)
    physics, _ := ManagerRegister(&manager, "physics", priority = 1)
    ManagerFavor(&manager, audio)
    kernel, got, ok := ManagerSelect(&manager, audio, &wide)
    testing.expect(t, ok && got == .AVX512 && kernel(0) == 5)
    kernel, got, ok = ManagerSelect(&manager, physics, &wide)
    testing.expect(t, ok && got == .AVX2 && kernel(0) == 2, "the queued client runs the level below")
    kernel, got, ok = ManagerSelect(&manager, audio, &gather)
    testing.expect(t, ok && got == .SCALAR && kernel(0) == 0, "an algorithm that does not gain from width runs the portable kernel")
    capped: Table(Kernel)
    TableSet(&capped, .SCALAR, proc "contextless" (x: int) -> int { return 0 })
    TableSet(&capped, .SSE42, proc "contextless" (x: int) -> int { return 4 })
    TableSet(&capped, .AVX2, proc "contextless" (x: int) -> int { return 2 })
    TableUseful(&capped, .SSE42)
    _, got, ok = ManagerSelect(&manager, audio, &capped)
    testing.expect(t, ok && got == .SSE42)
}

@(test)
test_the_explanation_names_the_level_and_why :: proc(t: ^testing.T) {
    cpu: Cpu = audioCpu()
    manager: Manager
    ManagerInit(&manager, &cpu)
    audio, _ := ManagerRegister(&manager, "audio", priority = 9)
    physics, _ := ManagerRegister(&manager, "physics", priority = 1)
    buffer: [128]u8
    testing.expect_value(t, ManagerExplain(&manager, audio, buffer[:]), "audio: AVX-512 (the best this machine runs)")
    ManagerFavor(&manager, audio)
    testing.expect_value(t, ManagerExplain(&manager, audio, buffer[:]), "audio: AVX-512 (the best this machine runs, wide slot)")
    testing.expect_value(t, ManagerExplain(&manager, physics, buffer[:]), "physics: AVX2 + FMA (waiting for a wide slot, place 1 in the queue)")
    testing.expect_value(t, ManagerExplain(&manager, 0, buffer[:]), "")
}

@(test)
test_a_cpu_that_lowers_its_clock_for_avx512_gives_it_only_to_a_client_that_names_it :: proc(t: ^testing.T) {
    base: Features = FULL_X86
    skylake: Cpu = CpuFromFeatures(base, "GenuineIntel")                      // AVX-512 without VBMI2: Skylake-X, Cascade Lake
    ice_lake: Cpu = CpuFromFeatures(base + {.AVX512VBMI2}, "GenuineIntel")    // Ice Lake and later
    zen4: Cpu = CpuFromFeatures(base + {.AVX512VBMI2}, "AuthenticAMD")
    amd_without: Cpu = CpuFromFeatures(base, "AuthenticAMD")                  // an AMD CPU is not taken as throttling whatever the features say
    unknown: Cpu = CpuFromFeatures(base)
    testing.expect(t, skylake.throttles && !ice_lake.throttles && !zen4.throttles && !amd_without.throttles && !unknown.throttles)
    testing.expect_value(t, CpuVendor(&skylake), "GenuineIntel")
    avx2_only: Cpu = CpuFromFeatures(FULL_X86 - {.AVX512F, .AVX512DQ, .AVX512BW, .AVX512VL}, "GenuineIntel")
    testing.expect(t, !avx2_only.throttles, "no AVX-512, nothing to throttle")

    manager: Manager
    ManagerInit(&manager, &skylake)
    everyone, _ := ManagerRegister(&manager, "everyone")                      // asks for the best there is
    named, _ := ManagerRegister(&manager, "named", wants = .AVX512)           // asks for AVX-512 by name
    testing.expect_value(t, ClientLevel(&manager, everyone), Level.AVX2)
    testing.expect_value(t, ClientInfo(&manager, everyone).reason, Reason.THROTTLES)
    testing.expect_value(t, ClientLevel(&manager, named), Level.AVX512)
    buffer: [128]u8
    testing.expect_value(t, ManagerExplain(&manager, everyone, buffer[:]), "everyone: AVX2 + FMA (this CPU lowers its clock for AVX-512)")
    // the program that does not care
    policy: Policy = manager.policy
    policy.allow_throttling = true
    ManagerSetPolicy(&manager, policy)
    testing.expect_value(t, ClientLevel(&manager, everyone), Level.AVX512)
    // the others: the best level, as before
    for cpu in ([?]^Cpu{&ice_lake, &zen4, &amd_without, &unknown}) {
        other: Manager
        ManagerInit(&other, cpu)
        client, _ := ManagerRegister(&other, "client")
        testing.expect_value(t, ClientLevel(&other, client), Level.AVX512)
    }
}

@(test)
test_features_that_are_not_levels_are_asked_with_cpu_has :: proc(t: ^testing.T) {
    cpu: Cpu = CpuFromFeatures({.SSE2, .SSE3, .SSSE3, .SSE41, .SSE42, .AVX, .AVX2, .FMA, .F16C, .AVX_VNNI})
    testing.expect(t, CpuHas(&cpu, .F16C) && CpuHas(&cpu, .AVX_VNNI) && !CpuHas(&cpu, .AVX512BF16))
    testing.expect_value(t, cpu.level, Level.AVX2)
    arm: Cpu = CpuFromFeatures({.NEON})
    testing.expect(t, !CpuHas(&arm, .SVE))
    CpuAddFeatures(&arm, {.SVE, .NEON_DOTPROD})                                // learned from the operating system by the program
    testing.expect(t, CpuHas(&arm, .SVE) && CpuHas(&arm, .NEON_DOTPROD))
    testing.expect_value(t, arm.level, Level.NEON)
    testing.expect_value(t, FeatureName(.AVX512VBMI2), "AVX512VBMI2")
    // the machine this runs on: a feature implies the ones it needs
    host: ^Cpu = CpuGet()
    if CpuHas(host, .AVX512VBMI2) { testing.expect(t, CpuHas(host, .AVX512BW) && CpuHas(host, .AVX512F)) }
}

@(test)
test_a_kernel_with_a_range_of_sizes_is_picked_only_for_those_sizes :: proc(t: ^testing.T) {
    Kernel :: #type proc "contextless" (x: int) -> int
    table: Table(Kernel)
    TableSet(&table, .SCALAR, proc "contextless" (x: int) -> int { return 1 })
    TableSet(&table, .AVX2, proc "contextless" (x: int) -> int { return 2 })
    // the 512 bit kernel is for 8192 points and under, the other one for every size
    TableSetRange(&table, .AVX512, proc "contextless" (x: int) -> int { return 5 }, 0, 8192)
    TableSetRange(&table, .SSE42, proc "contextless" (x: int) -> int { return 4 }, 64, 0)       // from 64 points up
    kernel, got, ok := TablePickSized(&table, .AVX512, 1024)
    testing.expect(t, ok && got == .AVX512 && kernel(0) == 5)
    kernel, got, ok = TablePickSized(&table, .AVX512, 8192)
    testing.expect(t, ok && got == .AVX512 && kernel(0) == 5)
    kernel, got, ok = TablePickSized(&table, .AVX512, 8193)
    testing.expect(t, ok && got == .AVX2 && kernel(0) == 2, "above the range the next kernel down")
    kernel, got, ok = TablePickSized(&table, .AVX2, 100000)
    testing.expect(t, ok && got == .AVX2 && kernel(0) == 2)
    kernel, got, ok = TablePickSized(&table, .SSE42, 32)
    testing.expect(t, ok && got == .SCALAR && kernel(0) == 1, "the SSE4.2 kernel is for 64 and up")
    kernel, got, ok = TablePickSized(&table, .SSE42, 64)
    testing.expect(t, ok && got == .SSE42 && kernel(0) == 4)
    // through the manager
    cpu: Cpu = CpuFromFeatures(FULL_X86)
    manager: Manager
    ManagerInit(&manager, &cpu)
    audio, _ := ManagerRegister(&manager, "audio")
    kernel, got, ok = ManagerSelectSized(&manager, audio, &table, 4096)
    testing.expect(t, ok && got == .AVX512)
    kernel, got, ok = ManagerSelectSized(&manager, audio, &table, 65536)
    testing.expect(t, ok && got == .AVX2)
    _ = kernel
}

@(test)
test_the_lanes_of_a_hot_loop_are_twice_the_native_vector_and_the_build_level_is_covered :: proc(t: ^testing.T) {
    testing.expect_value(t, LanesOf(.SCALAR, f32), 1)
    testing.expect_value(t, LanesOf(.SSE2, f32), 8)           // two 4 lane registers
    testing.expect_value(t, LanesOf(.AVX2, f32), 16)
    testing.expect_value(t, LanesOf(.AVX512, f32), 32)
    testing.expect_value(t, LanesOf(.AVX2, f64), 8)
    testing.expect_value(t, LanesOf(.AVX2, u8), 64)
    testing.expect_value(t, LanesOf(.NEON, f32), 8)
    // what the build targets is covered; the portable code always is
    testing.expect(t, BuildCovers(.SCALAR))
    testing.expect(t, BuildCovers(LevelBuild()))
    when ODIN_ARCH == .amd64 { testing.expect(t, BuildCovers(.SSE2)) }
    testing.expect(t, !BuildCovers(.AVX512) || LevelBuild() == .AVX512)
}

// The registers of a CPUID cache leaf for a cache of this geometry (the encoding of leaf 4 / 0x8000001D: ways, partitions and line minus one, sets minus one)
@(private="file")
leafRegisters :: proc(kind, level, ways, partitions, line, sets: u32) -> (eax, ebx, ecx: u32) {
    return kind | level << 5, (ways - 1) << 22 | (partitions - 1) << 12 | (line - 1), sets - 1
}

@(test)
test_a_cache_leaf_gives_its_size_and_the_record_takes_data_and_unified_caches :: proc(t: ^testing.T) {
    // a Zen like core: 48 KB 12 way L1 data, 32 KB L1 instructions, 1 MB 16 way L2, 32 MB 16 way L3
    zen: [4]CacheLeaf
    zen[0] = CacheFromLeaf(leafRegisters(1, 1, 12, 1, 64, 64))
    zen[1] = CacheFromLeaf(leafRegisters(2, 1, 8, 1, 64, 64))
    zen[2] = CacheFromLeaf(leafRegisters(3, 2, 16, 1, 64, 1024))
    zen[3] = CacheFromLeaf(leafRegisters(3, 3, 16, 1, 64, 32768))
    testing.expect_value(t, zen[0].size, u32(48 * 1024))
    testing.expect_value(t, zen[1].size, u32(32 * 1024))
    testing.expect_value(t, zen[2].size, u32(1024 * 1024))
    testing.expect_value(t, zen[3].size, u32(32 * 1024 * 1024))
    caches: Caches = CachesFromLeaves(zen[:])
    testing.expect_value(t, caches.l1d, u32(48 * 1024))                  // the instruction cache is not the L1 data cache
    testing.expect_value(t, caches.l2, u32(1024 * 1024))
    testing.expect_value(t, caches.l3, u32(32 * 1024 * 1024))
    testing.expect_value(t, caches.line, u32(64))
    testing.expect(t, caches.known && !caches.overridden)
    // a Skylake like core: 32 KB 8 way L1 data, 1 MB 16 way L2, 8 MB 16 way L3, the list ends with a leaf of kind 0
    skylake: [4]CacheLeaf
    skylake[0] = CacheFromLeaf(leafRegisters(1, 1, 8, 1, 64, 64))
    skylake[1] = CacheFromLeaf(leafRegisters(3, 2, 16, 1, 64, 1024))
    skylake[2] = CacheFromLeaf(leafRegisters(3, 3, 16, 1, 64, 8192))
    skylake[3] = CacheFromLeaf(0, 0, 0)
    testing.expect_value(t, skylake[3].kind, u8(0))
    caches = CachesFromLeaves(skylake[:])
    testing.expect_value(t, caches.l1d, u32(32 * 1024))
    testing.expect_value(t, caches.l3, u32(8 * 1024 * 1024))
    // nothing known stays nothing known
    testing.expect(t, !CachesFromLeaves({}).known)
}

@(test)
test_cache_sizes_can_be_overridden_and_say_so :: proc(t: ^testing.T) {
    caches: Caches = {l1d = 48 * 1024, l2 = 1024 * 1024, l3 = 32 * 1024 * 1024, line = 64, known = true}
    CacheOverride(&caches, 0, 0, 0)
    testing.expect(t, !caches.overridden)
    CacheOverride(&caches, 0, 2048, 0)
    testing.expect_value(t, caches.l2, u32(2048 * 1024))
    testing.expect_value(t, caches.l1d, u32(48 * 1024))                  // a size of 0 keeps what the CPU said
    testing.expect(t, caches.overridden)
}

@(test)
test_this_machine_reports_its_caches :: proc(t: ^testing.T) {
    caches: Caches = CpuCaches()
    when ODIN_ARCH == .amd64 || ODIN_ARCH == .i386 {
        // every x86-64 CPU this runs on reports a data cache through CPUID (a virtual machine that hides the leaves would fail here: that is worth knowing)
        testing.expect(t, caches.known)
        testing.expect(t, caches.l1d >= 8 * 1024 && caches.l1d <= 1024 * 1024)
        testing.expect(t, caches.line == 64 || caches.line == 32 || caches.line == 128)
        if caches.l2 != 0 { testing.expect(t, caches.l2 >= caches.l1d) }
    } else {
        testing.expect(t, !caches.known)
    }
}
