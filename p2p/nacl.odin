// NaCl "crypto_box": Curve25519 key agreement, XSalsa20 stream cipher, Poly1305 authenticator. It is what DERP relays (and the
// derpnet reference, https://github.com/mmozeiko/derpnet) use between a client and a server and between two peers, so a packet sealed
// here opens in any NaCl / libsodium / Tailscale implementation and the other way round.
//
// Pure functions over caller buffers, no allocation. core:crypto has x25519 and poly1305 but not Salsa20, so the cipher is here
// (about 60 lines; the algorithm is public domain, see https://cr.yp.to/snuffle.html).
//
// Sealed layout: [authenticator 16][ciphertext, same size as the message]. DERP packets put the 24 byte nonce in front of it.
package p2p

import "core:crypto"
import "core:crypto/poly1305"
import "core:crypto/x25519"
import "core:math/bits"
import "core:testing"

BOX_KEY_SIZE :: 32
BOX_NONCE_SIZE :: 24
BOX_AUTH_SIZE :: 16

BoxKey :: [BOX_KEY_SIZE]byte

@(private)
SalsaRounds :: proc(x: ^[16]u32) {
    quarter :: #force_inline proc(x: ^[16]u32, a, b, c, d: int) {
        x[b] ~= bits.rotate_left32(x[a] + x[d], 7)
        x[c] ~= bits.rotate_left32(x[b] + x[a], 9)
        x[d] ~= bits.rotate_left32(x[c] + x[b], 13)
        x[a] ~= bits.rotate_left32(x[d] + x[c], 18)
    }
    for _ in 0 ..< 10 {
        quarter(x, 0, 4, 8, 12)
        quarter(x, 5, 9, 13, 1)
        quarter(x, 10, 14, 2, 6)
        quarter(x, 15, 3, 7, 11)
        quarter(x, 0, 1, 2, 3)
        quarter(x, 5, 6, 7, 4)
        quarter(x, 10, 11, 8, 9)
        quarter(x, 15, 12, 13, 14)
    }
}

@(private)
Load32 :: proc(data: []byte) -> u32 {
    return u32(data[0]) | u32(data[1]) << 8 | u32(data[2]) << 16 | u32(data[3]) << 24
}

@(private)
Store32 :: proc(data: []byte, value: u32) {
    data[0] = u8(value)
    data[1] = u8(value >> 8)
    data[2] = u8(value >> 16)
    data[3] = u8(value >> 24)
}

@(private)
SalsaState :: proc(state: ^[16]u32, input: []byte, key: []byte) {
    constant: string = "expand 32-byte k"
    state[0] = Load32(transmute([]byte)constant[0:4])
    state[1] = Load32(key[0:4])
    state[2] = Load32(key[4:8])
    state[3] = Load32(key[8:12])
    state[4] = Load32(key[12:16])
    state[5] = Load32(transmute([]byte)constant[4:8])
    state[6] = Load32(input[0:4])
    state[7] = Load32(input[4:8])
    state[8] = Load32(input[8:12])
    state[9] = Load32(input[12:16])
    state[10] = Load32(transmute([]byte)constant[8:12])
    state[11] = Load32(key[16:20])
    state[12] = Load32(key[20:24])
    state[13] = Load32(key[24:28])
    state[14] = Load32(key[28:32])
    state[15] = Load32(transmute([]byte)constant[12:16])
}

// One 64 byte keystream block: input = 8 byte nonce + 8 byte counter.
SalsaBlock :: proc(output: []byte, input: []byte, key: []byte) {
    state: [16]u32
    SalsaState(&state, input, key)
    work: [16]u32 = state
    SalsaRounds(&work)
    for i in 0 ..< 16 {
        Store32(output[i * 4:], work[i] + state[i])
    }
}

// Derives a 32 byte subkey from a 16 byte input and a 32 byte key (the first step of XSalsa20 and of crypto_box key agreement).
HSalsa :: proc(output: ^[32]byte, input: []byte, key: []byte) {
    state: [16]u32
    SalsaState(&state, input, key)
    SalsaRounds(&state)
    Store32(output[0:], state[0])
    Store32(output[4:], state[5])
    Store32(output[8:], state[10])
    Store32(output[12:], state[15])
    Store32(output[16:], state[6])
    Store32(output[20:], state[7])
    Store32(output[24:], state[8])
    Store32(output[28:], state[9])
}

// XOR with the Salsa20 keystream (8 byte nonce, block counter from `counter`). `output` may be `input`.
@(private)
SalsaXor :: proc(output: []byte, input: []byte, key: []byte, nonce: []byte, counter: u64) {
    block_input: [16]byte
    copy(block_input[:8], nonce)
    block: [64]byte
    counter: u64 = counter
    offset: int
    for offset < len(input) {
        for i in 0 ..< 8 {
            block_input[8 + i] = u8(counter >> uint(8 * i))
        }
        SalsaBlock(block[:], block_input[:], key)
        count: int = min(64, len(input) - offset)
        for i in 0 ..< count {
            output[offset + i] = input[offset + i] ~ block[i]
        }
        offset += count
        counter += 1
    }
}

