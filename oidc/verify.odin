#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

// Checking an ID token: the signature against the keys of the provider (its JWKS), then the claims. ES256 (ECDSA P-256) and RS256 (RSA PKCS#1 v1.5) are accepted, the two that OIDC providers and
// SpacetimeDB use; `none` and the shared secret ones (HS256 ...) are refused, because a token that anybody can make is not a login. No allocation: the keys live in a `KeySet` of the caller.
//
//     keys: KeySet
//     JwksParse(jwks_json, &keys)
//     claims, error := JwtVerify(id_token, &keys, {issuer = "https://auth.example.com", audience = "my-client-id", nonce = nonce}, scratch[:])

import "core:crypto/ecdsa"
import "core:crypto/rsa"
import "core:encoding/json"
import "core:mem"
import "core:time"

MAX_KEYS :: 8
MAX_MODULUS :: 512              // bytes: up to a 4096 bit RSA key

KeyKind :: enum u8 {
    NONE,
    EC_P256,
    RSA,
}

Key :: struct {
    kind: KeyKind,
    id: [64]u8,                 // kid
    id_length: int,
    point: [65]u8,              // EC: the uncompressed point 0x04 | x | y
    modulus: [MAX_MODULUS]u8,   // RSA
    modulus_length: int,
    exponent: [8]u8,
    exponent_length: int,
}

KeySet :: struct {
    keys: [MAX_KEYS]Key,
    count: int,
}

// The keys of a JWKS document (`{"keys": [...]}`): the EC P-256 and RSA ones; others (and keys meant for encryption) are skipped. False when it is not a JWKS or holds no usable key.
JwksParse :: proc(document: string, set: ^KeySet) -> bool {
    set.count = 0
    scratch: [32768]u8
    arena: mem.Arena
    mem.arena_init(&arena, scratch[:])
    allocator: mem.Allocator = mem.arena_allocator(&arena)
    value, error := json.parse(transmute([]u8)document, json.DEFAULT_SPECIFICATION, true, allocator)
    if error != .None { return false }
    object, is_object := value.(json.Object)
    if !is_object { return false }
    list, is_list := object["keys"].(json.Array)
    if !is_list { return false }
    for entry in list {
        if set.count >= MAX_KEYS { break }
        item, is_item := entry.(json.Object)
        if !is_item { continue }
        if usage, has_usage := item["use"].(json.String); has_usage && usage != "sig" { continue }
        kind, has_kind := item["kty"].(json.String)
        if !has_kind { continue }
        key: Key
        if id, has_id := item["kid"].(json.String); has_id { key.id_length = copy(key.id[:], id) }
        switch kind {
        case "EC":
            curve, _ := item["crv"].(json.String)
            x, _ := item["x"].(json.String)
            y, _ := item["y"].(json.String)
            if curve != "P-256" { continue }
            key.point[0] = 4
            x_bytes, x_ok := Base64UrlDecode(x, key.point[1:33])
            y_bytes, y_ok := Base64UrlDecode(y, key.point[33:65])
            if !x_ok || !y_ok || len(x_bytes) != 32 || len(y_bytes) != 32 { continue }
            key.kind = .EC_P256
        case "RSA":
            n, _ := item["n"].(json.String)
            e, _ := item["e"].(json.String)
            n_bytes, n_ok := Base64UrlDecode(n, key.modulus[:])
            e_bytes, e_ok := Base64UrlDecode(e, key.exponent[:])
            if !n_ok || !e_ok || len(n_bytes) == 0 || len(e_bytes) == 0 { continue }
            key.modulus_length, key.exponent_length = len(n_bytes), len(e_bytes)
            key.kind = .RSA
        case: continue
        }
        set.keys[set.count] = key
        set.count += 1
    }
    return set.count > 0
}

VerifyOptions :: struct {
    issuer: string,             // "" does not check it (do check it: a token of another provider is not yours)
    audience: string,           // the client id the token was made for
    nonce: string,              // the nonce sent in the authorization request
    leeway: i64,                // seconds of clock difference that are forgiven (0: 60)
    now: i64,                   // seconds since the Unix epoch (0: the clock)
    allow_no_expiry: bool,      // a token without `exp` is refused unless this is set
}

