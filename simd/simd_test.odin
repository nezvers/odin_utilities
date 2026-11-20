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
