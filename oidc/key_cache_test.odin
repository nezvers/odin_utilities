#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

import "core:crypto/ecdsa"
import "core:fmt"
import "core:testing"
import "core:time"

// The cache with a provider that is a procedure: the JWKS it serves is what the test says, and it counts how often it was asked.

@(private = "file")
Provider :: struct {
    jwks: [2048]u8,
    jwks_length: int,
    fail: bool,
    asked: int,
}

@(private = "file")
serve :: proc(user: rawptr, metadata: ^Metadata, keys: ^KeySet) -> bool {
    provider: ^Provider = cast(^Provider)user
    provider.asked += 1
    if provider.fail { return false }
    return JwksParse(string(provider.jwks[:provider.jwks_length]), keys)
}

@(private = "file")
publish :: proc(provider: ^Provider, ids: []string, keys: []^ecdsa.Private_Key) {
    jwk: [512]u8
    text: [2048]u8
    length: int
    length += copy(text[length:], "{\"keys\":[")
    for key, i in keys {
        if i > 0 { length += copy(text[length:], ",") }
        length += copy(text[length:], JwkOfEs256(key, ids[i], jwk[:]))
    }
    length += copy(text[length:], "]}")
    provider.jwks = {}
    provider.jwks_length = copy(provider.jwks[:], string(text[:length]))
}

@(private = "file")
tokenOf :: proc(key: ^ecdsa.Private_Key, id: string, out: []u8) -> string {
    return JwtSignEs256(key, id, fmt.tprintf("{{\"iss\":\"https://iss\",\"sub\":\"user-1\",\"aud\":\"client\",\"exp\":%d,\"iat\":1700000000}}", i64(1_800_000_000 + 600)), out)
}

@(test)
test_the_cache_fetches_once_and_follows_a_rotation_but_not_a_flood :: proc(t: ^testing.T) {
    old_key, new_key, stranger: ecdsa.Private_Key
    testing.expect(t, ecdsa.private_key_generate(&old_key, .SECP256R1))
    testing.expect(t, ecdsa.private_key_generate(&new_key, .SECP256R1))
    testing.expect(t, ecdsa.private_key_generate(&stranger, .SECP256R1))
    provider: ^Provider = new(Provider)
    defer free(provider)
    publish(provider, {"old"}, {&old_key})
    cache: ^KeyCache = new(KeyCache)
    defer free(cache)
    cache.fetch, cache.user = serve, provider
    cache.min_gap = 200 * time.Millisecond
    metadata: ^Metadata = new(Metadata)
    defer free(metadata)
    out: [1024]u8
    scratch: [512]u8
    options: VerifyOptions = {issuer = "https://iss", audience = "client", now = 1_800_000_000}

    // the first check fetches, the second uses what is held
    _, error := KeyCacheVerify(cache, metadata, tokenOf(&old_key, "old", out[:]), options, scratch[:])
    testing.expect_value(t, error, VerifyError.NONE)
    _, error = KeyCacheVerify(cache, metadata, tokenOf(&old_key, "old", out[:]), options, scratch[:])
    testing.expect_value(t, error, VerifyError.NONE)
    testing.expect_value(t, provider.asked, 1)

    // the provider rotates: a token of the new key does not fit, but the gap since the fetch is too short to ask again
    publish(provider, {"old", "new"}, {&old_key, &new_key})
    _, error = KeyCacheVerify(cache, metadata, tokenOf(&new_key, "new", out[:]), options, scratch[:])
    testing.expect_value(t, error, VerifyError.NO_KEY)
    testing.expect_value(t, provider.asked, 1)
    // after the gap the same token makes one fetch and is accepted; the old key still works
    time.sleep(250 * time.Millisecond)
    _, error = KeyCacheVerify(cache, metadata, tokenOf(&new_key, "new", out[:]), options, scratch[:])
    testing.expect_value(t, error, VerifyError.NONE)
    testing.expect_value(t, provider.asked, 2)
    _, error = KeyCacheVerify(cache, metadata, tokenOf(&old_key, "old", out[:]), options, scratch[:])
    testing.expect_value(t, error, VerifyError.NONE)

    // forged tokens (a key nobody published) ask the provider at most once per gap, and are refused
    time.sleep(250 * time.Millisecond)
    for _ in 0 ..< 20 {
        _, error = KeyCacheVerify(cache, metadata, tokenOf(&stranger, "new", out[:]), options, scratch[:])
        testing.expect_value(t, error, VerifyError.SIGNATURE)
    }
    testing.expect_value(t, provider.asked, 3)
}

@(test)
test_a_provider_that_is_down_keeps_the_held_keys_and_an_empty_cache_has_no_key :: proc(t: ^testing.T) {
    key: ecdsa.Private_Key
    testing.expect(t, ecdsa.private_key_generate(&key, .SECP256R1))
    provider: ^Provider = new(Provider)
    defer free(provider)
    publish(provider, {"k"}, {&key})
    cache: ^KeyCache = new(KeyCache)
    defer free(cache)
    cache.fetch, cache.user = serve, provider
    cache.max_age = 100 * time.Millisecond
    metadata: ^Metadata = new(Metadata)
    defer free(metadata)
    out: [1024]u8
    scratch: [512]u8
    options: VerifyOptions = {issuer = "https://iss", audience = "client", now = 1_800_000_000}

    // nothing held and nothing to fetch: NO_KEY, not a crash
    provider.fail = true
    _, error := KeyCacheVerify(cache, metadata, tokenOf(&key, "k", out[:]), options, scratch[:])
    testing.expect_value(t, error, VerifyError.NO_KEY)
    // the provider comes up
    provider.fail = false
    _, error = KeyCacheVerify(cache, metadata, tokenOf(&key, "k", out[:]), options, scratch[:])
    testing.expect_value(t, error, VerifyError.NONE)
    // the keys are old and the provider is down again: the held keys still check
    time.sleep(150 * time.Millisecond)
    provider.fail = true
    asked: int = provider.asked
    _, error = KeyCacheVerify(cache, metadata, tokenOf(&key, "k", out[:]), options, scratch[:])
    testing.expect_value(t, error, VerifyError.NONE)
    testing.expect_value(t, provider.asked, asked + 1)
    // cleared: asked again
    KeyCacheClear(cache)
    provider.fail = false
    _, error = KeyCacheVerify(cache, metadata, tokenOf(&key, "k", out[:]), options, scratch[:])
    testing.expect_value(t, error, VerifyError.NONE)
}
