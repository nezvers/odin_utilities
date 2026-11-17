#+build !js
// NTLM (MS-NLMP), version 2 responses, written out so that a proxy that wants "NTLM" can be answered with an explicit user name and
// password on every platform (on Windows without credentials in the URL the login of the user goes through SSPI instead, proxy_sspi_windows.odin).
//
// The three messages: the client opens with NEGOTIATE (type 1), the server answers with CHALLENGE (type 2: its 8 byte challenge, the target
// information), the client closes with AUTHENTICATE (type 3: the response that proves it knows the password without sending it). Nothing is
// signed or sealed afterwards: the proxy only wants to know who is asking.
//
// The password is hashed with MD4 (NT hash), which core:crypto does not have: it is here, checked against RFC 1320. MD4 is broken as a hash and
// NTLM is a weak protocol: it is for proxies that demand it, nothing of ours depends on it.
package p2p

import "core:crypto"
import "core:crypto/hash"
import "core:crypto/hmac"
import "core:encoding/base64"
import "core:testing"
import "core:time"

NTLM_SIGNATURE :: "NTLMSSP\x00"
NTLM_FLAGS :: u32(0xA0888205)         // unicode, request target, NTLM, always sign, extended session security, target info, 128 and 56 bit

// ---------------------------------------------------------------------------------------------------------------- MD4 (RFC 1320)

@(private)
Md4Rotate :: #force_inline proc(value: u32, bits: u32) -> u32 {
    return value << bits | value >> (32 - bits)
}

Md4 :: proc(data: []byte) -> (digest: [16]byte) {
    state: [4]u32 = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476}
    // the message, a 1 bit, zeros to 56 mod 64, and its length in bits
    padded: [dynamic]byte
    defer delete(padded)
    append(&padded, ..data)
    append(&padded, 0x80)
    for len(padded) % 64 != 56 {
        append(&padded, 0)
    }
    bits: u64 = u64(len(data)) * 8
    for i in 0 ..< 8 {
        append(&padded, u8(bits >> (8 * uint(i))))
    }
    for block := 0; block < len(padded); block += 64 {
        x: [16]u32
        for i in 0 ..< 16 {
            at: int = block + 4 * i
            x[i] = u32(padded[at]) | u32(padded[at + 1]) << 8 | u32(padded[at + 2]) << 16 | u32(padded[at + 3]) << 24
        }
        t: [4]u32 = state
        shift1: [4]u32 = {3, 7, 11, 19}
        shift2: [4]u32 = {3, 5, 9, 13}
        shift3: [4]u32 = {3, 9, 11, 15}
        // the roles of the four words turn by one each step: a, d, c, b, a, ...
        for step in 0 ..< 16 {
            p: int = (0 - step) & 3
            f: u32 = (t[(p + 1) & 3] & t[(p + 2) & 3]) | (~t[(p + 1) & 3] & t[(p + 3) & 3])
            t[p] = Md4Rotate(t[p] + f + x[step], shift1[step & 3])
        }
        order2: [16]int = {0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15}
        for step in 0 ..< 16 {
            p: int = (0 - step) & 3
            b, c, d: u32 = t[(p + 1) & 3], t[(p + 2) & 3], t[(p + 3) & 3]
            g: u32 = (b & c) | (b & d) | (c & d)
            t[p] = Md4Rotate(t[p] + g + x[order2[step]] + 0x5a827999, shift2[step & 3])
        }
        order3: [16]int = {0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15}
        for step in 0 ..< 16 {
            p: int = (0 - step) & 3
            h: u32 = t[(p + 1) & 3] ~ t[(p + 2) & 3] ~ t[(p + 3) & 3]
            t[p] = Md4Rotate(t[p] + h + x[order3[step]] + 0x6ed9eba1, shift3[step & 3])
        }
        for i in 0 ..< 4 {
            state[i] += t[i]
        }
    }
    for i in 0 ..< 4 {
        for j in 0 ..< 4 {
            digest[4 * i + j] = u8(state[i] >> (8 * uint(j)))
        }
    }
    return
}

// ---------------------------------------------------------------------------------------------------------------- the messages

