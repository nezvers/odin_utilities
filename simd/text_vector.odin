package simd_utils

// The text kernels with 16 byte vectors of core:simd: the same source is the code of SSE2, of NEON and of SIMD128 (the compiler turns the lane compares, the move mask and the byte
// shuffle into each target's instructions). The x86 kernels with wider vectors are in text_vector_x86.odin.

import "base:intrinsics"
import "core:simd"

@(private) V16 :: #simd[16]u8
@(private) I16 :: #simd[16]i8

@(private)
load16 :: #force_inline proc "contextless" (at: ^u8) -> V16 {
    return intrinsics.unaligned_load(cast(^V16)at)
}

// The bits of a move mask as a number: bit i is lane i
@(private)
mask16 :: #force_inline proc "contextless" (lanes: V16) -> u32 {
    return u32(transmute(u16)simd.extract_msbs(lanes))
}

@(private)
firstBit :: #force_inline proc "contextless" (mask: u32) -> int {
    return int(intrinsics.count_trailing_zeros(mask))
}

@(private)
textFillPortable :: proc "contextless" (tables: ^[Level]TextProcs) {
    // wasm without the simd128 feature cannot lower these kernels (LLVM stops: "Do not know how to split the result of this operator!"), and its levels are SCALAR then:
    // nothing refers to the kernels, so none is compiled
    when (ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32) && !intrinsics.has_target_feature("simd128") { return }
    sixteen: TextProcs = {
        ascii_prefix = asciiPrefix16,
        ascii_run = asciiRun16,
        index_of_byte = indexOfByte16,
        index_of_any = indexOfAny16,
        scan_text = scanText16,
        rune_count = runeCount16,
        utf8_valid_up_to = utf8ValidUpToScalar,
    }
    for level in ([?]Level{.SSE2, .NEON, .SIMD128}) {
        tables[level] = sixteen
        text_filled[level] = true
    }
    // the validator needs byte shuffles: SSSE3 on x86, always there on NEON and SIMD128
    for level in ([?]Level{.NEON, .SIMD128}) { tables[level].utf8_valid_up_to = utf8ValidUpTo16 }
    when ODIN_ARCH == .amd64 || ODIN_ARCH == .i386 { textFillX86(tables) }
}

@(private)
asciiPrefix16 :: proc "contextless" (bytes: []u8) -> int {
    at: int
    for at + 16 <= len(bytes) {
        mask: u32 = mask16(load16(&bytes[at]))
        if mask != 0 { return at + firstBit(mask) }
        at += 16
    }
    return at + asciiPrefixScalar(bytes[at:])
}

@(private)
asciiRun16 :: proc "contextless" (bytes: []u8) -> int {
    at: int
    for at + 16 <= len(bytes) {
        v: V16 = load16(&bytes[at])
        // below 0x20, or 0x7f and above (0x80 and above are in the second compare)
        bad: V16 = simd.lanes_lt(v, V16(0x20)) | simd.lanes_ge(v, V16(0x7f))
        mask: u32 = mask16(bad)
        if mask != 0 { return at + firstBit(mask) }
        at += 16
    }
    return at + asciiRunScalar(bytes[at:])
}

@(private)
indexOfByte16 :: proc "contextless" (bytes: []u8, needle: u8) -> int {
    at: int
    wanted: V16 = V16(needle)
    for at + 16 <= len(bytes) {
        mask: u32 = mask16(simd.lanes_eq(load16(&bytes[at]), wanted))
        if mask != 0 { return at + firstBit(mask) }
        at += 16
    }
    return at + indexOfByteScalar(bytes[at:], needle)
}

@(private)
indexOfAny16 :: proc "contextless" (bytes: []u8, set: [4]u8) -> int {
    at: int
    a, b, c, d: V16 = V16(set[0]), V16(set[1]), V16(set[2]), V16(set[3])
    for at + 16 <= len(bytes) {
        v: V16 = load16(&bytes[at])
        mask: u32 = mask16(simd.lanes_eq(v, a) | simd.lanes_eq(v, b) | simd.lanes_eq(v, c) | simd.lanes_eq(v, d))
        if mask != 0 { return at + firstBit(mask) }
        at += 16
    }
    return at + indexOfAnyScalar(bytes[at:], set)
}

