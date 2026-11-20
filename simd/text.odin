package simd_utils

// Text kernels: the loops that a text program spends its time in, with a kernel per level (the pattern of table.odin) and the portable one as the reference. What ghostty and
// simdutf8 do (`references/ghostty/src/simd`, `references/simdutf8`), written for this library:
//
//     AsciiPrefix(bytes)           how many bytes from the start are ASCII (below 0x80)
//     AsciiRun(bytes)              how many are printable ASCII (0x20 to 0x7e)
//     IndexOfByte(bytes, needle)   where a byte is first (len when it is not there)
//     IndexOfAny(bytes, set)       the first of up to four bytes
//     ScanText(bytes, stop)        where `stop` is first, and whether everything before it is ASCII: one pass for "an ESC or a letter that needs decoding"
//     RuneCount(bytes)             how many characters: the bytes that are not continuation bytes
//     Utf8Valid(bytes)             is it all well formed UTF-8
//     Utf8ValidUpTo(bytes)         how many bytes are well formed, up to the character before the first error
//
// and the scalar pieces every consumer shares, so that one rule decides what a bad byte is (the "maximal subpart" rule of the Unicode standard, table 3-7: one U+FFFD for the
// longest start of a well formed sequence, else one for a single byte; what the web, Go and ghostty do):
//
//     Utf8Next(bytes, at)          the character at `at` and its size in bytes, RUNE_ERROR for a bad subpart (its size is the whole subpart)
//     Utf8TrimPartial(bytes)       how many bytes to keep when a chunk may end inside a character: cuts only a tail that is valid so far
//     Utf8Clean(source, out)       a copy where every bad subpart is U+FFFD
//
// `TextLevel` runs one level on a machine that has more (the tests, a benchmark); the plain procedures use the best level the CPU allows (`CpuLevel`, `SIMD_LEVEL`).
//
// Limits: the vector kernels read the bytes they are given and nothing past them (the tail is scalar); 16, 32 and 64 byte steps for SSE2 / NEON / SIMD128, AVX2, AVX-512; the UTF-8
//     validator is the lookup method of Keiser and Lemire with 16 byte vectors (it needs byte shuffles: SSSE3, NEON and SIMD128 have them) and skips ASCII blocks with the wide scans;
//     no streaming state is kept between calls (`Utf8TrimPartial` and a carry of the caller do it).

import "base:intrinsics"
import "core:unicode/utf8"

// The kernels of the text procedures, one table each
TextProcs :: struct {
    ascii_prefix: proc "contextless" (bytes: []u8) -> int,
    ascii_run: proc "contextless" (bytes: []u8) -> int,
    index_of_byte: proc "contextless" (bytes: []u8, needle: u8) -> int,
    index_of_any: proc "contextless" (bytes: []u8, set: [4]u8) -> int,
    scan_text: proc "contextless" (bytes: []u8, stop: u8) -> (at: int, ascii: bool),
    rune_count: proc "contextless" (bytes: []u8) -> int,
    utf8_valid_up_to: proc "contextless" (bytes: []u8) -> int,
}

@(private) text_tables: [Level]TextProcs
@(private) text_current: ^TextProcs

// The kernels of a level (the best kernel at or below it for each procedure: a level that has no kernel of its own for a procedure runs the one under it)
TextLevel :: proc "contextless" (level: Level) -> ^TextProcs {
    if !text_ready { textInit() }
    return textPick(level)
}

// The table of a level without the start up check (the filling of the tables uses it)
@(private)
textPick :: proc "contextless" (level: Level) -> ^TextProcs {
    at: Level = LevelClamp(level, CpuBest())
    for {
        if text_filled[at] { return &text_tables[at] }
        if at == .SCALAR { break }
        at = LevelBelow(at)
    }
    return &text_tables[.SCALAR]
}

@(private) text_filled: [Level]bool
@(private) text_ready: bool

// Filled at program start (before main and before any thread of a test runner: the tables are plain data after that); also by the first use, for a program that
// calls it before the init procedures have run
@(init, private)
textInitAtStart :: proc "contextless" () {
    textInit()
}

@(private)
textInit :: proc "contextless" () {
    if text_ready { return }
    textFillScalar(&text_tables[.SCALAR])
    text_filled[.SCALAR] = true
    textFillPortable(&text_tables)
    // ladder: a level that is not filled takes what the one below it has, procedure by procedure
    for level in Level {
        if level == .SCALAR { continue }
        if !text_filled[level] { text_tables[level] = text_tables[LevelBelow(level)] ; text_filled[level] = true }
    }
    textSelect()
    text_ready = true                       // last: another thread that sees it ready sees the tables
}

