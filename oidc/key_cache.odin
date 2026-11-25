#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

// The keys of a provider for a program that checks many tokens (a server, a game that verifies every player): fetched once, kept for `max_age`, and fetched again when a token does not fit the keys
// that are held, because a provider rotates its keys and a token signed with the new one arrives before the cache expires.
//
//     cache: KeyCache                                              // zero value: one hour, 30 seconds between refetches, `FetchKeys`
//     claims, error := KeyCacheVerify(&cache, &metadata, token, {issuer = iss, audience = client}, scratch[:])
//
// A token that is not signed by a held key (`NO_KEY`, `SIGNATURE`) makes one new fetch and one more check; that is how a rotation is followed. The refetch is not done more often than `min_gap`
// whatever arrives, so a flood of forged tokens cannot make the program hammer the provider. A fetch that fails keeps the keys that are held (a provider that is down for a minute does not log
// everybody out): the answer is then the one of the old keys.
//
// Limits: one provider per cache (the keys are the ones of `metadata.jwks_uri`), no thread safety (one cache per thread, or the caller locks), a key that the provider withdrew stays valid for up
//     to `max_age` (a program that must react at once calls `KeyCacheClear`), the time is the monotonic clock of the program, not the `Cache-Control` of the provider.

import "core:time"

KEY_CACHE_MAX_AGE_DEFAULT :: time.Hour
KEY_CACHE_MIN_GAP_DEFAULT :: 30 * time.Second

KeyCache :: struct {
    keys: KeySet,
    loaded: bool,
    fetched: time.Tick,                 // when the held keys came
    last_attempt: time.Tick,            // the last fetch, successful or not: `min_gap` counts from it
    attempted: bool,
    max_age: time.Duration,             // 0: KEY_CACHE_MAX_AGE_DEFAULT
    min_gap: time.Duration,             // 0: KEY_CACHE_MIN_GAP_DEFAULT
    fetch: proc(user: rawptr, metadata: ^Metadata, keys: ^KeySet) -> bool,    // nil: `FetchKeys`; a test or a program with its own transport puts its own
    user: rawptr,
    fetches: int,                       // how many fetches were made (successful or not), for the program that wants to show or test it
}

// Forgets the keys: the next check fetches them
KeyCacheClear :: proc(cache: ^KeyCache) {
    cache.loaded = false
    cache.keys = {}
}

// Checks a token with the held keys; fetches them when they are missing or too old, and once more when the token does not fit them. The result is the one of `JwtVerify`; `NO_KEY` is also the answer when
// there are no keys at all and they could not be fetched.
KeyCacheVerify :: proc(cache: ^KeyCache, metadata: ^Metadata, token: string, options: VerifyOptions, scratch: []u8) -> (claims: JwtClaims, error: VerifyError) {
    max_age: time.Duration = cache.max_age if cache.max_age > 0 else KEY_CACHE_MAX_AGE_DEFAULT
    if !cache.loaded || time.tick_since(cache.fetched) > max_age {
        keyCacheFetch(cache, metadata)                      // a failure keeps what is held (and loaded stays what it was)
        if !cache.loaded { return {}, .NO_KEY }
    }
    claims, error = JwtVerify(token, &cache.keys, options, scratch)
    if error != .NO_KEY && error != .SIGNATURE { return }
    min_gap: time.Duration = cache.min_gap if cache.min_gap > 0 else KEY_CACHE_MIN_GAP_DEFAULT
    if cache.attempted && time.tick_since(cache.last_attempt) < min_gap { return }
    if keyCacheFetch(cache, metadata) { claims, error = JwtVerify(token, &cache.keys, options, scratch) }
    return
}

// One fetch into a fresh set that replaces the held one only when it worked and holds a key
@(private)
keyCacheFetch :: proc(cache: ^KeyCache, metadata: ^Metadata) -> bool {
    cache.fetches += 1
    cache.attempted = true
    cache.last_attempt = time.tick_now()
    fresh: ^KeySet = new(KeySet, context.temp_allocator)
    ok: bool = cache.fetch(cache.user, metadata, fresh) if cache.fetch != nil else FetchKeys(metadata, fresh)
    if !ok || fresh.count == 0 { return false }
    cache.keys = fresh^
    cache.loaded = true
    cache.fetched = time.tick_now()
    return true
}
