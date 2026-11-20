#+build i386, amd64
package simd_utils

// The text kernels of the x86 levels: 16 byte kernels compiled with the features of SSSE3 (byte shuffles for the UTF-8 validator), 32 byte scans for AVX2, 64 byte scans for AVX-512.
// Each kernel is its own procedure with its own `enable_target_feature`: no shared inline helper crosses a feature boundary with a 256 or 512 bit value (the rule of README.md).

import "base:intrinsics"
import "core:simd"

@(private) V32 :: #simd[32]u8
@(private) V64 :: #simd[64]u8
@(private) I32 :: #simd[32]i8
@(private) I64 :: #simd[64]i8

// (No `load32` helper: a 256 or 512 bit value returned from a procedure that is a call at -o:none and has no target feature loses its upper half. Every kernel loads inline.)

@(private)
textFillX86 :: proc "contextless" (tables: ^[Level]TextProcs) {
    tables[.SSSE3] = tables[.SSE2]
    tables[.SSSE3].utf8_valid_up_to = utf8ValidUpToSsse3
    text_filled[.SSSE3] = true
    tables[.AVX2] = {
        ascii_prefix = asciiPrefix32, ascii_run = asciiRun32, index_of_byte = indexOfByte32, index_of_any = indexOfAny32, scan_text = scanText32, rune_count = runeCount32,
        utf8_valid_up_to = utf8ValidUpToAvx2,
    }
    text_filled[.AVX2] = true
    tables[.AVX512] = {
        ascii_prefix = asciiPrefix64, ascii_run = asciiRun64, index_of_byte = indexOfByte64, index_of_any = indexOfAny64, scan_text = scanText64, rune_count = runeCount64,
        utf8_valid_up_to = utf8ValidUpToAvx2,
    }
    text_filled[.AVX512] = true
}

@(private, enable_target_feature = FEATURES_SSSE3)
utf8ValidUpToSsse3 :: proc "contextless" (bytes: []u8) -> int {
    return utf8ValidUpTo16Inline(bytes)
}

// The same with VEX encoded instructions (no register copies); the vectors are 16 bytes: a 32 byte lookup needs a lane crossing carry that costs what it saves on text
@(private, enable_target_feature = FEATURES_AVX2)
utf8ValidUpToAvx2 :: proc "contextless" (bytes: []u8) -> int {
    return utf8ValidUpTo16Inline(bytes)
}

// ---- AVX2: 32 bytes ----------------------------------------------------------------------------------------------------------------------------------------

@(private, enable_target_feature = FEATURES_AVX2)
asciiPrefix32 :: proc "contextless" (bytes: []u8) -> int {
    at: int
    for at + 32 <= len(bytes) {
        mask: u32 = transmute(u32)simd.extract_msbs(intrinsics.unaligned_load(cast(^V32)&bytes[at]))
        if mask != 0 { return at + int(intrinsics.count_trailing_zeros(mask)) }
        at += 32
    }
    return at + asciiPrefix16(bytes[at:])
}

@(private, enable_target_feature = FEATURES_AVX2)
asciiRun32 :: proc "contextless" (bytes: []u8) -> int {
    at: int
    for at + 32 <= len(bytes) {
        v: V32 = intrinsics.unaligned_load(cast(^V32)&bytes[at])
        bad: V32 = simd.lanes_lt(v, V32(0x20)) | simd.lanes_ge(v, V32(0x7f))
        mask: u32 = transmute(u32)simd.extract_msbs(bad)
        if mask != 0 { return at + int(intrinsics.count_trailing_zeros(mask)) }
        at += 32
    }
    return at + asciiRun16(bytes[at:])
}

@(private, enable_target_feature = FEATURES_AVX2)
indexOfByte32 :: proc "contextless" (bytes: []u8, needle: u8) -> int {
    at: int
    wanted: V32 = V32(needle)
    for at + 32 <= len(bytes) {
        mask: u32 = transmute(u32)simd.extract_msbs(simd.lanes_eq(intrinsics.unaligned_load(cast(^V32)&bytes[at]), wanted))
        if mask != 0 { return at + int(intrinsics.count_trailing_zeros(mask)) }
        at += 32
    }
    return at + indexOfByte16(bytes[at:], needle)
}

@(private, enable_target_feature = FEATURES_AVX2)
indexOfAny32 :: proc "contextless" (bytes: []u8, set: [4]u8) -> int {
    at: int
    a, b, c, d: V32 = V32(set[0]), V32(set[1]), V32(set[2]), V32(set[3])
    for at + 32 <= len(bytes) {
        v: V32 = intrinsics.unaligned_load(cast(^V32)&bytes[at])
        mask: u32 = transmute(u32)simd.extract_msbs(simd.lanes_eq(v, a) | simd.lanes_eq(v, b) | simd.lanes_eq(v, c) | simd.lanes_eq(v, d))
        if mask != 0 { return at + int(intrinsics.count_trailing_zeros(mask)) }
        at += 32
    }
    return at + indexOfAny16(bytes[at:], set)
}

