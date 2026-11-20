#+build !js
package simd_utils

import "core:testing"
import "core:unicode/utf8"

// The levels of the table that this machine runs
@(private = "file")
levelsToTest :: proc() -> (levels: [dynamic]Level) {
    for level in Level {
        if LevelUsable(level, CpuBest()) { append(&levels, level) }
    }
    return
}

@(private = "file")
Random :: struct { state: u32 }

@(private = "file")
next :: proc(random: ^Random) -> u32 {
    random.state = random.state * 1664525 + 1013904223
    return random.state >> 8
}

// The reference of the standard library: the length of the well formed start, a character at a time
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

// Text of every shape: ASCII, valid sequences of two, three and four bytes, the edges of the ranges, stray and cut bytes
@(private = "file")
makeText :: proc(random: ^Random, length: int, damage: u32) -> [dynamic]u8 {
    text: [dynamic]u8
    pieces := [?]string{
        "a", "z", " ", "\n", "The quick brown fox ", "é", "Ж", "߿", "ࠀ", "中", "퟿", "", "￿", "\U00010000", "\U0001F600", "\U0010FFFF",
        "€", " ", "~", "\x7f", "\x00",
    }
    for len(text) < length {
        append(&text, ..transmute([]u8)pieces[next(random) % len(pieces)])
    }
    // damage: random bytes, cut sequences, bytes from the edge cases of the standard
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
    if len(text) > length { resize(&text, length + int(next(random) % 3)) }       // the end may cut a sequence
    return text
}

@(test)
test_every_text_kernel_of_every_level_agrees_with_the_scalar_one :: proc(t: ^testing.T) {
    random: Random = {7}
    levels := levelsToTest()
    defer delete(levels)
    scalar: ^TextProcs = TextLevel(.SCALAR)
    for round in 0 ..< 6000 {
        text := makeText(&random, int(next(&random) % 300), next(&random) % 4)
        defer delete(text)
        bytes: []u8 = text[:]
        for level in levels {
            procs: ^TextProcs = TextLevel(level)
            testing.expectf(t, procs.ascii_prefix(bytes) == scalar.ascii_prefix(bytes), "%v ascii_prefix, round %d", level, round)
            testing.expectf(t, procs.ascii_run(bytes) == scalar.ascii_run(bytes), "%v ascii_run, round %d", level, round)
            needle: u8 = u8(next(&random) % 4) + 0x1b if round % 3 == 0 else (bytes[int(next(&random)) % max(len(bytes), 1)] if len(bytes) > 0 else 0)
            testing.expectf(t, procs.index_of_byte(bytes, needle) == scalar.index_of_byte(bytes, needle), "%v index_of_byte, round %d", level, round)
            set: [4]u8 = {u8(next(&random)), ' ', '\n', 0x1b}
            testing.expectf(t, procs.index_of_any(bytes, set) == scalar.index_of_any(bytes, set), "%v index_of_any, round %d", level, round)
            got_at, got_ascii := procs.scan_text(bytes, needle)
            want_at, want_ascii := scalar.scan_text(bytes, needle)
            testing.expectf(t, got_at == want_at && got_ascii == want_ascii, "%v scan_text, round %d: %d %v, expected %d %v", level, round, got_at, got_ascii, want_at, want_ascii)
            testing.expectf(t, procs.rune_count(bytes) == scalar.rune_count(bytes), "%v rune_count, round %d", level, round)
            expected: int = referenceValidUpTo(bytes)
            testing.expectf(t, procs.utf8_valid_up_to(bytes) == expected, "%v utf8_valid_up_to, round %d: %d, expected %d", level, round, procs.utf8_valid_up_to(bytes), expected)
        }
    }
}

