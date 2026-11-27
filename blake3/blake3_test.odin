#+build windows, linux, darwin, freebsd, openbsd, netbsd
package blake3

// The official test vectors of the BLAKE3 team (testdata/test_vectors.json, from BLAKE3-team/BLAKE3, public domain / Apache 2.0): 35 input lengths from 0 to 102400 bytes (the input is the
// bytes 0 to 250 repeating), each with the plain hash, the keyed hash and the derived key, all 131 bytes long (the first 32 are the usual digest). Every length is also fed in pieces of
// different sizes, so that the chunk and block boundaries are crossed in every way.

import "core:encoding/hex"
import "core:encoding/json"
import "core:testing"

VECTORS_JSON :: #load("testdata/test_vectors.json")

@(private = "file")
KEY: string = "whats the Elvish word for friend"
@(private = "file")
CONTEXT: string = "BLAKE3 2019-12-27 16:29:52 test vectors context"

@(private = "file")
makeInput :: proc(length: int) -> []u8 {
    input: []u8 = make([]u8, length, context.temp_allocator)
    for i in 0 ..< length { input[i] = u8(i % 251) }
    return input
}

@(private = "file")
expectHex :: proc(t: ^testing.T, got: []u8, want_hex: string, label: string, length: int) {
    want: []u8 = hex.decode(transmute([]u8)want_hex, context.temp_allocator) or_else nil
    testing.expectf(t, len(want) == len(got), "%s, input %d: the vector has %d bytes", label, length, len(want))
    if len(want) != len(got) { return }
    for i in 0 ..< len(got) {
        if got[i] != want[i] {
            testing.expectf(t, false, "%s, input %d: byte %d is %02x, expected %02x", label, length, i, got[i], want[i])
            return
        }
    }
}

@(test)
test_the_official_vectors :: proc(t: ^testing.T) {
    value, error := json.parse(VECTORS_JSON, allocator = context.temp_allocator)
    testing.expect(t, error == nil, "the vector file parses")
    cases: json.Array = value.(json.Object)["cases"].(json.Array)
    testing.expect_value(t, len(cases), 35)

    for case_value in cases {
        entry: json.Object = case_value.(json.Object)
        length: int = int(entry["input_len"].(json.Float))
        input: []u8 = makeInput(length)
        out: [131]u8

        Blake3Hash(input, out[:])
        expectHex(t, out[:], entry["hash"].(json.String), "hash", length)

        keyed: Blake3Hasher
        Blake3InitKeyed(&keyed, transmute([]u8)KEY)
        Blake3Update(&keyed, input)
        Blake3Final(&keyed, out[:])
        expectHex(t, out[:], entry["keyed_hash"].(json.String), "keyed hash", length)

        derived: Blake3Hasher
        Blake3InitDeriveKey(&derived, CONTEXT)
        Blake3Update(&derived, input)
        Blake3Final(&derived, out[:])
        expectHex(t, out[:], entry["derive_key"].(json.String), "derive key", length)

        // The same input in pieces: sizes that stop before, on and after the block (64) and chunk (1024) borders, so no way of splitting changes the answer
        pieces: []int = {1, 7, 63, 64, 65, 1023, 1024, 1025, 4096}
        for piece in pieces {
            hasher: Blake3Hasher
            Blake3Init(&hasher)
            rest: []u8 = input
            for len(rest) > 0 {
                take: int = min(piece, len(rest))
                Blake3Update(&hasher, rest[:take])
                rest = rest[take:]
            }
            Blake3Final(&hasher, out[:])
            expectHex(t, out[:], entry["hash"].(json.String), "hash in pieces", length)
        }
    }
}

@(test)
test_the_output_is_extendable_and_the_hasher_goes_on_after_it :: proc(t: ^testing.T) {
    input: []u8 = makeInput(3000)
    short, long: [32]u8
    longer: [100]u8
    hasher: Blake3Hasher
    Blake3Init(&hasher)
    Blake3Update(&hasher, input[:1500])
    Blake3Final(&hasher, short[:])                              // looking at the state in the middle changes nothing
    Blake3Update(&hasher, input[1500:])
    Blake3Final(&hasher, longer[:])
    Blake3Final(&hasher, long[:])
    for i in 0 ..< 32 { testing.expect_value(t, long[i], longer[i]) }      // a longer output starts with the shorter one
    whole: [32]u8
    Blake3Hash(input, whole[:])
    testing.expect_value(t, whole, long)
    testing.expect(t, whole != short, "the middle state was a different hash")
}

@(test)
test_empty_input_and_text :: proc(t: ^testing.T) {
    digest: [32]u8
    Blake3HashString("", digest[:])
    want: [32]u8 = {0xaf, 0x13, 0x49, 0xb9, 0xf5, 0xf9, 0xa1, 0xa6, 0xa0, 0x40, 0x4d, 0xea, 0x36, 0xdc, 0xc9, 0x49, 0x9b, 0xcb, 0x25, 0xc9, 0xad, 0xc1, 0x12, 0xb7, 0xcc, 0x9a, 0x93, 0xca, 0xe4, 0x1f, 0x32, 0x62}
    testing.expect_value(t, digest, want)
    other: [32]u8
    Blake3HashString("abc", other[:])
    testing.expect(t, other != digest)
}