VerifyError :: enum u8 {
    NONE,
    MALFORMED,                  // not a JWT, or the header or payload are not what they should be
    ALGORITHM,                  // none, a shared secret algorithm, or one that is not supported
    NO_KEY,                     // no key of the set fits (kid, algorithm)
    SIGNATURE,                  // the signature is not the one of this token
    ISSUER,
    AUDIENCE,
    EXPIRED,
    NOT_YET,                    // nbf or iat in the future
    NONCE,
}

NowUnix :: proc() -> i64 {
    return time.to_unix_seconds(time.now())
}

// Checks the token and returns its claims (the strings point into `scratch`, which holds the decoded payload)
JwtVerify :: proc(token: string, keys: ^KeySet, options: VerifyOptions, scratch: []u8) -> (claims: JwtClaims, error: VerifyError) {
    jwt, split := JwtSplit(token)
    if !split || jwt.signature == "" { return {}, .MALFORMED }
    header_scratch: [512]u8
    header, header_ok := JwtHeaderRead(token, header_scratch[:])
    if !header_ok { return {}, .MALFORMED }
    wanted: KeyKind
    switch header.algorithm {
    case "ES256": wanted = .EC_P256
    case "RS256": wanted = .RSA
    case: return {}, .ALGORITHM
    }
    signature_scratch: [MAX_MODULUS]u8
    signature, signature_ok := Base64UrlDecode(jwt.signature, signature_scratch[:])
    if !signature_ok { return {}, .MALFORMED }

    verified: bool
    found: bool
    for i in 0 ..< keys.count {
        key: ^Key = &keys.keys[i]
        if key.kind != wanted { continue }
        if header.key_id != "" && key.id_length > 0 && string(key.id[:key.id_length]) != header.key_id { continue }
        found = true
        if keyVerifies(key, jwt.signing_input, signature) {
            verified = true
            break
        }
    }
    if !found { return {}, .NO_KEY }
    if !verified { return {}, .SIGNATURE }

    parsed, claims_ok := JwtPayloadClaims(jwt.payload, scratch)
    if !claims_ok { return {}, .MALFORMED }
    claims = parsed
    now: i64 = options.now if options.now != 0 else NowUnix()
    leeway: i64 = options.leeway if options.leeway != 0 else 60
    if options.issuer != "" && claims.issuer != options.issuer { return claims, .ISSUER }
    if options.audience != "" && !JwtAudienceHas(claims, options.audience) { return claims, .AUDIENCE }
    if claims.has_expires {
        if now > claims.expires + leeway { return claims, .EXPIRED }
    } else if !options.allow_no_expiry {
        return claims, .EXPIRED
    }
    if claims.not_before != 0 && now + leeway < claims.not_before { return claims, .NOT_YET }
    if claims.issued != 0 && now + leeway < claims.issued { return claims, .NOT_YET }
    if options.nonce != "" && claims.nonce != options.nonce { return claims, .NONCE }
    return claims, .NONE
}

@(private)
keyVerifies :: proc(key: ^Key, message: string, signature: []u8) -> bool {
    switch key.kind {
    case .EC_P256:
        if len(signature) != 64 { return false }
        public: ecdsa.Public_Key
        if !ecdsa.public_key_set_bytes(&public, .SECP256R1, key.point[:]) { return false }
        return ecdsa.verify_raw(&public, .SHA256, transmute([]u8)message, signature)
    case .RSA:
        public: rsa.Public_Key
        if !rsa.public_key_set_bytes(&public, key.modulus[:key.modulus_length], key.exponent[:key.exponent_length]) { return false }
        return rsa.verify_pkcs1(&public, .SHA256, transmute([]u8)message, signature)
    case .NONE:
    }
    return false
}

VerifyErrorText :: proc(error: VerifyError) -> string {
    switch error {
    case .NONE: return "ok"
    case .MALFORMED: return "not a valid token"
    case .ALGORITHM: return "the algorithm is not accepted (only ES256 and RS256)"
    case .NO_KEY: return "the provider has no key for this token"
    case .SIGNATURE: return "the signature is wrong"
    case .ISSUER: return "the token comes from another provider"
    case .AUDIENCE: return "the token is for another application"
    case .EXPIRED: return "the token has expired"
    case .NOT_YET: return "the token is not valid yet (check the clock)"
    case .NONCE: return "the nonce is not the one of this login"
    }
    return ""
}