// The text as UTF-16LE (a name or a password: only what UTF-8 decodes to is kept as it is, every rune is one or two units).
@(private)
NtlmUtf16 :: proc(text: string, allocator := context.allocator) -> []byte {
    out: [dynamic]byte
    out.allocator = allocator
    for r in text {
        value: u32 = u32(r)
        if value >= 0x10000 {
            value -= 0x10000
            high: u16 = u16(0xd800 + (value >> 10))
            low: u16 = u16(0xdc00 + (value & 0x3ff))
            append(&out, u8(high), u8(high >> 8), u8(low), u8(low >> 8))
        } else {
            append(&out, u8(value), u8(value >> 8))
        }
    }
    return out[:]
}

@(private)
NtlmUpper :: proc(text: string, allocator := context.allocator) -> string {
    out: [dynamic]byte
    out.allocator = allocator
    for i in 0 ..< len(text) {
        c: byte = text[i]
        append(&out, c - 32 if c >= 'a' && c <= 'z' else c)
    }
    return string(out[:])
}

// NTOWFv2 = HMAC_MD5(MD4(UTF16(password)), UTF16(UPPER(user) + domain))
NtlmHashV2 :: proc(user: string, domain: string, password: string) -> (key: [16]byte) {
    password_bytes: []byte = NtlmUtf16(password, context.temp_allocator)
    nt_hash: [16]byte = Md4(password_bytes)
    upper: string = NtlmUpper(user, context.temp_allocator)
    identity: []byte = NtlmUtf16(upper, context.temp_allocator)
    domain_bytes: []byte = NtlmUtf16(domain, context.temp_allocator)
    joined: []byte = make([]byte, len(identity) + len(domain_bytes), context.temp_allocator)
    copy(joined, identity)
    copy(joined[len(identity):], domain_bytes)
    hmac.sum(hash.Algorithm.Insecure_MD5, key[:], joined, nt_hash[:])
    return
}

// The NTLMv2 response: NTProofStr (16 bytes) followed by the blob it covers. `target_info` is what the server's CHALLENGE carried, `time` the
// Windows file time (100 ns since 1601) the blob states.
NtlmResponseV2 :: proc(key: [16]byte, server_challenge: [8]byte, client_challenge: [8]byte, file_time: u64, target_info: []byte, allocator := context.allocator) -> []byte {
    key_copy: [16]byte = key
    client_copy: [8]byte = client_challenge
    server_copy: [8]byte = server_challenge
    blob: [dynamic]byte
    defer delete(blob)
    append(&blob, 1, 1, 0, 0, 0, 0, 0, 0)
    for i in 0 ..< 8 {
        append(&blob, u8(file_time >> (8 * uint(i))))
    }
    append(&blob, ..client_copy[:])
    append(&blob, 0, 0, 0, 0)
    append(&blob, ..target_info)
    append(&blob, 0, 0, 0, 0)
    covered: [dynamic]byte
    defer delete(covered)
    append(&covered, ..server_copy[:])
    append(&covered, ..blob[:])
    proof: [16]byte
    hmac.sum(hash.Algorithm.Insecure_MD5, proof[:], covered[:], key_copy[:])
    out: []byte = make([]byte, 16 + len(blob), allocator)
    copy(out, proof[:])
    copy(out[16:], blob[:])
    return out
}

// NEGOTIATE, type 1: the flags and nothing else.
NtlmNegotiate :: proc(out: []byte) -> int {
    assert(len(out) >= 32)
    for i in 0 ..< 32 {
        out[i] = 0
    }
    copy(out, NTLM_SIGNATURE)
    out[8] = 1
    for i in 0 ..< 4 {
        out[12 + i] = u8(NTLM_FLAGS >> (8 * uint(i)))
    }
    return 32
}

// The CHALLENGE (type 2) of the server: its challenge, flags and target information (a view into `message`).
NtlmParseChallenge :: proc(message: []byte) -> (challenge: [8]byte, flags: u32, target_info: []byte, ok: bool) {
    if len(message) < 48 || string(message[:8]) != NTLM_SIGNATURE || message[8] != 2 {
        return
    }
    flags = u32(message[20]) | u32(message[21]) << 8 | u32(message[22]) << 16 | u32(message[23]) << 24
    copy(challenge[:], message[24:32])
    info_length: int = int(message[40]) | int(message[41]) << 8
    info_offset: int = int(message[44]) | int(message[45]) << 8 | int(message[46]) << 16 | int(message[47]) << 24
    if info_length > 0 {
        if info_offset < 48 || info_offset + info_length > len(message) {
            return
        }
        target_info = message[info_offset:info_offset + info_length]
    }
    ok = true
    return
}