// Every length and every position of the byte that ends a run, for the scans, from every start (the vector steps and the tails)
@(test)
test_the_scans_find_the_first_byte_at_every_position_and_length :: proc(t: ^testing.T) {
    levels := levelsToTest()
    defer delete(levels)
    buffer: [200]u8
    for level in levels {
        procs: ^TextProcs = TextLevel(level)
        for start in 0 ..< 5 {
            for length in 0 ..< len(buffer) - 5 {
                for i in 0 ..< len(buffer) { buffer[i] = 'a' }
                bytes: []u8 = buffer[start:start + length]
                testing.expect_value(t, procs.index_of_byte(bytes, 'z'), length)
                testing.expect_value(t, procs.ascii_prefix(bytes), length)
                testing.expect_value(t, procs.ascii_run(bytes), length)
                testing.expect_value(t, procs.rune_count(bytes), length)
                if length > 0 {
                    position: int = (length * 7) % length
                    bytes[position] = 'z'
                    testing.expect_value(t, procs.index_of_byte(bytes, 'z'), position)
                    at, ascii := procs.scan_text(bytes, 'z')
                    testing.expect(t, at == position && ascii)
                    bytes[position] = 0xE2
                    testing.expect_value(t, procs.ascii_prefix(bytes), position)
                    testing.expect_value(t, procs.ascii_run(bytes), position)
                    at, ascii = procs.scan_text(bytes, 'z')
                    testing.expect(t, at == length && !ascii)
                    bytes[position] = 0x1b
                    testing.expect_value(t, procs.ascii_run(bytes), position)
                    testing.expect_value(t, procs.ascii_prefix(bytes), length)
                }
            }
        }
    }
}

@(test)
test_the_maximal_subpart_rule_and_the_examples_of_the_standard :: proc(t: ^testing.T) {
    // sizes of the errors and valid characters, in order
    Case :: struct { text: string, parts: []int }
    cases := [?]Case{
        {"abc", {1, 1, 1}},
        {"\xF0\x80\x80\x80", {1, 1, 1, 1}},                      // F0 needs 90 to BF next: F0 alone, then three continuation bytes
        {"\xE0\x80", {1, 1}},
        {"\xE1\x80", {2}},                                       // cut short: one error for the valid start
        {"\xE1\x80\xC2", {2, 1}},
        {"\xED\xA0\x80", {1, 1, 1}},                             // a surrogate
        {"\xC0\x80", {1, 1}},                                    // overlong
        {"\xC1\xBF", {1, 1}},
        {"\xF4\x90\x80\x80", {1, 1, 1, 1}},                      // above U+10FFFF
        {"\xF5\x80\x80\x80", {1, 1, 1, 1}},
        {"\x80", {1}},
        {"\xFF\xFE", {1, 1}},
        {"a\xF1\x80\x80\xE1\x80\xC2b", {1, 3, 2, 1, 1}},          // the example of the W3C and the Unicode standard, table 3-8
        {"\xE2\x82\xAC", {3}},                                   // the euro sign
        {"\xF0\x9F\x98\x80", {4}},
        {"\xF0\x9F\x98", {3}},                                   // a face cut short
        {"\xEF\xBF\xBD", {3}},                                   // U+FFFD itself is a character of three bytes
    }
    for test_case in cases {
        bytes: []u8 = transmute([]u8)test_case.text
        at: int
        for expected in test_case.parts {
            _, size := Utf8Next(bytes, at)
            testing.expectf(t, size == expected, "%q at %d: size %d, expected %d", test_case.text, at, size, expected)
            at += max(size, 1)
        }
        testing.expectf(t, at == len(bytes), "%q: the parts do not cover the text", test_case.text)
    }
    // the character itself
    character, size := Utf8Next(transmute([]u8)string("\xE2\x82\xAC!"), 0)
    testing.expect(t, character == 0x20AC && size == 3)
    character, size = Utf8Next(transmute([]u8)string("\xF0\x9F\x98\x80"), 0)
    testing.expect(t, character == 0x1F600 && size == 4)
    _, size = Utf8Next(nil, 0)
    testing.expect_value(t, size, 0)
    // agreement with the standard library on text that is well formed
    random: Random = {99}
    for _ in 0 ..< 500 {
        text := makeText(&random, 100, 0)
        defer delete(text)
        at: int
        for at < len(text) {
            mine, my_size := Utf8Next(text[:], at)
            theirs, their_size := utf8.decode_rune(text[at:])
            // a character the standard library accepts is the same here; one it rejects is an error here too (its size is the whole subpart: the standard library says 1)
            standard_ok: bool = !(theirs == utf8.RUNE_ERROR && their_size <= 1)
            if standard_ok && (mine != theirs || my_size != their_size) || !standard_ok && (mine != utf8.RUNE_ERROR || my_size < 1) {
                testing.expectf(t, false, "at %d: %v %d, the standard library: %v %d", at, mine, my_size, theirs, their_size)
                return
            }
            at += my_size
        }
    }
}

