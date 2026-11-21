#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

// Making tokens: for the provider of a test (oidc/mock), for a service that issues its own tokens (SpacetimeDB accepts ES256 and RS256 tokens of any issuer that serves a discovery document and a
// JWKS), and for the tests of verify.odin. Caller buffers, no allocation.

import "core:crypto/ecdsa"
import "core:crypto/rsa"
import "core:fmt"

// `header.payload.signature` for a payload JSON, signed with ES256 into `out` (it needs about 4/3 of the payload plus 200 bytes). "" when it does not fit.
JwtSignEs256 :: proc(key: ^ecdsa.Private_Key, key_id: string, payload_json: string, out: []u8) -> string {
    header: string = fmt.tprintf("{{\"alg\":\"ES256\",\"typ\":\"JWT\",\"kid\":\"%s\"}}", key_id)
    signing, ok := signingInput(header, payload_json, out)
    if !ok { return "" }
    signature: [64]u8
    if !ecdsa.sign_raw(key, .SHA256, transmute([]u8)signing, signature[:]) { return "" }
    return finish(signing, signature[:], out)
}

JwtSignRs256 :: proc(key: ^rsa.Private_Key, key_id: string, payload_json: string, out: []u8) -> string {
    header: string = fmt.tprintf("{{\"alg\":\"RS256\",\"typ\":\"JWT\",\"kid\":\"%s\"}}", key_id)
    signing, ok := signingInput(header, payload_json, out)
    if !ok { return "" }
    signature: [MAX_MODULUS]u8
    size: int = rsa.private_key_size(key)
    if size > len(signature) || !rsa.sign_pkcs1(key, .SHA256, transmute([]u8)signing, signature[:size]) { return "" }
    return finish(signing, signature[:size], out)
}

@(private)
signingInput :: proc(header: string, payload: string, out: []u8) -> (signing: string, ok: bool) {
    needed: int = Base64UrlLength(len(header)) + 1 + Base64UrlLength(len(payload)) + 1 + Base64UrlLength(MAX_MODULUS)
    if len(out) < needed { return "", false }
    at: int
    part: string = Base64UrlEncode(transmute([]u8)header, out[at:])
    at += len(part)
    out[at] = '.'
    at += 1
    part = Base64UrlEncode(transmute([]u8)payload, out[at:])
    at += len(part)
    return string(out[:at]), true
}

@(private)
finish :: proc(signing: string, signature: []u8, out: []u8) -> string {
    at: int = len(signing)
    out[at] = '.'
    at += 1
    part: string = Base64UrlEncode(signature, out[at:])
    return string(out[:at + len(part)])
}

// The JWK (JSON) of the public key of an ES256 private key: for a JWKS document
JwkOfEs256 :: proc(key: ^ecdsa.Private_Key, key_id: string, out: []u8) -> string {
    point: [65]u8
    ecdsa.private_key_public_bytes(key, point[:])
    x_text: [48]u8
    y_text: [48]u8
    x: string = Base64UrlEncode(point[1:33], x_text[:])
    y: string = Base64UrlEncode(point[33:65], y_text[:])
    return fmt.bprintf(out, "{{\"kty\":\"EC\",\"crv\":\"P-256\",\"use\":\"sig\",\"alg\":\"ES256\",\"kid\":\"%s\",\"x\":\"%s\",\"y\":\"%s\"}}", key_id, x, y)
}

JwkOfRs256 :: proc(key: ^rsa.Private_Key, key_id: string, out: []u8) -> string {
    public: rsa.Public_Key
    rsa.public_key_set_priv(&public, key)
    modulus: [MAX_MODULUS]u8
    n_length: int = rsa.public_key_n(&public, modulus[:])
    exponent: u32 = rsa.public_key_e(&public)
    e_bytes: [4]u8 = {u8(exponent >> 24), u8(exponent >> 16), u8(exponent >> 8), u8(exponent)}
    e_start: int
    for e_start < 3 && e_bytes[e_start] == 0 { e_start += 1 }
    n_text: [MAX_MODULUS * 2]u8
    e_text: [16]u8
    n: string = Base64UrlEncode(modulus[:n_length], n_text[:])
    e: string = Base64UrlEncode(e_bytes[e_start:], e_text[:])
    return fmt.bprintf(out, "{{\"kty\":\"RSA\",\"use\":\"sig\",\"alg\":\"RS256\",\"kid\":\"%s\",\"n\":\"%s\",\"e\":\"%s\"}}", key_id, n, e)
}
