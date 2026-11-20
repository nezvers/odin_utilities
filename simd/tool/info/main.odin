package main

// What this machine runs and how the manager would hand it out: `odin run simd/tool/info`. `SIMD_LEVEL=avx2 odin run simd/tool/info` shows a limited machine, `-- --bench` times the
// dot product of simd/example at every level this CPU has (one launch is a screen, not a result: run it a few times).

import "core:fmt"
import "core:os"
import "core:time"
import su "../.."
import example "../../example"

main :: proc() {
    cpu: ^su.Cpu = su.CpuGet()
    fmt.println("cpu     ", su.CpuBrand(cpu) if su.CpuBrand(cpu) != "" else "(no brand string)", "  vendor", su.CpuVendor(cpu))
    fmt.println("family  ", cpu.family, "  best level", su.LevelName(cpu.level), "  in use", su.LevelName(cpu.forced), "(limited)" if cpu.was_forced else "")
    fmt.println("build   ", su.LevelName(su.LevelBuild()), "(what the compiler targets: no enable_target_feature needed up to it)")
    fmt.print("features")
    for feature in su.Feature {
        if feature in cpu.features { fmt.print("", su.FeatureName(feature)) }
    }
    fmt.println()
    fmt.println()
    fmt.println("ladder")
    for level in su.Level {
        if su.LevelFamily(level) != cpu.family && level != .SCALAR { continue }
        marker: string = "  "
        if su.LevelUsable(level, cpu.level) { marker = "ok" }
        if level == cpu.forced { marker = "->" }
        fmt.printf("  %s %-12s %2d lanes\n", marker, su.LevelName(level), su.LevelLanes(level))
    }

    // the manager: three libraries, the audio one first
    fmt.println()
    fmt.println("manager: audio (100), physics (10), images (1, wants AVX2), one wide slot for the favored one")
    manager: su.Manager
    su.ManagerInit(&manager)
    audio, _ := su.ManagerRegister(&manager, "audio", priority = 100)
    physics, _ := su.ManagerRegister(&manager, "physics", priority = 10)
    images, _ := su.ManagerRegister(&manager, "images", priority = 1, wants = .AVX2)
    su.ManagerFavor(&manager, audio)
    line: [160]u8
    for id in ([?]su.ClientId{audio, physics, images}) { fmt.println(" ", su.ManagerExplain(&manager, id, line[:])) }
    su.ManagerRelease(&manager, audio)
    fmt.println("audio stops:")
    for id in ([?]su.ClientId{audio, physics, images}) { fmt.println(" ", su.ManagerExplain(&manager, id, line[:])) }

    for argument in os.args[1:] {
        if argument == "--bench" {
            bench()
            benchText()
        }
    }
}

bench :: proc() {
    fmt.println()
    fmt.println("dot product, 4096 floats, ns per call (best of 5 runs of 20000 calls)")
    table: example.DotTable
    example.DotInit(&table)
    a: [4096]f32
    b: [4096]f32
    for i in 0 ..< len(a) {
        a[i] = f32(i % 17) * 0.1
        b[i] = f32(i % 13) * 0.2
    }
    base: f64
    for level in su.Level {
        if !su.TableHas(&table, level) || !su.LevelUsable(level, su.CpuBest()) { continue }
        kernel, _, _ := su.TablePick(&table, level)
        best: f64 = 1e30
        sink: f32
        for _ in 0 ..< 5 {
            start: time.Tick = time.tick_now()
            for _ in 0 ..< 20000 { sink += kernel(a[:], b[:]) }
            best = min(best, f64(time.duration_nanoseconds(time.tick_since(start))) / 20000)
        }
        if level == .SCALAR { base = best }
        fmt.printf("  %-12s %9.1f ns   %5.2fx  (%v)\n", su.LevelName(level), best, base / best if base > 0 else 1, sink != 0)
    }
}

// The text kernels on 1 MB: English text with some accents and a little CJK (so the validator has real work), GB/s per level
benchText :: proc() {
    fmt.println()
    fmt.println("text kernels, 1 MB (best of 5; GB/s)")
    text: [dynamic]u8
    defer delete(text)
    pieces := [?]string{"The quick brown fox jumps over the lazy dog, again and again. ", "café naïve façade ", "日本語のテキスト ", "plain ASCII text with numbers 0123456789 and symbols ~!@# "}
    for i := 0; len(text) < 1 << 20; i += 1 { append(&text, ..transmute([]u8)pieces[i % len(pieces)]) }
    ascii: [dynamic]u8
    defer delete(ascii)
    for len(ascii) < 1 << 20 { append(&ascii, ..transmute([]u8)pieces[0]) }
    Case :: struct { name: string, run: proc(procs: ^su.TextProcs, bytes: []u8) -> int }
    cases := [?]Case{
        {"ascii_prefix (ASCII)", proc(p: ^su.TextProcs, b: []u8) -> int { return p.ascii_prefix(b) }},
        {"index_of_byte (ASCII)", proc(p: ^su.TextProcs, b: []u8) -> int { return p.index_of_byte(b, 0x1b) }},
        {"rune_count (mixed)", proc(p: ^su.TextProcs, b: []u8) -> int { return p.rune_count(b) }},
        {"utf8_valid (ASCII)", proc(p: ^su.TextProcs, b: []u8) -> int { return p.utf8_valid_up_to(b) }},
        {"utf8_valid (mixed)", proc(p: ^su.TextProcs, b: []u8) -> int { return p.utf8_valid_up_to(b) }},
    }
    fmt.printf("  %-24s", "")
    for level in su.Level { if su.LevelUsable(level, su.CpuBest()) && level != .SCALAR && su.LevelFamily(level) == su.CpuGet().family { fmt.printf(" %10s", su.LevelName(level)) } }
    fmt.printf(" %10s\n", "scalar")
    for test_case, c in cases {
        data: []u8 = ascii[:] if c < 4 else text[:]
        fmt.printf("  %-24s", test_case.name)
        measure :: proc(test_case: Case, level: su.Level, data: []u8) -> f64 {
            procs: ^su.TextProcs = su.TextLevel(level)
            best: f64 = 1e30
            sink: int
            for _ in 0 ..< 5 {
                start: time.Tick = time.tick_now()
                for _ in 0 ..< 20 { sink += test_case.run(procs, data) }
                best = min(best, f64(time.duration_nanoseconds(time.tick_since(start))) / 20)
            }
            _ = sink
            return f64(len(data)) / best
        }
        for level in su.Level {
            if su.LevelUsable(level, su.CpuBest()) && level != .SCALAR && su.LevelFamily(level) == su.CpuGet().family { fmt.printf(" %10.2f", measure(test_case, level, data)) }
        }
        fmt.printf(" %10.2f\n", measure(test_case, .SCALAR, data))
    }
}