// Chooses the kernels of the level in use. Called at start up and by CpuForce.
@(private)
textSelect :: proc "contextless" () {
    text_current = textPick(CpuLevel())
}

@(private)
textCurrent :: #force_inline proc "contextless" () -> ^TextProcs {
    if text_current == nil { textInit() }
    return text_current
}

AsciiPrefix :: proc "contextless" (bytes: []u8) -> int { return textCurrent().ascii_prefix(bytes) }
AsciiRun :: proc "contextless" (bytes: []u8) -> int { return textCurrent().ascii_run(bytes) }
IndexOfByte :: proc "contextless" (bytes: []u8, needle: u8) -> int { return textCurrent().index_of_byte(bytes, needle) }
IndexOfAny :: proc "contextless" (bytes: []u8, set: [4]u8) -> int { return textCurrent().index_of_any(bytes, set) }
ScanText :: proc "contextless" (bytes: []u8, stop: u8) -> (at: int, ascii: bool) { return textCurrent().scan_text(bytes, stop) }
RuneCount :: proc "contextless" (bytes: []u8) -> int { return textCurrent().rune_count(bytes) }
Utf8ValidUpTo :: proc "contextless" (bytes: []u8) -> int { return textCurrent().utf8_valid_up_to(bytes) }
Utf8Valid :: proc "contextless" (bytes: []u8) -> bool { return textCurrent().utf8_valid_up_to(bytes) == len(bytes) }

// ---- the scalar pieces ----------------------------------------------------------------------------------------------------------------------------------

// The character at bytes[at] and its size. A well formed character is itself; anything else is RUNE_ERROR whose size is the maximal subpart: the longest start of a well formed
// sequence (the lead byte and the continuation bytes that fit the ranges of table 3-7), else one byte. So a cut three byte character is one error of two bytes, a lone continuation
// byte one error of one byte, an overlong lead (C0, C1) and a byte above F4 one error of one byte.
Utf8Next :: proc "contextless" (bytes: []u8, at: int) -> (character: rune, size: int) {
    if at >= len(bytes) { return utf8.RUNE_ERROR, 0 }
    b0: u8 = bytes[at]
    if b0 < 0x80 { return rune(b0), 1 }
    if b0 < 0xC2 || b0 > 0xF4 { return utf8.RUNE_ERROR, 1 }        // a continuation byte, C0, C1, F5 and above
    needed: int
    low: u8 = 0x80
    high: u8 = 0xBF
    switch {
    case b0 <= 0xDF: needed = 2
    case b0 == 0xE0: needed, low = 3, 0xA0
    case b0 == 0xED: needed, high = 3, 0x9F                          // not a surrogate
    case b0 <= 0xEF: needed = 3
    case b0 == 0xF0: needed, low = 4, 0x90
    case b0 == 0xF4: needed, high = 4, 0x8F                          // not above U+10FFFF
    case: needed = 4
    }
    // the first continuation byte has its own range, the next ones 80 to BF
    size = 1
    for size < needed {
        if at + size >= len(bytes) { break }
        b: u8 = bytes[at + size]
        if size == 1 {
            if b < low || b > high { break }
        } else if b < 0x80 || b > 0xBF {
            break
        }
        size += 1
    }
    if size < needed { return utf8.RUNE_ERROR, size }
    switch needed {
    case 2: character = rune(b0 & 0x1F) << 6 | rune(bytes[at + 1] & 0x3F)
    case 3: character = rune(b0 & 0x0F) << 12 | rune(bytes[at + 1] & 0x3F) << 6 | rune(bytes[at + 2] & 0x3F)
    case 4: character = rune(b0 & 0x07) << 18 | rune(bytes[at + 1] & 0x3F) << 12 | rune(bytes[at + 2] & 0x3F) << 6 | rune(bytes[at + 3] & 0x3F)
    }
    return
}

// The same as Utf8Next, and whether the character is well formed (RUNE_ERROR comes back for an error and for U+FFFD itself, which is a character of three bytes)
Utf8Decode :: proc "contextless" (bytes: []u8, at: int) -> (character: rune, size: int, valid: bool) {
    character, size = Utf8Next(bytes, at)
    if character == utf8.RUNE_ERROR {
        valid = size == 3 && bytes[at] == 0xEF && bytes[at + 1] == 0xBF && bytes[at + 2] == 0xBD
    } else {
        valid = size > 0
    }
    return
}