@(private)
scanText16 :: proc "contextless" (bytes: []u8, stop: u8) -> (at: int, ascii: bool) {
    wanted: V16 = V16(stop)
    ascii = true
    for at + 16 <= len(bytes) {
        v: V16 = load16(&bytes[at])
        stops: u32 = mask16(simd.lanes_eq(v, wanted))
        high: u32 = mask16(v)
        if stops != 0 {
            first: int = firstBit(stops)
            if high & ((u32(1) << u32(first)) - 1) != 0 { ascii = false }
            return at + first, ascii
        }
        if high != 0 { ascii = false }
        at += 16
    }
    rest_at, rest_ascii := scanTextScalar(bytes[at:], stop)
    return at + rest_at, ascii && rest_ascii
}

@(private)
runeCount16 :: proc "contextless" (bytes: []u8) -> int {
    at: int
    continuations: int
    // 0x80 to 0xBF are the signed values -128 to -65
    limit: I16 = I16(-64)
    for at + 16 <= len(bytes) {
        v: I16 = transmute(I16)load16(&bytes[at])
        continuations += int(intrinsics.count_ones(mask16(simd.lanes_lt(v, limit))))
        at += 16
    }
    return (at - continuations) + runeCountScalar(bytes[at:])
}

// ---- UTF-8 validation: the lookup method of Keiser and Lemire ("Validating UTF-8 in less than one instruction per byte"), 16 bytes at a time ----------------------------
// For every pair of neighbouring bytes three nibble tables (the high and the low nibble of the first byte, the high nibble of the second) are looked up with a byte shuffle and
// ANDed: a bit that survives is one kind of error (overlong, surrogate, above U+10FFFF, a lead without a continuation, a continuation without a lead). The bit 0x80 is "two
// continuation bytes in a row", which is right exactly when the third or fourth byte of a sequence is there (known from the bytes two and three places back).

@(private) TOO_SHORT :: u8(1 << 0)
@(private) TOO_LONG :: u8(1 << 1)
@(private) OVERLONG_3 :: u8(1 << 2)
@(private) TOO_LARGE :: u8(1 << 3)
@(private) SURROGATE :: u8(1 << 4)
@(private) OVERLONG_2 :: u8(1 << 5)
@(private) TOO_LARGE_1000 :: u8(1 << 6)
@(private) OVERLONG_4 :: u8(1 << 6)
@(private) TWO_CONTS :: u8(1 << 7)
@(private) CARRY :: TOO_SHORT | TOO_LONG | TWO_CONTS

@(private) TABLE_FIRST_HIGH: V16 = {
    TOO_LONG, TOO_LONG, TOO_LONG, TOO_LONG, TOO_LONG, TOO_LONG, TOO_LONG, TOO_LONG,
    TWO_CONTS, TWO_CONTS, TWO_CONTS, TWO_CONTS,
    TOO_SHORT | OVERLONG_2, TOO_SHORT, TOO_SHORT | OVERLONG_3 | SURROGATE, TOO_SHORT | TOO_LARGE | TOO_LARGE_1000 | OVERLONG_4,
}
@(private) TABLE_FIRST_LOW: V16 = {
    CARRY | OVERLONG_3 | OVERLONG_2 | OVERLONG_4, CARRY | OVERLONG_2, CARRY, CARRY,
    CARRY | TOO_LARGE,
    CARRY | TOO_LARGE | TOO_LARGE_1000, CARRY | TOO_LARGE | TOO_LARGE_1000, CARRY | TOO_LARGE | TOO_LARGE_1000, CARRY | TOO_LARGE | TOO_LARGE_1000,
    CARRY | TOO_LARGE | TOO_LARGE_1000, CARRY | TOO_LARGE | TOO_LARGE_1000, CARRY | TOO_LARGE | TOO_LARGE_1000, CARRY | TOO_LARGE | TOO_LARGE_1000,
    CARRY | TOO_LARGE | TOO_LARGE_1000 | SURROGATE, CARRY | TOO_LARGE | TOO_LARGE_1000, CARRY | TOO_LARGE | TOO_LARGE_1000,
}
@(private) TABLE_SECOND_HIGH: V16 = {
    TOO_SHORT, TOO_SHORT, TOO_SHORT, TOO_SHORT, TOO_SHORT, TOO_SHORT, TOO_SHORT, TOO_SHORT,
    TOO_LONG | OVERLONG_2 | TWO_CONTS | OVERLONG_3 | TOO_LARGE_1000 | OVERLONG_4,
    TOO_LONG | OVERLONG_2 | TWO_CONTS | OVERLONG_3 | TOO_LARGE,
    TOO_LONG | OVERLONG_2 | TWO_CONTS | SURROGATE | TOO_LARGE,
    TOO_LONG | OVERLONG_2 | TWO_CONTS | SURROGATE | TOO_LARGE,
    TOO_SHORT, TOO_SHORT, TOO_SHORT, TOO_SHORT,
}

