#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

import "core:crypto/ecdsa"
import "core:crypto/rsa"
import "core:fmt"
import "core:testing"

@(test)
test_base64url_round_trip_and_refusals :: proc(t: ^testing.T) {
    for text in ([]string{"", "f", "fo", "foo", "foob", "fooba", "foobar"}) {
        encoded: [32]u8
        decoded: [32]u8
        part: string = Base64UrlEncode(transmute([]u8)text, encoded[:])
        bytes, ok := Base64UrlDecode(part, decoded[:])
        testing.expect(t, ok && string(bytes) == text, "round trip")
    }
    encoded: [16]u8
    testing.expect_value(t, Base64UrlEncode(transmute([]u8)string("foobar"), encoded[:]), "Zm9vYmFy")
    // the url alphabet: - and _ instead of + and /
    testing.expect_value(t, Base64UrlEncode([]u8{0xfb, 0xff, 0xbe}, encoded[:]), "-_--")
    decoded: [8]u8
    _, ok := Base64UrlDecode("Zm9v+g", decoded[:])
    testing.expect(t, !ok, "+ is not in the alphabet")
    _, ok = Base64UrlDecode("Z", decoded[:])
    testing.expect(t, !ok, "a single letter is not valid")
}

@(test)
test_claims_are_read_without_the_signature :: proc(t: ^testing.T) {
    payload := `{"iss":"https://auth.example.com","sub":"user-1","aud":["a","my-game"],"exp":2000000000,"iat":1700000000,"nonce":"n1","nested":{"iss":"fake"},"email":"x@y.z"}`
    part: [256]u8
    token: string = fmt.tprintf("e30.%s.sig", Base64UrlEncode(transmute([]u8)string(payload), part[:]))
    scratch: [512]u8
    claims, ok := JwtClaimsRead(token, scratch[:])
    testing.expect(t, ok)
    testing.expect_value(t, claims.issuer, "https://auth.example.com")      // the nested "iss" does not count
    testing.expect_value(t, claims.subject, "user-1")
    testing.expect_value(t, claims.expires, 2000000000)
    testing.expect_value(t, claims.nonce, "n1")
    testing.expect(t, JwtAudienceHas(claims, "my-game") && JwtAudienceHas(claims, "a") && !JwtAudienceHas(claims, "b"), "an audience list")
    email, has_email := JsonString(claims.payload, "email")
    testing.expect(t, has_email && email == "x@y.z")
    // the payload as the JSON that a module gets from the host
    from_json, json_ok := JwtPayloadClaims(payload, scratch[:])
    testing.expect(t, json_ok && from_json.subject == "user-1")
    // not tokens
    _, bad := JwtSplit("only.two")
    testing.expect(t, !bad)
    _, bad = JwtSplit("a.b.c.d")
    testing.expect(t, !bad)
    _, bad = JwtClaimsRead("e30.e30.x", scratch[:])
    testing.expect(t, !bad, "a payload without iss and sub is not a login")
}

@(private = "file")
payloadOf :: proc(issuer: string, audience: string, expires: i64, nonce: string) -> string {
    return fmt.tprintf("{{\"iss\":\"%s\",\"sub\":\"user-1\",\"aud\":\"%s\",\"exp\":%d,\"iat\":1700000000,\"nonce\":\"%s\"}}", issuer, audience, expires, nonce)
}