// How many bytes the sequence that starts with `lead` has: 1 for ASCII, 2 to 4 for a lead byte, 0 for a byte that starts nothing (a continuation byte, C0, C1, F5 and above)
Utf8SequenceLength :: proc "contextless" (lead: u8) -> int {
    switch {
    case lead < 0x80: return 1
    case lead < 0xC2: return 0
    case lead <= 0xDF: return 2
    case lead <= 0xEF: return 3
    case lead <= 0xF4: return 4
    }
    return 0
}

// Can the byte `b` be the byte number `position` (1 for the first continuation byte) of the sequence that starts with `lead`: the ranges of table 3-7, for a byte at a time decoder
Utf8ContinuationOk :: proc "contextless" (lead: u8, position: int, b: u8) -> bool {
    if position == 1 {
        low: u8 = 0x80
        high: u8 = 0xBF
        switch lead {
        case 0xE0: low = 0xA0
        case 0xED: high = 0x9F
        case 0xF0: low = 0x90
        case 0xF4: high = 0x8F
        }
        return b >= low && b <= high
    }
    return b >= 0x80 && b <= 0xBF
}

// ---- a decoder that takes the bytes of a stream one at a time ---------------------------------------------------------------------------------------------------

// For a reader that gets text in pieces (a terminal screen, a log, a chat): the few bytes of a character that a piece ended in the middle of. The rule is the one of Utf8Next: a sequence
// that is valid so far waits for the next byte, one that is not is an error at once, with one replacement for its maximal subpart. The zero value is the start.
Utf8Decoder :: struct {
    bytes: [4]u8,
    count: u8,                  // the bytes of an unfinished sequence that are held
    needed: u8,                 // how many it has
}

Utf8Status :: enum u8 {
    MORE,                       // the byte was taken, the character is not whole yet
    CHARACTER,                  // the byte finished a character: `character` is it
    ASCII,                      // an ASCII byte with nothing pending: `character` is it
    ERROR,                      // the byte is bad (it starts nothing: a continuation byte, C0, C1, F5 and above): one replacement character, the byte is taken
    CUT,                        // the byte is NOT taken: it cannot go on with the unfinished sequence, which is one replacement character; push the same byte again
}

Utf8DecoderPending :: proc "contextless" (decoder: ^Utf8Decoder) -> bool {
    return decoder.count > 0
}

Utf8DecoderPush :: proc "contextless" (decoder: ^Utf8Decoder, b: u8) -> (character: rune, status: Utf8Status) {
    if decoder.count > 0 {
        if Utf8ContinuationOk(decoder.bytes[0], int(decoder.count), b) {
            decoder.bytes[decoder.count] = b
            decoder.count += 1
            if decoder.count == decoder.needed {
                character, _ = utf8.decode_rune(decoder.bytes[:decoder.count])
                decoder.count = 0
                return character, .CHARACTER
            }
            return 0, .MORE
        }
        decoder.count = 0
        return utf8.RUNE_ERROR, .CUT
    }
    if b < 0x80 { return rune(b), .ASCII }
    needed: int = Utf8SequenceLength(b)
    if needed == 0 { return utf8.RUNE_ERROR, .ERROR }
    decoder.bytes[0], decoder.count, decoder.needed = b, 1, u8(needed)
    return 0, .MORE
}

// Where a chunk of a stream can be cut so that no character is split: the length to process now. The tail that is the start of a well formed character and is only cut short by the
// end of the chunk (valid so far) stays for the next chunk; a bad byte (C0, C1, F5 and above, a continuation byte, a lead followed by a byte that cannot continue it) is an error
// now and is not kept. Put the kept bytes in front of the next chunk.
Utf8TrimPartial :: proc "contextless" (bytes: []u8) -> int {
    count: int = len(bytes)
    // a lead byte is at most three bytes from the end
    start: int = max(count - 3, 0)
    for at := count - 1; at >= start; at -= 1 {
        b: u8 = bytes[at]
        if b & 0xC0 == 0x80 { continue }                            // a continuation byte: look further back for its lead
        if b < 0xC2 || b > 0xF4 { return count }                    // ASCII or a lead that is an error anyway
        _, size := Utf8Next(bytes, at)
        needed: int = 2 if b <= 0xDF else (3 if b <= 0xEF else 4)
        // the subpart reaches the end of the chunk and is shorter than the character: it may be finished by the next chunk
        if at + size == count && size < needed { return at }
        return count
    }
    return count
}