// The error bits of one vector of 16 bytes that follows `prev` (the 16 bytes before it). Zero in every lane when they are well formed (as far as the bytes before can tell: a cut
// sequence at the very end is the caller's).
@(private)
utf8CheckVector :: #force_inline proc "contextless" (v: V16, prev: V16) -> V16 {
    prev1: V16 = simd.shuffle(prev, v, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30)
    prev2: V16 = simd.shuffle(prev, v, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29)
    prev3: V16 = simd.shuffle(prev, v, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28)
    nibble: V16 = V16(0x0F)
    special: V16 = intrinsics.simd_runtime_swizzle(TABLE_FIRST_HIGH, simd.shr(prev1, V16(4))) &
        intrinsics.simd_runtime_swizzle(TABLE_FIRST_LOW, prev1 & nibble) &
        intrinsics.simd_runtime_swizzle(TABLE_SECOND_HIGH, simd.shr(v, V16(4)))
    // the third byte of a sequence comes after a lead of E0 and above, the fourth after F0 and above: both are continuation bytes that the table calls TWO_CONTS
    third: V16 = simd.saturating_sub(prev2, V16(0xE0 - 0x80))
    fourth: V16 = simd.saturating_sub(prev3, V16(0xF0 - 0x80))
    must: V16 = (third | fourth) & V16(0x80)
    return simd.bit_xor(must, special)
}

// The length of the well formed start. 64 byte groups: an ASCII group is skipped with one test; the other groups run the vector check four times with the carry of the last vector, and
// a group that shows an error is handed to the scalar validator, from the start of the character that may reach into it, for the exact place.
@(private)
utf8ValidUpTo16 :: proc "contextless" (bytes: []u8) -> int {
    return utf8ValidUpTo16Inline(bytes)
}

// The body, inlined into a procedure with the target feature of its level (the shuffle is one instruction there), or into the portable one
@(private)
utf8ValidUpTo16Inline :: #force_inline proc "contextless" (bytes: []u8) -> int {
    at: int
    prev: V16
    count: int = len(bytes)
    for at + 64 <= count {
        a: V16 = load16(&bytes[at])
        b: V16 = load16(&bytes[at + 16])
        c: V16 = load16(&bytes[at + 32])
        d: V16 = load16(&bytes[at + 48])
        if mask16(a | b | c | d) == 0 {
            // an ASCII group: a sequence that was left open by the group before it is an error here, a whole one is not
            if at > 0 && bytes[at - 1] >= 0x80 {
                checked: int = utf8Rescan(bytes, at, at + 4)
                if checked < at + 4 { return checked }
            }
            prev = d
            at += 64
            continue
        }
        error: V16 = utf8CheckVector(a, prev) | utf8CheckVector(b, a) | utf8CheckVector(c, b) | utf8CheckVector(d, c)
        if mask16(simd.lanes_ne(error, V16(0))) != 0 { return utf8Rescan(bytes, at, count) }
        prev = d
        at += 64
    }
    // the rest (less than 64 bytes) and a sequence that the last group left open: the exact scalar check from the character that reaches into the tail
    return utf8Rescan(bytes, at, count)
}

// The exact length by the scalar rule over bytes[start:end], where start is `at`, or the lead byte of a sequence that was left open in the three bytes before `at` (the bytes before
// it were checked by the vectors). Returns the length counted from the start of `bytes`.
@(private)
utf8Rescan :: proc "contextless" (bytes: []u8, at: int, end: int) -> int {
    start: int = at
    for k in 1 ..= 3 {
        if at - k < 0 { break }
        b: u8 = bytes[at - k]
        if b & 0xC0 != 0x80 {
            if b >= 0xC0 { start = at - k }
            break
        }
    }
    return start + utf8ValidUpToScalar(bytes[start:end])
}