// The server's own clock from its target information (MsvAvTimestamp, id 7), 0 when it did not send one.
NtlmServerTime :: proc(target_info: []byte) -> (file_time: u64) {
    at: int
    for at + 4 <= len(target_info) {
        id: int = int(target_info[at]) | int(target_info[at + 1]) << 8
        size: int = int(target_info[at + 2]) | int(target_info[at + 3]) << 8
        at += 4
        if id == 0 || at + size > len(target_info) {
            return 0
        }
        if id == 7 && size == 8 {
            for i in 0 ..< 8 {
                file_time |= u64(target_info[at + i]) << (8 * uint(i))
            }
            return
        }
        at += size
    }
    return 0
}

// AUTHENTICATE, type 3, for the CHALLENGE `challenge_message`. `domain\user` in `user_text` is split; the workstation is left empty. Allocated.
NtlmAuthenticate :: proc(
    user_text: string,
    password: string,
    server_challenge: [8]byte,
    server_flags: u32,
    target_info: []byte,
    client_challenge: [8]byte,
    file_time: u64,
    allocator := context.allocator,
) -> []byte {
    user, domain: string = user_text, ""
    for i in 0 ..< len(user_text) {
        if user_text[i] == '\\' {
            domain, user = user_text[:i], user_text[i + 1:]
            break
        }
    }
    key: [16]byte = NtlmHashV2(user, domain, password)
    response: []byte = NtlmResponseV2(key, server_challenge, client_challenge, file_time, target_info, context.temp_allocator)
    lm: [24]byte                                        // LMv2 is left out: zeros, which servers accept next to a good NTLMv2 response
    domain_bytes: []byte = NtlmUtf16(domain, context.temp_allocator)
    user_bytes: []byte = NtlmUtf16(user, context.temp_allocator)

    HEADER :: 64
    total: int = HEADER + len(domain_bytes) + len(user_bytes) + len(lm) + len(response)
    out: []byte = make([]byte, total, allocator)
    copy(out, NTLM_SIGNATURE)
    out[8] = 3
    at: int = HEADER
    // a field: length, capacity, offset of where its bytes follow
    put_field :: proc(out: []byte, field: int, data: []byte, at: ^int) {
        out[field] = u8(len(data))
        out[field + 1] = u8(len(data) >> 8)
        out[field + 2] = u8(len(data))
        out[field + 3] = u8(len(data) >> 8)
        for i in 0 ..< 4 {
            out[field + 4 + i] = u8(at^ >> (8 * uint(i)))
        }
        copy(out[at^:], data)
        at^ += len(data)
    }
    put_field(out, 12, lm[:], &at)                      // LmChallengeResponse
    put_field(out, 20, response, &at)                   // NtChallengeResponse
    put_field(out, 28, domain_bytes, &at)
    put_field(out, 36, user_bytes, &at)
    put_field(out, 44, nil, &at)                        // workstation
    put_field(out, 52, nil, &at)                        // encrypted session key
    flags: u32 = NTLM_FLAGS & server_flags | 0x201      // what both want, unicode and NTLM in any case
    for i in 0 ..< 4 {
        out[60 + i] = u8(flags >> (8 * uint(i)))
    }
    return out
}

// The base64 of a message, the token of an Authorization header.
NtlmHeaderValue :: proc(message: []byte, allocator := context.temp_allocator) -> string {
    encoded, _ := base64.encode(message, allocator = allocator)
    return encoded
}

// 100 ns ticks since 1601, now.
NtlmNow :: proc() -> u64 {
    return u64(time.to_unix_nanoseconds(time.now()) / 100) + 116_444_736_000_000_000
}

NtlmRandom :: proc() -> (value: [8]byte) {
    crypto.rand_bytes(value[:])
    return
}

// ---------------------------------------------------------------------------------------------------------------- tests