BoxKeyGenerate :: proc(private: ^BoxKey, public: ^BoxKey) -> bool {
    if !crypto.HAS_RAND_BYTES {
        return false
    }
    crypto.rand_bytes(private[:])
    private[0] &= 248
    private[31] &= 127
    private[31] |= 64
    x25519.scalarmult_basepoint(public[:], private[:])
    return true
}

BoxPublicKey :: proc(private: BoxKey) -> (public: BoxKey) {
    private_copy: BoxKey = private
    x25519.scalarmult_basepoint(public[:], private_copy[:])
    return
}

// The key two parties share (crypto_box_beforenm): X25519, then HSalsa20 with a zero input. Compute it once per peer.
BoxShared :: proc(private: BoxKey, peer_public: BoxKey) -> (shared: BoxKey) {
    private_copy: BoxKey = private
    public_copy: BoxKey = peer_public
    secret: [32]byte
    x25519.scalarmult(secret[:], private_copy[:], public_copy[:])
    zero: [16]byte
    HSalsa(&shared, zero[:], secret[:])
    return
}

// message -> [auth 16][ciphertext] in `output` (len(message) + 16 bytes). The nonce must never repeat for one shared key: random 24
// bytes are enough (BoxNonce).
BoxSeal :: proc(output: []byte, message: []byte, nonce: [BOX_NONCE_SIZE]byte, shared: BoxKey) {
    assert(len(output) >= len(message) + BOX_AUTH_SIZE)
    nonce_copy: [BOX_NONCE_SIZE]byte = nonce
    shared_copy: BoxKey = shared
    subkey: [32]byte
    HSalsa(&subkey, nonce_copy[:16], shared_copy[:])
    first: [64]byte
    SalsaXor(first[:], first[:], subkey[:], nonce_copy[16:], 0)          // the first block is the Poly1305 key and 32 bytes of pad
    ciphertext: []byte = output[BOX_AUTH_SIZE:BOX_AUTH_SIZE + len(message)]
    head: int = min(len(message), 32)
    for i in 0 ..< head {
        ciphertext[i] = message[i] ~ first[32 + i]
    }
    SalsaXor(ciphertext[head:], message[head:], subkey[:], nonce_copy[16:], 1)
    poly1305.sum(output[:BOX_AUTH_SIZE], ciphertext, first[:32])
}

// The opposite: false when the packet was damaged or was not sealed for this key pair.
BoxOpen :: proc(output: []byte, sealed: []byte, nonce: [BOX_NONCE_SIZE]byte, shared: BoxKey) -> bool {
    if len(sealed) < BOX_AUTH_SIZE || len(output) < len(sealed) - BOX_AUTH_SIZE {
        return false
    }
    nonce_copy: [BOX_NONCE_SIZE]byte = nonce
    shared_copy: BoxKey = shared
    subkey: [32]byte
    HSalsa(&subkey, nonce_copy[:16], shared_copy[:])
    first: [64]byte
    SalsaXor(first[:], first[:], subkey[:], nonce_copy[16:], 0)
    ciphertext: []byte = sealed[BOX_AUTH_SIZE:]
    if !poly1305.verify(sealed[:BOX_AUTH_SIZE], ciphertext, first[:32]) {
        return false
    }
    head: int = min(len(ciphertext), 32)
    for i in 0 ..< head {
        output[i] = ciphertext[i] ~ first[32 + i]
    }
    SalsaXor(output[head:len(ciphertext)], ciphertext[head:], subkey[:], nonce_copy[16:], 1)
    return true
}

BoxNonce :: proc() -> (nonce: [BOX_NONCE_SIZE]byte) {
    crypto.rand_bytes(nonce[:])
    return
}

// ---------------------------------------------------------------------------------------------------------------- tests

@(private)
FromHex :: proc(text: string, out: []byte) {
    value :: proc(c: u8) -> u8 {
        switch {
        case c >= '0' && c <= '9':
            return c - '0'
        case c >= 'a' && c <= 'f':
            return c - 'a' + 10
        }
        return 0
    }
    for i in 0 ..< len(text) / 2 {
        out[i] = value(text[2 * i]) << 4 | value(text[2 * i + 1])
    }
}