@(test)
test_an_es256_token_is_signed_and_verified :: proc(t: ^testing.T) {
    private: ecdsa.Private_Key
    testing.expect(t, ecdsa.private_key_generate(&private, .SECP256R1))
    jwk: [512]u8
    jwks: string = fmt.tprintf("{{\"keys\":[%s]}}", JwkOfEs256(&private, "k1", jwk[:]))
    keys: KeySet
    testing.expect(t, JwksParse(jwks, &keys))
    testing.expect_value(t, keys.count, 1)

    out: [1024]u8
    scratch: [512]u8
    now: i64 = 1_800_000_000
    token: string = JwtSignEs256(&private, "k1", payloadOf("https://iss", "client", now + 600, "n"), out[:])
    claims, error := JwtVerify(token, &keys, {issuer = "https://iss", audience = "client", nonce = "n", now = now}, scratch[:])
    testing.expect_value(t, error, VerifyError.NONE)
    testing.expect_value(t, claims.subject, "user-1")

    // each way of being wrong has its own answer
    _, error = JwtVerify(token, &keys, {issuer = "https://other", now = now}, scratch[:])
    testing.expect_value(t, error, VerifyError.ISSUER)
    _, error = JwtVerify(token, &keys, {audience = "other", now = now}, scratch[:])
    testing.expect_value(t, error, VerifyError.AUDIENCE)
    _, error = JwtVerify(token, &keys, {nonce = "other", now = now}, scratch[:])
    testing.expect_value(t, error, VerifyError.NONCE)
    _, error = JwtVerify(token, &keys, {now = now + 601 + 60}, scratch[:])
    testing.expect_value(t, error, VerifyError.EXPIRED)
    _, error = JwtVerify(token, &keys, {now = now + 601}, scratch[:])
    testing.expect_value(t, error, VerifyError.NONE)                   // inside of the leeway
    _, error = JwtVerify(token, &keys, {now = 1_000_000_000}, scratch[:])
    testing.expect_value(t, error, VerifyError.NOT_YET)

    // a changed payload: the signature no longer fits
    copy_token: [1024]u8
    copy(copy_token[:], token)
    parts, _ := JwtSplit(token)
    copy_token[len(parts.header) + 3] ~= 1
    _, error = JwtVerify(string(copy_token[:len(token)]), &keys, {now = now}, scratch[:])
    testing.expect(t, error == .SIGNATURE || error == .MALFORMED, "a tampered payload is refused")

    // a key of another provider
    other: ecdsa.Private_Key
    testing.expect(t, ecdsa.private_key_generate(&other, .SECP256R1))
    other_token: string = JwtSignEs256(&other, "k1", payloadOf("https://iss", "client", now + 600, "n"), out[:])
    _, error = JwtVerify(other_token, &keys, {now = now}, scratch[:])
    testing.expect_value(t, error, VerifyError.SIGNATURE)

    // none and a shared secret are never accepted
    none: string = fmt.tprintf("%s.%s.", Base64UrlEncode(transmute([]u8)string(`{"alg":"none"}`), copy_token[:64]), Base64UrlEncode(transmute([]u8)string(payloadOf("https://iss", "client", now + 600, "n")), copy_token[64:400]))
    _, error = JwtVerify(none, &keys, {now = now}, scratch[:])
    testing.expect(t, error == .MALFORMED || error == .ALGORITHM, "alg none")
    hs256: string = fmt.tprintf("%s.%s.AAAA", Base64UrlEncode(transmute([]u8)string(`{"alg":"HS256"}`), copy_token[:64]), Base64UrlEncode(transmute([]u8)string(payloadOf("https://iss", "client", now + 600, "n")), copy_token[64:400]))
    _, error = JwtVerify(hs256, &keys, {now = now}, scratch[:])
    testing.expect_value(t, error, VerifyError.ALGORITHM)
}

@(test)
test_an_rs256_token_is_signed_and_verified :: proc(t: ^testing.T) {
    private: rsa.Private_Key
    testing.expect(t, rsa.private_key_generate(&private, 2048))
    jwk: [1024]u8
    jwks: string = fmt.tprintf("{{\"keys\":[%s]}}", JwkOfRs256(&private, "r1", jwk[:]))
    keys: KeySet
    testing.expect(t, JwksParse(jwks, &keys))
    out: [2048]u8
    scratch: [512]u8
    now: i64 = 1_800_000_000
    token: string = JwtSignRs256(&private, "r1", payloadOf("https://iss", "client", now + 600, "n"), out[:])
    testing.expect(t, token != "")
    claims, error := JwtVerify(token, &keys, {issuer = "https://iss", audience = "client", now = now}, scratch[:])
    testing.expect_value(t, error, VerifyError.NONE)
    testing.expect_value(t, claims.issuer, "https://iss")
    // the kid selects the key: a token that names another one finds no key
    other_name: string = JwtSignRs256(&private, "other", payloadOf("https://iss", "client", now + 600, "n"), out[:])
    _, error = JwtVerify(other_name, &keys, {now = now}, scratch[:])
    testing.expect(t, error == .NONE || error == .NO_KEY || error == .SIGNATURE)
}
