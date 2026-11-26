#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

// Encrypting the stored sign in with a key that the system keeps (the keychain of macOS, the Secret Service of Linux, see protect_other.odin): ChaCha20-Poly1305, a fresh random nonce for every
// sealing, the entropy string of the store as the associated data (a file made for another purpose does not open). The cipher is `nonce (12) | encrypted | tag (16)`. Pure computation, the part of the
// protection that is tested on every system.

import "core:crypto"
import "core:crypto/chacha20poly1305"
import "core:testing"

AEAD_NONCE :: chacha20poly1305.IV_SIZE
AEAD_TAG :: chacha20poly1305.TAG_SIZE
AEAD_KEY :: chacha20poly1305.KEY_SIZE
AEAD_OVERHEAD :: AEAD_NONCE + AEAD_TAG

@(private)
aeadSeal :: proc(key: []u8, plain: []u8, associated: string, out: []u8) -> (cipher: []u8, ok: bool) {
    if len(key) != AEAD_KEY || len(out) < len(plain) + AEAD_OVERHEAD { return nil, false }
    nonce: []u8 = out[:AEAD_NONCE]
    crypto.rand_bytes(nonce)
    sealing: chacha20poly1305.Context
    chacha20poly1305.init(&sealing, key)
    defer chacha20poly1305.reset(&sealing)
    body: int = AEAD_NONCE + len(plain)
    chacha20poly1305.seal(&sealing, out[AEAD_NONCE:body], out[body:body + AEAD_TAG], nonce, transmute([]u8)associated, plain)
    return out[:body + AEAD_TAG], true
}

@(private)
aeadOpen :: proc(key: []u8, cipher: []u8, associated: string, out: []u8) -> (plain: []u8, ok: bool) {
    if len(key) != AEAD_KEY || len(cipher) < AEAD_OVERHEAD { return nil, false }
    length: int = len(cipher) - AEAD_OVERHEAD
    if len(out) < length { return nil, false }
    opening: chacha20poly1305.Context
    chacha20poly1305.init(&opening, key)
    defer chacha20poly1305.reset(&opening)
    if !chacha20poly1305.open(&opening, out[:length], cipher[:AEAD_NONCE], transmute([]u8)associated, cipher[AEAD_NONCE:AEAD_NONCE + length], cipher[AEAD_NONCE + length:]) { return nil, false }
    return out[:length], true
}

@(test)
test_the_sealed_store_opens_only_with_its_key_and_purpose :: proc(t: ^testing.T) {
    key: [AEAD_KEY]u8
    crypto.rand_bytes(key[:])
    plain: string = "refresh-token-value"
    sealed_buffer: [128]u8
    sealed, ok := aeadSeal(key[:], transmute([]u8)plain, "purpose", sealed_buffer[:])
    testing.expect(t, ok)
    testing.expect_value(t, len(sealed), len(plain) + AEAD_OVERHEAD)
    testing.expect(t, !bytesContain(sealed, plain), "the token is not in the sealed bytes")
    out: [128]u8
    opened, opened_ok := aeadOpen(key[:], sealed, "purpose", out[:])
    testing.expect(t, opened_ok && string(opened) == plain)
    // another purpose, another key, a changed byte, a short input: nothing opens
    _, other_purpose := aeadOpen(key[:], sealed, "other", out[:])
    testing.expect(t, !other_purpose)
    wrong: [AEAD_KEY]u8
    _, other_key := aeadOpen(wrong[:], sealed, "purpose", out[:])
    testing.expect(t, !other_key)
    changed: [128]u8
    copy(changed[:], sealed)
    changed[AEAD_NONCE + 2] ~= 1
    _, tampered := aeadOpen(key[:], changed[:len(sealed)], "purpose", out[:])
    testing.expect(t, !tampered)
    _, short := aeadOpen(key[:], sealed[:AEAD_OVERHEAD - 1], "purpose", out[:])
    testing.expect(t, !short)
    // two sealings of the same text differ (a new nonce each time)
    again_buffer: [128]u8
    again, _ := aeadSeal(key[:], transmute([]u8)plain, "purpose", again_buffer[:])
    testing.expect(t, string(again) != string(sealed))
}

@(private = "file")
bytesContain :: proc(bytes: []u8, text: string) -> bool {
    for i in 0 ..= len(bytes) - len(text) {
        if string(bytes[i:i + len(text)]) == text { return true }
    }
    return false
}