@(test)
test_a_chunk_is_cut_only_where_the_next_chunk_can_finish_a_character :: proc(t: ^testing.T) {
    check :: proc(t: ^testing.T, text: string, expected: int) {
        testing.expectf(t, Utf8TrimPartial(transmute([]u8)text) == expected, "%q: %d, expected %d", text, Utf8TrimPartial(transmute([]u8)text), expected)
    }
    check(t, "", 0)
    check(t, "abc", 3)
    check(t, "ab\xE2", 2)                    // a three byte character with its first byte
    check(t, "ab\xE2\x82", 2)                // and with two
    check(t, "ab\xE2\x82\xAC", 5)            // whole
    check(t, "ab\xF0\x9F\x98", 2)            // a four byte one with three
    check(t, "ab\xF0\x9F\x98\x80", 6)
    check(t, "ab\xC3", 2)
    check(t, "ab\xC3\xA9", 4)
    check(t, "ab\xC0", 3)                    // C0 is an error, not a start: nothing to wait for
    check(t, "ab\xF5", 3)
    check(t, "ab\xE0\x80", 4)                // E0 80 is not the start of anything well formed: errors now
    check(t, "ab\x80", 3)                    // a lone continuation byte
    check(t, "ab\xE2\x82\x82\x82", 6)        // too many continuation bytes: the last is an error, nothing is kept
    // text cut anywhere and put together again is the same text
    text: string = "aé€\U0001F600z中"
    bytes: []u8 = transmute([]u8)text
    for cut in 0 ..= len(bytes) {
        keep: int = Utf8TrimPartial(bytes[:cut])
        testing.expect(t, keep <= cut && Utf8ValidUpTo(bytes[:keep]) == keep)
    }
}

@(test)
test_a_text_is_cleaned_with_one_replacement_per_bad_subpart :: proc(t: ^testing.T) {
    out: [64]u8
    clean :: proc(text: string, out: []u8) -> string {
        count: int = Utf8Clean(transmute([]u8)text, out)
        return string(out[:count])
    }
    testing.expect_value(t, clean("hello", out[:]), "hello")
    testing.expect_value(t, clean("a\xF1\x80\x80\xE1\x80\xC2b", out[:]), "a���b")
    testing.expect_value(t, clean("\x80\x80", out[:]), "��")
    testing.expect_value(t, clean("caf\xC3\xA9 \xFF", out[:]), "café �")
    testing.expect_value(t, clean("", out[:]), "")
    // a full output stops before a character that does not fit, never in the middle of one
    small: [4]u8
    testing.expect_value(t, clean("ab€", small[:]), "ab")
    testing.expect_value(t, clean("a€", small[:]), "a€")
    // every result is valid
    random: Random = {5}
    for _ in 0 ..< 300 {
        text := makeText(&random, 80, 6)
        defer delete(text)
        buffer: [400]u8
        count: int = Utf8Clean(text[:], buffer[:])
        testing.expect(t, Utf8Valid(buffer[:count]))
    }
}

@(test)
test_forcing_a_lower_level_changes_the_kernels_the_plain_procedures_use :: proc(t: ^testing.T) {
    text: [100]u8
    for i in 0 ..< len(text) { text[i] = 'a' }
    text[60] = 0xE2
    saved: Level = CpuLevel()
    defer CpuForce(saved)
    for level in levelsToTest() {
        CpuForce(level)
        testing.expect_value(t, AsciiPrefix(text[:]), 60)
        testing.expect_value(t, IndexOfByte(text[:], 0xE2), 60)
        testing.expect(t, !Utf8Valid(text[:]))
    }
}