// A copy of `source` into `out` where every bad subpart is U+FFFD (three bytes): how many bytes were written. Stops when `out` is full (a whole character is never cut).
Utf8Clean :: proc "contextless" (source: []u8, out: []u8) -> int {
    written: int
    at: int
    for at < len(source) {
        // the well formed stretch is copied as it is
        good: int = Utf8ValidUpTo(source[at:])
        if good > 0 {
            n: int = min(good, len(out) - written)
            // do not cut a character when the output is full
            for n > 0 && n < good && source[at + n] & 0xC0 == 0x80 { n -= 1 }
            intrinsics.mem_copy_non_overlapping(&out[written], &source[at], n)
            written += n
            at += n
            if n < good { return written }
            continue
        }
        _, size := Utf8Next(source, at)
        if written + 3 > len(out) { return written }
        out[written], out[written + 1], out[written + 2] = 0xEF, 0xBF, 0xBD
        written += 3
        at += max(size, 1)
    }
    return written
}

// ---- the portable reference ------------------------------------------------------------------------------------------------------------------------------

@(private)
textFillScalar :: proc "contextless" (procs: ^TextProcs) {
    procs.ascii_prefix = asciiPrefixScalar
    procs.ascii_run = asciiRunScalar
    procs.index_of_byte = indexOfByteScalar
    procs.index_of_any = indexOfAnyScalar
    procs.scan_text = scanTextScalar
    procs.rune_count = runeCountScalar
    procs.utf8_valid_up_to = utf8ValidUpToScalar
}

@(private)
asciiPrefixScalar :: proc "contextless" (bytes: []u8) -> int {
    HIGH :: u64(0x8080808080808080)
    at: int
    for at + 8 <= len(bytes) {
        if (intrinsics.unaligned_load(cast(^u64)&bytes[at])) & HIGH != 0 { break }
        at += 8
    }
    for at < len(bytes) && bytes[at] < 0x80 { at += 1 }
    return at
}

@(private)
asciiRunScalar :: proc "contextless" (bytes: []u8) -> int {
    ONES :: u64(0x0101010101010101)
    HIGH :: u64(0x8080808080808080)
    at: int
    for at + 8 <= len(bytes) {
        word: u64 = intrinsics.unaligned_load(cast(^u64)&bytes[at])
        below: u64 = (word - ONES * 0x20) & ~word & HIGH
        del: u64 = word ~ (ONES * 0x7f)
        is_del: u64 = (del - ONES) & ~del & HIGH
        if (word & HIGH) | below | is_del != 0 { break }
        at += 8
    }
    for at < len(bytes) && bytes[at] >= 0x20 && bytes[at] < 0x7f { at += 1 }
    return at
}

@(private)
indexOfByteScalar :: proc "contextless" (bytes: []u8, needle: u8) -> int {
    ONES :: u64(0x0101010101010101)
    HIGH :: u64(0x8080808080808080)
    pattern: u64 = ONES * u64(needle)
    at: int
    for at + 8 <= len(bytes) {
        word: u64 = intrinsics.unaligned_load(cast(^u64)&bytes[at]) ~ pattern
        if (word - ONES) & ~word & HIGH != 0 { break }
        at += 8
    }
    for at < len(bytes) && bytes[at] != needle { at += 1 }
    return at
}

@(private)
indexOfAnyScalar :: proc "contextless" (bytes: []u8, set: [4]u8) -> int {
    for b, i in bytes {
        if b == set[0] || b == set[1] || b == set[2] || b == set[3] { return i }
    }
    return len(bytes)
}

@(private)
scanTextScalar :: proc "contextless" (bytes: []u8, stop: u8) -> (at: int, ascii: bool) {
    at = indexOfByteScalar(bytes, stop)
    return at, asciiPrefixScalar(bytes[:at]) == at
}

@(private)
runeCountScalar :: proc "contextless" (bytes: []u8) -> int {
    count: int
    for b in bytes {
        if b & 0xC0 != 0x80 { count += 1 }
    }
    return count
}

// The validity of the bytes by Utf8Next's rule: the length of the well formed start
@(private)
utf8ValidUpToScalar :: proc "contextless" (bytes: []u8) -> int {
    at: int
    for at < len(bytes) {
        // an ASCII run at a time
        run: int = asciiPrefixScalar(bytes[at:])
        at += run
        if at >= len(bytes) { break }
        character, size := Utf8Next(bytes, at)
        if character == utf8.RUNE_ERROR && !(size == 3 && bytes[at] == 0xEF && bytes[at + 1] == 0xBF && bytes[at + 2] == 0xBD) { return at }
        at += size
    }
    return at
}