// Values computed by the derpnet C reference (derpnet.h compiled on its own) for fixed keys, a fixed nonce and four message sizes:
// the same bytes must come out of this implementation (and the live DERP servers accept it, see tool/derp).
@(test)
BoxReferenceTest :: proc(t: ^testing.T) {
    alice, bob: BoxKey
    for i in 0 ..< 32 {
        alice[i] = u8(i + 1)
        bob[i] = u8(0xA0 + i)
    }
    alice[0] &= 248
    alice[31] = alice[31] & 127 | 64
    bob[0] &= 248
    bob[31] = bob[31] & 127 | 64
    expected_alice, expected_bob, expected_shared: BoxKey
    FromHex("07a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c", expected_alice[:])
    FromHex("605a725d2a4adfeeb1a29e17edd621c1b7593ee8cdbc44ac6c4ab6e2f805d23c", expected_bob[:])
    FromHex("be2a85ab99cae8251db5dd19afeee3a14e1cdb0e871a06d4d65f0596e7b30906", expected_shared[:])
    testing.expect_value(t, BoxPublicKey(alice), expected_alice)
    testing.expect_value(t, BoxPublicKey(bob), expected_bob)
    shared: BoxKey = BoxShared(alice, BoxPublicKey(bob))
    testing.expect_value(t, shared, expected_shared)
    testing.expect_value(t, BoxShared(bob, BoxPublicKey(alice)), shared)

    nonce: [BOX_NONCE_SIZE]byte
    for i in 0 ..< 24 {
        nonce[i] = u8(0x40 + i)
    }
    Case :: struct {
        size: int,
        auth: string,
        ciphertext: string,
    }
    cases: [4]Case = {
        {0, "618ca3d5383ed87928923a9d70e8cb67", ""},
        {5, "ec91f530846022843414560de66575d9", "02bf1608e5"},
        {32, "4a501ef30d65e0db148f694af7ab58f3", "02bf1608e5f8ba66eee026ffb3772bd19b1fa7c1c23bd546dfa5986a84c529ee"},
        {100, "fb9f817823209be3a5bb17dc610da873", "02bf1608e5f8ba66eee026ffb3772bd19b1fa7c1c23bd546dfa5986a84c529ee155944f6cbd0bae1ba7dff943c273a772bcfaeb162a76046f3a8680606c9b34a3d38dc9dbd5759ce053bad25a6a49d4208a1a320fe784e4f1797f04519b4bd135cc3d5ba"},
    }
    for item in cases {
        message: [100]byte
        for i in 0 ..< item.size {
            message[i] = u8(i * 7 + 3)
        }
        sealed: [116]byte
        BoxSeal(sealed[:], message[:item.size], nonce, shared)
        expected: [116]byte
        FromHex(item.auth, expected[:16])
        FromHex(item.ciphertext, expected[16:])
        testing.expectf(t, string(sealed[:16 + item.size]) == string(expected[:16 + item.size]), "size %d: sealed bytes differ from the reference", item.size)

        opened: [100]byte
        testing.expect(t, BoxOpen(opened[:], sealed[:16 + item.size], nonce, shared))
        testing.expect(t, string(opened[:item.size]) == string(message[:item.size]))
        if item.size > 0 {
            sealed[16] ~= 1                                      // one flipped bit and it is refused
            testing.expect(t, !BoxOpen(opened[:], sealed[:16 + item.size], nonce, shared))
        }
    }
    // the derived blocks of the reference
    hs: [32]byte
    input: [16]byte
    for i in 0 ..< 16 {
        input[i] = u8(i)
    }
    HSalsa(&hs, input[:], shared[:])
    expected_hs: [32]byte
    FromHex("6ed1962bcbb72f3e675e6bd87821abe67f253e0e4cd031db0f81ca074c68d286", expected_hs[:])
    testing.expect_value(t, hs, expected_hs)
    block: [64]byte
    for i in 0 ..< 16 {
        input[i] = u8(0x80 + i)
    }
    SalsaBlock(block[:], input[:], shared[:])
    expected_block: [64]byte
    FromHex("2ea3155bd1101ab4688a2a479b35884e6fed8d4e19c394576d0e82bb6b195bf44ff4b7941fa0ac051c1161fefa079fcd35c88c06b916f0205fe76e01579db555", expected_block[:])
    testing.expect_value(t, block, expected_block)
}

@(test)
BoxRandomTest :: proc(t: ^testing.T) {
    private_a, public_a, private_b, public_b: BoxKey
    testing.expect(t, BoxKeyGenerate(&private_a, &public_a))
    testing.expect(t, BoxKeyGenerate(&private_b, &public_b))
    shared: BoxKey = BoxShared(private_a, public_b)
    testing.expect_value(t, BoxShared(private_b, public_a), shared)
    // every size around the block edges (64) and the 32 byte first-block split, sealed in place of different buffers
    for size in 0 ..< 200 {
        message: [200]byte
        crypto.rand_bytes(message[:size])
        nonce: [BOX_NONCE_SIZE]byte = BoxNonce()
        sealed: [216]byte
        BoxSeal(sealed[:], message[:size], nonce, shared)
        opened: [200]byte
        testing.expect(t, BoxOpen(opened[:], sealed[:16 + size], nonce, shared))
        testing.expect(t, string(opened[:size]) == string(message[:size]))
        other: [BOX_NONCE_SIZE]byte = nonce
        other[0] ~= 1
        testing.expect(t, !BoxOpen(opened[:], sealed[:16 + size], other, shared))      // wrong nonce
    }
}