@(private, enable_target_feature = FEATURES_AVX2)
scanText32 :: proc "contextless" (bytes: []u8, stop: u8) -> (at: int, ascii: bool) {
    wanted: V32 = V32(stop)
    ascii = true
    for at + 32 <= len(bytes) {
        v: V32 = intrinsics.unaligned_load(cast(^V32)&bytes[at])
        stops: u32 = transmute(u32)simd.extract_msbs(simd.lanes_eq(v, wanted))
        high: u32 = transmute(u32)simd.extract_msbs(v)
        if stops != 0 {
            first: u32 = intrinsics.count_trailing_zeros(stops)
            if high & ((u32(1) << first) - 1) != 0 { ascii = false }
            return at + int(first), ascii
        }
        if high != 0 { ascii = false }
        at += 32
    }
    rest_at, rest_ascii := scanText16(bytes[at:], stop)
    return at + rest_at, ascii && rest_ascii
}

@(private, enable_target_feature = FEATURES_AVX2)
runeCount32 :: proc "contextless" (bytes: []u8) -> int {
    at: int
    continuations: int
    limit: I32 = I32(-64)
    for at + 32 <= len(bytes) {
        v: I32 = transmute(I32)intrinsics.unaligned_load(cast(^V32)&bytes[at])
        continuations += int(intrinsics.count_ones(transmute(u32)simd.extract_msbs(simd.lanes_lt(v, limit))))
        at += 32
    }
    return (at - continuations) + runeCount16(bytes[at:])
}

// ---- AVX-512: 64 bytes -------------------------------------------------------------------------------------------------------------------------------------

@(private, enable_target_feature = FEATURES_AVX512)
asciiPrefix64 :: proc "contextless" (bytes: []u8) -> int {
    at: int
    for at + 64 <= len(bytes) {
        mask: u64 = transmute(u64)simd.extract_msbs(intrinsics.unaligned_load(cast(^V64)&bytes[at]))
        if mask != 0 { return at + int(intrinsics.count_trailing_zeros(mask)) }
        at += 64
    }
    return at + asciiPrefix32(bytes[at:])
}

@(private, enable_target_feature = FEATURES_AVX512)
asciiRun64 :: proc "contextless" (bytes: []u8) -> int {
    at: int
    for at + 64 <= len(bytes) {
        v: V64 = intrinsics.unaligned_load(cast(^V64)&bytes[at])
        bad: V64 = simd.lanes_lt(v, V64(0x20)) | simd.lanes_ge(v, V64(0x7f))
        mask: u64 = transmute(u64)simd.extract_msbs(bad)
        if mask != 0 { return at + int(intrinsics.count_trailing_zeros(mask)) }
        at += 64
    }
    return at + asciiRun32(bytes[at:])
}

@(private, enable_target_feature = FEATURES_AVX512)
indexOfByte64 :: proc "contextless" (bytes: []u8, needle: u8) -> int {
    at: int
    wanted: V64 = V64(needle)
    for at + 64 <= len(bytes) {
        mask: u64 = transmute(u64)simd.extract_msbs(simd.lanes_eq(intrinsics.unaligned_load(cast(^V64)&bytes[at]), wanted))
        if mask != 0 { return at + int(intrinsics.count_trailing_zeros(mask)) }
        at += 64
    }
    return at + indexOfByte32(bytes[at:], needle)
}

@(private, enable_target_feature = FEATURES_AVX512)
indexOfAny64 :: proc "contextless" (bytes: []u8, set: [4]u8) -> int {
    at: int
    a, b, c, d: V64 = V64(set[0]), V64(set[1]), V64(set[2]), V64(set[3])
    for at + 64 <= len(bytes) {
        v: V64 = intrinsics.unaligned_load(cast(^V64)&bytes[at])
        mask: u64 = transmute(u64)simd.extract_msbs(simd.lanes_eq(v, a) | simd.lanes_eq(v, b) | simd.lanes_eq(v, c) | simd.lanes_eq(v, d))
        if mask != 0 { return at + int(intrinsics.count_trailing_zeros(mask)) }
        at += 64
    }
    return at + indexOfAny32(bytes[at:], set)
}

@(private, enable_target_feature = FEATURES_AVX512)
scanText64 :: proc "contextless" (bytes: []u8, stop: u8) -> (at: int, ascii: bool) {
    wanted: V64 = V64(stop)
    ascii = true
    for at + 64 <= len(bytes) {
        v: V64 = intrinsics.unaligned_load(cast(^V64)&bytes[at])
        stops: u64 = transmute(u64)simd.extract_msbs(simd.lanes_eq(v, wanted))
        high: u64 = transmute(u64)simd.extract_msbs(v)
        if stops != 0 {
            first: u64 = intrinsics.count_trailing_zeros(stops)
            if high & ((u64(1) << first) - 1) != 0 { ascii = false }
            return at + int(first), ascii
        }
        if high != 0 { ascii = false }
        at += 64
    }
    rest_at, rest_ascii := scanText32(bytes[at:], stop)
    return at + rest_at, ascii && rest_ascii
}

@(private, enable_target_feature = FEATURES_AVX512)
runeCount64 :: proc "contextless" (bytes: []u8) -> int {
    at: int
    continuations: int
    limit: I64 = I64(-64)
    for at + 64 <= len(bytes) {
        v: I64 = transmute(I64)intrinsics.unaligned_load(cast(^V64)&bytes[at])
        continuations += int(intrinsics.count_ones(transmute(u64)simd.extract_msbs(simd.lanes_lt(v, limit))))
        at += 64
    }
    return (at - continuations) + runeCount32(bytes[at:])
}
