#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

// Against real providers on the internet: `OIDC_LIVE=1 odin test oidc`. Nothing here needs an account of ours: the discovery documents and the keys of the big providers are public, and the demo
// server of Duende IdentityServer issues tokens for the public demo client (`m2m` / `secret`, documented at demo.duendesoftware.com), so a real RS256 token of a real provider is verified.

@(test)
test_real_providers_discovery_and_keys :: proc(t: ^testing.T) {
    if os.get_env("OIDC_LIVE", context.temp_allocator) != "1" { return }
    issuers: []string = {"https://accounts.google.com", "https://login.microsoftonline.com/9188040d-6c67-4c5b-b112-36a304b66dad/v2.0", "https://auth.spacetimedb.com/oidc", "https://demo.duendesoftware.com", "https://discord.com"}
    for issuer in issuers {
        metadata: ^Metadata = new(Metadata)
        keys: ^KeySet = new(KeySet)
        defer free(metadata)
        defer free(keys)
        found: bool = Discover(issuer, metadata)
        testing.expectf(t, found, "%s: discovery", issuer)
        if !found { continue }
        testing.expectf(t, metadata.authorization_endpoint != "" && metadata.token_endpoint != "", "%s: the endpoints", issuer)
        got_keys: bool = FetchKeys(metadata, keys)
        testing.expectf(t, got_keys && keys.count > 0, "%s: keys (%d)", issuer, keys.count)
        fmt.printfln("[oidc live] %s: issuer ok, %d keys (kinds: %v)", issuer, keys.count, keys.keys[0].kind)
    }
}

@(test)
test_a_real_token_is_verified :: proc(t: ^testing.T) {
    if os.get_env("OIDC_LIVE", context.temp_allocator) != "1" { return }
    metadata: ^Metadata = new(Metadata)
    keys: ^KeySet = new(KeySet)
    tokens: ^Tokens = new(Tokens)
    defer free(metadata)
    defer free(keys)
    defer free(tokens)
    issuer :: "https://demo.duendesoftware.com"
    testing.expect(t, Discover(issuer, metadata))
    testing.expect(t, FetchKeys(metadata, keys))
    testing.expectf(t, ClientCredentials(metadata, {client_id = "m2m", client_secret = "secret"}, "api", tokens), "the token: %s", tokens.error)
    scratch: [2048]u8
    claims, error := JwtVerify(tokens.access_token, keys, {issuer = issuer, audience = "api", allow_no_subject = true}, scratch[:])
    testing.expectf(t, error == .NONE, "the real token verifies: %s", VerifyErrorText(error))
    testing.expect_value(t, claims.issuer, issuer)
    // the same token with another audience or issuer is refused, and a changed byte breaks the signature
    _, error = JwtVerify(tokens.access_token, keys, {audience = "another-api", allow_no_subject = true}, scratch[:])
    testing.expect_value(t, error, VerifyError.AUDIENCE)
    _, error = JwtVerify(tokens.access_token, keys, {issuer = "https://accounts.google.com", allow_no_subject = true}, scratch[:])
    testing.expect_value(t, error, VerifyError.ISSUER)
    tampered: [4096]u8
    copy(tampered[:], tokens.access_token)
    last: int = len(tokens.access_token) - 5
    tampered[last] = 'A' if tampered[last] != 'A' else 'B'
    _, error = JwtVerify(string(tampered[:len(tokens.access_token)]), keys, {issuer = issuer, allow_no_subject = true}, scratch[:])
    testing.expect_value(t, error, VerifyError.SIGNATURE)
    // the keys of Google cannot verify a token of Duende
    google: ^KeySet = new(KeySet)
    defer free(google)
    google_metadata: ^Metadata = new(Metadata)
    defer free(google_metadata)
    if Discover("https://accounts.google.com", google_metadata) && FetchKeys(google_metadata, google) {
        _, error = JwtVerify(tokens.access_token, google, {allow_no_subject = true}, scratch[:])
        testing.expect(t, error == .SIGNATURE || error == .NO_KEY, "another provider's keys do not fit")
    }
}

// GitHub is not OpenID Connect: its device code endpoint answers a made up client id with a refusal in JSON, which proves that the address is right (a wrong one is a 404 page)
@(test)
test_github_device_endpoint_answers :: proc(t: ^testing.T) {
    if os.get_env("OIDC_LIVE", context.temp_allocator) != "1" { return }
    metadata: ^Metadata = new(Metadata)
    defer free(metadata)
    PresetMetadataGithub(metadata)
    buffer: [4096]u8
    response, ok := PostForm(metadata.device_authorization_endpoint, "client_id=odin-oidc-test&scope=read%3Auser", buffer[:])
    testing.expect(t, ok, "reached")
    testing.expectf(t, strings.contains(string(response.body), "error"), "a refusal for an unknown client: %d %s", response.status, string(response.body))
}