@(test)
Md4Test :: proc(t: ^testing.T) {
    // RFC 1320, appendix A.5
    cases: [5][2]string = {
        {"", "31d6cfe0d16ae931b73c59d7e0c089c0"},
        {"a", "bde52cb31de33e46245e05fbdbd6fb24"},
        {"abc", "a448017aaf21d8525fc10ae87aa6729d"},
        {"message digest", "d9130a8164549fe818874806e1c7014b"},
        {"12345678901234567890123456789012345678901234567890123456789012345678901234567890", "e33b4ddc9c38f2199c3e7b164fcc0536"},
    }
    for entry in cases {
        digest: [16]byte = Md4(transmute([]byte)entry[0])
        hex: [32]byte
        digits: string = "0123456789abcdef"
        for b, i in digest {
            hex[2 * i] = digits[b >> 4]
            hex[2 * i + 1] = digits[b & 15]
        }
        testing.expect_value(t, string(hex[:]), entry[1])
    }
}

@(private)
NtlmHex :: proc(data: []byte) -> string {
    digits: string = "0123456789abcdef"
    out: []byte = make([]byte, 2 * len(data), context.temp_allocator)
    for b, i in data {
        out[2 * i] = digits[b >> 4]
        out[2 * i + 1] = digits[b & 15]
    }
    return string(out)
}

// The example of MS-NLMP 4.2.4 (user "User", domain "Domain", password "Password").
@(test)
NtlmV2Test :: proc(t: ^testing.T) {
    nt_hash: [16]byte = Md4(NtlmUtf16("Password", context.temp_allocator))
    testing.expect_value(t, NtlmHex(nt_hash[:]), "a4f49c406510bdcab6824ee7c30fd852")
    key: [16]byte = NtlmHashV2("User", "Domain", "Password")
    testing.expect_value(t, NtlmHex(key[:]), "0c868a403bfd7a93a3001ef22ef02e3f")

    server_challenge: [8]byte = {0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef}
    client_challenge: [8]byte = {0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa}
    // the server name list of the example: NetBIOS domain "Domain", NetBIOS computer "Server", end
    info: []byte = {0x02, 0x00, 0x0c, 0x00, 'D', 0, 'o', 0, 'm', 0, 'a', 0, 'i', 0, 'n', 0, 0x01, 0x00, 0x0c, 0x00, 'S', 0, 'e', 0, 'r', 0, 'v', 0, 'e', 0, 'r', 0, 0, 0, 0, 0}
    response: []byte = NtlmResponseV2(key, server_challenge, client_challenge, 0, info, context.temp_allocator)
    testing.expect_value(t, NtlmHex(response[:16]), "68cd0ab851e51c96aabc927bebef6a1c")
    testing.expect_value(t, len(response), 16 + 28 + len(info) + 4)

    // the messages: type 1 is only flags; a type 2 built by hand is read back; the type 3 names user and domain and points at its data
    negotiate: [32]byte
    testing.expect_value(t, NtlmNegotiate(negotiate[:]), 32)
    testing.expect_value(t, string(negotiate[:8]), NTLM_SIGNATURE)
    challenge: [48 + 36]byte
    copy(challenge[:], NTLM_SIGNATURE)
    challenge[8] = 2
    challenge[20], challenge[21], challenge[22], challenge[23] = 0x05, 0x82, 0x88, 0xA0
    copy(challenge[24:], server_challenge[:])
    challenge[40], challenge[41], challenge[44] = u8(len(info)), 0, 48
    copy(challenge[48:], info)
    parsed_challenge, flags, target_info, ok := NtlmParseChallenge(challenge[:])
    testing.expect(t, ok)
    testing.expect_value(t, parsed_challenge, server_challenge)
    testing.expect_value(t, flags, u32(0xA0888205))
    testing.expect_value(t, len(target_info), len(info))
    testing.expect_value(t, NtlmServerTime(target_info), u64(0))
    message: []byte = NtlmAuthenticate("Domain\\User", "Password", parsed_challenge, flags, target_info, client_challenge, 0, context.temp_allocator)
    testing.expect_value(t, string(message[:8]), NTLM_SIGNATURE)
    testing.expect_value(t, message[8], 3)
    nt_offset: int = int(message[24]) | int(message[25]) << 8
    testing.expect_value(t, nt_offset, 64 + 24)
    testing.expect_value(t, NtlmHex(message[nt_offset:nt_offset + 16]), "68cd0ab851e51c96aabc927bebef6a1c")
    testing.expect_value(t, int(message[28]), 12)         // "Domain" in UTF-16
    testing.expect_value(t, int(message[36]), 8)          // "User"

    _, _, _, bad := NtlmParseChallenge(negotiate[:])
    testing.expect(t, !bad)
}
