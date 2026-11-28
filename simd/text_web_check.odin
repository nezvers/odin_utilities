#+build js
package simd_utils

// The text kernels of the top level of a web page (SIMD128) against the scalar ones and the standard library, the same checks as text_test.odin (which is not built for js: core:testing). Run in a
// browser by simd/web_check: the desktop tests cannot say whether the wasm SIMD instructions that the browser runs give the same answers.

import "core:fmt"
import "core:unicode/utf8"

@(private = "file")
Random :: struct { state: u32 }

@(private = "file")
next :: proc(random: ^Random) -> u32 {
    random.state = random.state * 1664525 + 1013904223
    return random.state >> 8
}

@(private = "file")
referenceValidUpTo :: proc(bytes: []u8) -> int {
    at: int
    for at < len(bytes) {
        character, size := utf8.decode_rune(bytes[at:])
        if character == utf8.RUNE_ERROR && size <= 1 { return at }
        at += size
    }
    return at
}

@(private = "file")
makeText :: proc(random: ^Random, length: int, damage: u32) -> [dynamic]u8 {
    text: [dynamic]u8
    pieces := [?]string{
        "a", "z", " ", "\n", "The quick brown fox ", "é", "Ж", "߿", "ࠀ", "中", "퟿", "", "￿", "\U00010000", "\U0001F600", "\U0010FFFF",
        "€", " ", "~", "\x7f", "\x00",
    }
    for len(text) < length { append(&text, ..transmute([]u8)pieces[next(random) % len(pieces)]) }
    edges := [?]u8{0x80, 0xBF, 0xC0, 0xC1, 0xC2, 0xDF, 0xE0, 0xE1, 0xED, 0xEF, 0xF0, 0xF4, 0xF5, 0xFF, 0x90, 0x9F, 0xA0}
    for _ in 0 ..< damage {
        if len(text) == 0 { break }
        at: int = int(next(random)) % len(text)
        switch next(random) % 4 {
        case 0: text[at] = u8(next(random))
        case 1: text[at] = edges[next(random) % len(edges)]
        case 2: inject_at(&text, at, edges[next(random) % len(edges)])
        case 3: ordered_remove(&text, at)
        }
    }
    if len(text) > length { resize(&text, length + int(next(random) % 3)) }
    return text
}

MAX_REPORTED :: 10

// Returns how many checks failed and how many ran; the first failures are printed. `kernels_ran` says the level under test is SIMD128: a build without the feature checks nothing new.
TextWebCheck :: proc() -> (failed: int, ran: int, kernels_ran: bool) {
    level: Level = .SIMD128
    kernels_ran = CpuBest() == level
    scalar: ^TextProcs = TextLevel(.SCALAR)
    procs: ^TextProcs = TextLevel(level)
    check :: proc(ok: bool, failed: ^int, ran: ^int, name: string, round: int) {
        ran^ += 1
        if ok { return }
        failed^ += 1
        if failed^ <= MAX_REPORTED { fmt.println("FAIL", name, "round", round) }
    }

    random: Random = {7}
    for round in 0 ..< 6000 {
        text := makeText(&random, int(next(&random) % 300), next(&random) % 4)
        defer delete(text)
        bytes: []u8 = text[:]
        check(procs.ascii_prefix(bytes) == scalar.ascii_prefix(bytes), &failed, &ran, "ascii_prefix", round)
        check(procs.ascii_run(bytes) == scalar.ascii_run(bytes), &failed, &ran, "ascii_run", round)
        needle: u8 = u8(next(&random) % 4) + 0x1b if round % 3 == 0 else (bytes[int(next(&random)) % max(len(bytes), 1)] if len(bytes) > 0 else 0)
        check(procs.index_of_byte(bytes, needle) == scalar.index_of_byte(bytes, needle), &failed, &ran, "index_of_byte", round)
        set: [4]u8 = {u8(next(&random)), ' ', '\n', 0x1b}
        check(procs.index_of_any(bytes, set) == scalar.index_of_any(bytes, set), &failed, &ran, "index_of_any", round)
        got_at, got_ascii := procs.scan_text(bytes, needle)
        want_at, want_ascii := scalar.scan_text(bytes, needle)
        check(got_at == want_at && got_ascii == want_ascii, &failed, &ran, "scan_text", round)
        check(procs.rune_count(bytes) == scalar.rune_count(bytes), &failed, &ran, "rune_count", round)
        check(procs.utf8_valid_up_to(bytes) == referenceValidUpTo(bytes), &failed, &ran, "utf8_valid_up_to", round)
    }

    // every length and every position of the byte that ends a run, from every start: the vector steps and the tails
    buffer: [200]u8
    for start in 0 ..< 5 {
        for length in 0 ..< len(buffer) - 5 {
            for i in 0 ..< len(buffer) { buffer[i] = 'a' }
            bytes: []u8 = buffer[start:start + length]
            check(procs.index_of_byte(bytes, 'z') == length && procs.ascii_prefix(bytes) == length && procs.ascii_run(bytes) == length && procs.rune_count(bytes) == length, &failed, &ran, "plain run", length)
            if length > 0 {
                position: int = (length * 7) % length
                bytes[position] = 'z'
                at, ascii := procs.scan_text(bytes, 'z')
                check(procs.index_of_byte(bytes, 'z') == position && at == position && ascii, &failed, &ran, "stop byte", length)
                bytes[position] = 0xE2
                at, ascii = procs.scan_text(bytes, 'z')
                check(procs.ascii_prefix(bytes) == position && procs.ascii_run(bytes) == position && at == length && !ascii, &failed, &ran, "non ascii byte", length)
                bytes[position] = 0x1b
                check(procs.ascii_run(bytes) == position && procs.ascii_prefix(bytes) == length, &failed, &ran, "control byte", length)
            }
        }
    }
    return
}
