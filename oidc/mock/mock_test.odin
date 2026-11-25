#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc_mock

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"
import "../../wait_for"
import ".."

// The client of oidc against the provider of this package, in one thread: the waits of a request step the provider and the login (that is what the person's browser would do).

@(private = "file")
Pair :: struct {
    provider: ^Provider,
    login: ^oidc.Login,
}

@(private = "file")
idle :: proc(user: rawptr) {
    pair: ^Pair = cast(^Pair)user
    Step(pair.provider)
    if pair.login != nil && pair.login.state == .WAITING && !pair.login.busy { oidc.LoginPoll(pair.login) }
}

// The three tests below set the global hook: one at a time
tests_lock: sync.Mutex

@(private = "file")
withProvider :: proc(options: Options, fault: Fault, pair: ^Pair) -> bool {
    pair.provider = new(Provider)
    if !Start(pair.provider, options) { return false }
    pair.provider.fault = fault
    pair.login = new(oidc.Login)
    oidc.HttpIdle, oidc.HttpIdleUser = idle, pair
    return true
}

@(private = "file")
without :: proc(pair: ^Pair) {
    oidc.HttpIdle, oidc.HttpIdleUser = nil, nil
    Stop(pair.provider)
    free(pair.provider)
    free(pair.login)
}

// What the browser does: open the login page, follow its redirect back to the program
@(private = "file")
browse :: proc(t: ^testing.T, login: ^oidc.Login) -> (status: int, page: string) {
    buffer: [4096]u8
    first, ok := oidc.Request(oidc.LoginUrl(login), "GET", nil, nil, buffer[:])
    testing.expect(t, ok && first.status == 302 && first.location != "", "the provider sends the browser back")
    if !ok || first.location == "" { return 0, "" }
    location: string = strings.clone(first.location, context.temp_allocator)
    callback: [4096]u8
    second, second_ok := oidc.Request(location, "GET", nil, nil, callback[:])
    testing.expect(t, second_ok, "the program answers the browser")
    return second.status, strings.clone(string(second.body), context.temp_allocator)
}

@(test)
test_a_login_with_es256 :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-1", email = "a@b.c"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    login: ^oidc.Login = pair.login
    testing.expect(t, oidc.LoginBegin(login, {issuer = Issuer(pair.provider), client_id = "game"}), oidc.LoginError(login))
    testing.expect(t, strings.contains(oidc.LoginUrl(login), "code_challenge_method=S256") && strings.contains(oidc.LoginUrl(login), "scope=openid%20profile%20email"), "PKCE and the scopes are asked")
    status, page := browse(t, login)
    testing.expect_value(t, login.state, oidc.LoginState.DONE)
    testing.expectf(t, login.state == .DONE, "the login: %s", oidc.LoginError(login))
    // what the person sees in the browser says what the program found out, after it found out
    testing.expect_value(t, status, 200)
    for part in ([]string{"Login verified", "Issuer: " , Issuer(pair.provider), "Subject: user-1"}) {
        testing.expectf(t, strings.contains(page, part), "the page has %q: %s", part, page)
    }
    testing.expect(t, !strings.contains(page, login.tokens.id_token), "the page never shows the token")
    testing.expect_value(t, login.claims.subject, "user-1")
    testing.expect_value(t, login.claims.issuer, Issuer(pair.provider))
    testing.expect(t, login.tokens.refresh_token != "" && login.tokens.access_token != "", "the other tokens came too")

    // the user info with the access token
    info_buffer: [1024]u8
    info, info_ok := oidc.Userinfo(&login.metadata, login.tokens.access_token, info_buffer[:])
    testing.expect(t, info_ok && strings.contains(info, "a@b.c"), "user info")

    // a refresh gives a new ID token that verifies too
    refreshed: ^oidc.Tokens = new(oidc.Tokens)
    defer free(refreshed)
    testing.expect(t, oidc.Refresh(&login.metadata, login.config, login.tokens.refresh_token, refreshed), refreshed.error)
    scratch: [1024]u8
    claims, error := oidc.JwtVerify(refreshed.id_token, &login.keys, {issuer = Issuer(pair.provider), audience = "game"}, scratch[:])
    testing.expect_value(t, error, oidc.VerifyError.NONE)
    testing.expect_value(t, claims.subject, "user-1")
    // the used refresh token is not good again
    again: ^oidc.Tokens = new(oidc.Tokens)
    defer free(again)
    testing.expect(t, oidc.Refresh(&login.metadata, login.config, "not-a-token", again) == false && again.error == "invalid_grant")
}

@(test)
test_a_login_with_rs256 :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .RS256, client_id = "game", subject = "user-2"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    login: ^oidc.Login = pair.login
    testing.expect(t, oidc.LoginBegin(login, {issuer = Issuer(pair.provider), client_id = "game"}), oidc.LoginError(login))
    browse(t, login)
    testing.expectf(t, login.state == .DONE, "the login: %s", oidc.LoginError(login))
    testing.expect_value(t, login.claims.subject, "user-2")
}

@(test)
test_a_provider_that_cheats_is_refused :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    for fault in ([]Fault{.BAD_SIGNATURE, .WRONG_AUDIENCE, .WRONG_ISSUER, .WRONG_NONCE, .EXPIRED, .HS256}) {
        pair: Pair
        if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-1"}, fault, &pair) { testing.fail_now(t, "the provider does not start") }
        login: ^oidc.Login = pair.login
        testing.expect(t, oidc.LoginBegin(login, {issuer = Issuer(pair.provider), client_id = "game"}), oidc.LoginError(login))
        status, page := browse(t, login)
        testing.expectf(t, login.state == .FAILED && strings.contains(oidc.LoginError(login), "not accepted"), "%v is refused: %v %s", fault, login.state, oidc.LoginError(login))
        // the browser is not told "signed in" for a login that the program refused
        testing.expectf(t, status == 400 && strings.contains(page, "Login failed") && strings.contains(page, "not accepted"), "%v: the page says it failed: %d %s", fault, status, page)
        testing.expectf(t, !strings.contains(page, "Login verified") && !strings.contains(page, "Signed in"), "%v: the page does not claim a login", fault)
        without(&pair)
    }
}

@(test)
test_the_redirect_is_checked :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-1"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    login: ^oidc.Login = pair.login
    testing.expect(t, oidc.LoginBegin(login, {issuer = Issuer(pair.provider), client_id = "game"}), oidc.LoginError(login))
    // a request with the wrong state (a page of another site that sends the person here) does not end the login
    buffer: [2048]u8
    forged, ok := oidc.Request(fmt.tprintf("http://127.0.0.1:%d/callback?code=evil&state=wrong", login.port), "GET", nil, nil, buffer[:])
    testing.expect(t, ok && forged.status == 400)
    testing.expect_value(t, login.state, oidc.LoginState.WAITING)
    // the page tells the person what is wrong, and the login remembers what the browser sent (the tool shows it)
    testing.expect(t, strings.contains(string(forged.body), "older attempt"), "the page explains the stale tab")
    testing.expect_value(t, login.rejected_count, 1)
    testing.expect_value(t, string(login.rejected[:login.rejected_length]), "code=<4 characters>&state=wrong")      // the one-time code is never kept
    // a path that is not the callback
    other, other_ok := oidc.Request(fmt.tprintf("http://127.0.0.1:%d/favicon.ico", login.port), "GET", nil, nil, buffer[:])
    testing.expect(t, other_ok && other.status == 404)
    testing.expect_value(t, login.state, oidc.LoginState.WAITING)
    // the provider says no
    refused, refused_ok := oidc.Request(fmt.tprintf("http://127.0.0.1:%d/callback?error=access_denied&state=x", login.port), "GET", nil, nil, buffer[:])
    _ = refused
    testing.expect(t, refused_ok)
    // (a state that is not ours is ignored even then: the login still waits)
    testing.expect_value(t, login.state, oidc.LoginState.WAITING)
    browse(t, login)
    testing.expect_value(t, login.state, oidc.LoginState.DONE)
}

@(test)
test_a_provider_that_says_no_ends_the_login :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-1"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    login: ^oidc.Login = pair.login
    testing.expect(t, oidc.LoginBegin(login, {issuer = Issuer(pair.provider), client_id = "game"}), oidc.LoginError(login))
    buffer: [2048]u8
    _, ok := oidc.Request(fmt.tprintf("http://127.0.0.1:%d/callback?error=access_denied&state=%s", login.port, string(login.state_value[:login.state_length])), "GET", nil, nil, buffer[:])
    testing.expect(t, ok)
    testing.expect_value(t, login.state, oidc.LoginState.FAILED)
    testing.expect(t, strings.contains(oidc.LoginError(login), "access_denied"))
}

@(test)
test_pkce_protects_the_code :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-1"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    metadata: ^oidc.Metadata = new(oidc.Metadata)
    defer free(metadata)
    testing.expect(t, oidc.Discover(Issuer(pair.provider), metadata))
    // a code that was stolen is no use without the verifier
    verifier_buffer, challenge_buffer: [64]u8
    verifier: string = oidc.PkceVerifier(verifier_buffer[:])
    challenge: string = oidc.PkceChallenge(verifier, challenge_buffer[:])
    buffer: [2048]u8
    authorize: string = fmt.tprintf("%s?response_type=code&client_id=game&redirect_uri=http%%3A%%2F%%2F127.0.0.1%%3A9%%2Fcb&state=s&nonce=n&code_challenge=%s&code_challenge_method=S256", metadata.authorization_endpoint, challenge)
    response, ok := oidc.Request(authorize, "GET", nil, nil, buffer[:])
    testing.expect(t, ok && response.status == 302)
    start: int = strings.index(response.location, "code=") + 5
    code: string = strings.clone(response.location[start:strings.index_byte(response.location[start:], '&') + start], context.temp_allocator)
    tokens: ^oidc.Tokens = new(oidc.Tokens)
    defer free(tokens)
    testing.expect(t, !oidc.ExchangeCode(metadata, {client_id = "game"}, code, "not-the-verifier", "http://127.0.0.1:9/cb", tokens))
    testing.expect_value(t, tokens.error, "invalid_grant")
    // and the code is used up even when the thief failed: the person has to sign in again
    testing.expect(t, !oidc.ExchangeCode(metadata, {client_id = "game"}, code, verifier, "http://127.0.0.1:9/cb", tokens))
}

@(test)
test_the_device_flow :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-3"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    metadata: ^oidc.Metadata = new(oidc.Metadata)
    defer free(metadata)
    testing.expect(t, oidc.Discover(Issuer(pair.provider), metadata))
    device: ^oidc.DeviceCode = new(oidc.DeviceCode)
    defer free(device)
    testing.expect(t, oidc.DeviceStart(metadata, {client_id = "game"}, device))
    testing.expect_value(t, device.user_code, "WDJB-MJHT")
    tokens: ^oidc.Tokens = new(oidc.Tokens)
    defer free(tokens)
    state: oidc.DevicePollState
    for deadline := wait_for.DeadlineStart(24); !wait_for.DeadlineExpired(&deadline); {
        state = oidc.DevicePoll(metadata, {client_id = "game"}, device, tokens)
        if state != .PENDING { break }
        time.sleep(20 * time.Millisecond)
    }
    testing.expect_value(t, state, oidc.DevicePollState.DONE)
    testing.expect(t, tokens.id_token != "")
}

// GitHub has no discovery document: the endpoints are written by hand (`PresetMetadataGithub`). The same has to work against a provider that is not discovered: the device flow and the user lookup
// with a `Metadata` that was filled in by hand, and no keys at all (the access token is not checked here, the provider is asked who it belongs to).
@(test)
test_a_provider_without_discovery_works_through_the_device_flow :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-4"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    base: string = Issuer(pair.provider)
    metadata: ^oidc.Metadata = new(oidc.Metadata)
    defer free(metadata)
    metadata.issuer = base
    metadata.device_authorization_endpoint = fmt.tprintf("%s/device", base)
    metadata.token_endpoint = fmt.tprintf("%s/token", base)
    metadata.userinfo_endpoint = fmt.tprintf("%s/userinfo", base)
    config: oidc.ClientConfig = oidc.PresetConfig(.GITHUB, "game")
    device: ^oidc.DeviceCode = new(oidc.DeviceCode)
    tokens: ^oidc.Tokens = new(oidc.Tokens)
    defer { free(device); free(tokens) }
    testing.expect(t, oidc.DeviceStart(metadata, config, device))
    testing.expect_value(t, device.user_code, "WDJB-MJHT")
    state: oidc.DevicePollState
    for deadline := wait_for.DeadlineStart(24); !wait_for.DeadlineExpired(&deadline); {
        state = oidc.DevicePoll(metadata, config, device, tokens)
        if state != .PENDING { break }
        time.sleep(20 * time.Millisecond)
    }
    testing.expect_value(t, state, oidc.DevicePollState.DONE)
    testing.expect(t, tokens.access_token != "")
    info: [2048]u8
    text, ok := oidc.Userinfo(metadata, tokens.access_token, info[:])
    testing.expect(t, ok)
    subject, found := oidc.JsonString(text, "sub")
    testing.expect(t, found)
    testing.expect_value(t, subject, "user-4")
    // a token that the provider did not make is not accepted by it
    _, forged := oidc.Userinfo(metadata, "not-a-token", info[:])
    testing.expect(t, !forged, "the lookup of an unknown token fails")
}

// Discord refuses a refresh without the client secret (`invalid_client`) although the login itself needs none: the client has to report it, and succeed with the secret
@(test)
test_a_refresh_that_needs_the_secret :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .RS256, client_id = "game", subject = "user-5", refresh_secret = "s3cret"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    config: oidc.ClientConfig = {issuer = Issuer(pair.provider), client_id = "game"}
    testing.expect(t, oidc.LoginBegin(pair.login, config), oidc.LoginError(pair.login))
    browse(t, pair.login)
    testing.expect_value(t, pair.login.state, oidc.LoginState.DONE)
    refresh: string = strings.clone(pair.login.tokens.refresh_token, context.temp_allocator)
    refreshed: ^oidc.Tokens = new(oidc.Tokens)
    defer free(refreshed)
    testing.expect(t, !oidc.Refresh(&pair.login.metadata, config, refresh, refreshed), "no secret: refused")
    testing.expect_value(t, refreshed.error, "invalid_client")
    config.client_secret = "wrong"
    testing.expect(t, !oidc.Refresh(&pair.login.metadata, config, refresh, refreshed), "a wrong secret: refused")
    config.client_secret = "s3cret"
    testing.expect(t, oidc.Refresh(&pair.login.metadata, config, refresh, refreshed), refreshed.error)
    testing.expect(t, refreshed.id_token != "")
}

// The client credentials grant (a program that is not a person): the access token is a JWT of the provider without `sub`, the audience is the scope, and it is checked like any other token
@(test)
test_the_client_credentials_grant :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    for algorithm in ([]Algorithm{.ES256, .RS256}) {
        pair: Pair
        if !withProvider({algorithm = algorithm, client_id = "server", subject = "unused", service_secret = "s3cret"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
        defer without(&pair)
        metadata: ^oidc.Metadata = new(oidc.Metadata)
        keys: ^oidc.KeySet = new(oidc.KeySet)
        tokens: ^oidc.Tokens = new(oidc.Tokens)
        defer { free(metadata); free(keys); free(tokens) }
        issuer: string = Issuer(pair.provider)
        testing.expect(t, oidc.Discover(issuer, metadata))
        testing.expect(t, oidc.FetchKeys(metadata, keys))

        testing.expectf(t, oidc.ClientCredentials(metadata, {client_id = "server", client_secret = "s3cret"}, "api", tokens), "the token: %s", tokens.error)
        testing.expect(t, tokens.access_token != "" && tokens.id_token == "" && tokens.refresh_token == "", "an access token and nothing else")
        scratch: [2048]u8
        claims, error := oidc.JwtVerify(tokens.access_token, keys, {issuer = issuer, audience = "api", allow_no_subject = true}, scratch[:])
        testing.expectf(t, error == .NONE, "the service token verifies: %s", oidc.VerifyErrorText(error))
        testing.expect_value(t, claims.subject, "")
        client_id, has_client := oidc.JsonString(claims.payload, "client_id")
        testing.expect(t, has_client)
        testing.expect_value(t, client_id, "server")
        // a token without `sub` is not a login unless it is allowed, another audience is refused, a changed byte breaks the signature
        _, error = oidc.JwtVerify(tokens.access_token, keys, {issuer = issuer, audience = "api"}, scratch[:])
        testing.expect_value(t, error, oidc.VerifyError.MALFORMED)
        _, error = oidc.JwtVerify(tokens.access_token, keys, {audience = "other-api", allow_no_subject = true}, scratch[:])
        testing.expect_value(t, error, oidc.VerifyError.AUDIENCE)
        changed: [2048]u8
        copy(changed[:], tokens.access_token)
        last: int = len(tokens.access_token) - 4
        changed[last] = 'A' if changed[last] != 'A' else 'B'
        _, error = oidc.JwtVerify(string(changed[:len(tokens.access_token)]), keys, {allow_no_subject = true}, scratch[:])
        testing.expect_value(t, error, oidc.VerifyError.SIGNATURE)

        // the secret is the proof: without it, with a wrong one, or for another client the provider says no
        testing.expect(t, !oidc.ClientCredentials(metadata, {client_id = "server"}, "api", tokens))
        testing.expect_value(t, tokens.error, "invalid_client")
        testing.expect(t, !oidc.ClientCredentials(metadata, {client_id = "server", client_secret = "wrong"}, "api", tokens))
        testing.expect(t, !oidc.ClientCredentials(metadata, {client_id = "someone-else", client_secret = "s3cret"}, "api", tokens))
    }
}

// Discord keeps the name out of the ID token: the page of the browser and `LoginDisplayName` find it in the user info; without it the page says so
@(test)
test_the_name_of_the_person_is_found_where_the_provider_keeps_it :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-8", userinfo_name = "Ada Lovelace"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    testing.expect(t, oidc.LoginBegin(pair.login, {issuer = Issuer(pair.provider), client_id = "game"}), oidc.LoginError(pair.login))
    status, page := browse(t, pair.login)
    testing.expect_value(t, status, 200)
    testing.expect(t, strings.contains(page, "Name: Ada Lovelace"), page)
    name, found := oidc.LoginDisplayName(pair.login)
    testing.expect(t, found)
    testing.expect_value(t, name, "Ada Lovelace")
    testing.expect(t, strings.contains(oidc.LoginUserinfo(pair.login), "user-8"))

    // no name anywhere: not found, and the page says so instead of inventing one
    other: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-9"}, .NONE, &other) { testing.fail_now(t, "the provider does not start") }
    defer without(&other)
    testing.expect(t, oidc.LoginBegin(other.login, {issuer = Issuer(other.provider), client_id = "game"}), oidc.LoginError(other.login))
    _, other_page := browse(t, other.login)
    testing.expect(t, strings.contains(other_page, "Name: (none in the token)"), other_page)
    _, other_found := oidc.LoginDisplayName(other.login)
    testing.expect(t, !other_found)
}

// Real providers answer with kilobytes of headers (Discord: about 2 KB with the CDN's): the user info must still be read, and the name found. (The first version of the login kept 2 KB for the whole answer and
// found no name at Discord.)
@(test)
test_the_user_info_is_read_when_the_answer_has_big_headers :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .RS256, client_id = "game", subject = "user-10", userinfo_name = "Grace Hopper", header_padding = 5000}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    testing.expect(t, oidc.LoginBegin(pair.login, {issuer = Issuer(pair.provider), client_id = "game"}), oidc.LoginError(pair.login))
    status, page := browse(t, pair.login)
    testing.expect_value(t, status, 200)
    testing.expect_value(t, pair.login.state, oidc.LoginState.DONE)       // the login itself does not depend on it
    name, found := oidc.LoginDisplayName(pair.login)
    testing.expect(t, found, "the name is found although the answer has 5 KB of headers")
    testing.expect_value(t, name, "Grace Hopper")
    testing.expect(t, strings.contains(page, "Name: Grace Hopper"), page)
}

// A client with a secret (SpacetimeAuth, Discord's refresh): the secret goes in HTTP Basic first and in the form when the provider refuses that, for the code exchange, the refresh and the client credentials.
// Found with a real SpacetimeAuth client: the secret in the form only was `invalid_client`.
@(test)
test_the_client_secret_is_sent_the_way_the_provider_wants :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    // a secret with characters that need encoding in both ways of sending it (the colon of Basic, `&` and `+` of a form)
    secret: string = "p@ss:w/rd+&%é d"
    cases := [?]struct { auth: ClientAuth, retries: int, used: oidc.ClientAuthUsed }{{.EITHER, 0, .BASIC}, {.BASIC_ONLY, 0, .BASIC}, {.POST_ONLY, 1, .FORM}, {.PUBLIC, 2, .WITHOUT_SECRET}}
    for item in cases {
        pair: Pair
        if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-11", client_secret = secret, client_auth = item.auth, service_secret = secret}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
        config: oidc.ClientConfig = {issuer = Issuer(pair.provider), client_id = "game", client_secret = secret}
        testing.expect(t, oidc.LoginBegin(pair.login, config), oidc.LoginError(pair.login))
        browse(t, pair.login)
        testing.expectf(t, pair.login.state == .DONE, "%v: the code is exchanged: %s", item.auth, oidc.LoginError(pair.login))
        testing.expectf(t, pair.provider.failed_authentications == item.retries, "%v: %d refused before it worked", item.auth, pair.provider.failed_authentications)
        testing.expect_value(t, pair.login.tokens.client_auth, item.used)

        refreshed: ^oidc.Tokens = new(oidc.Tokens)
        defer free(refreshed)
        refresh: string = strings.clone(pair.login.tokens.refresh_token, context.temp_allocator)
        testing.expectf(t, oidc.Refresh(&pair.login.metadata, config, refresh, refreshed), "%v: the refresh: %s", item.auth, refreshed.error)
        service: ^oidc.Tokens = new(oidc.Tokens)
        defer free(service)
        if item.auth != .PUBLIC {          // a public client has no client credentials grant (that is for a client with a secret)
            testing.expectf(t, oidc.ClientCredentials(&pair.login.metadata, config, "api", service), "%v: client credentials: %s", item.auth, service.error)
        }
        without(&pair)
    }

    // a wrong secret fails both ways and says so; no secret at all fails too
    pair: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-11", client_secret = "right"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    wrong: oidc.ClientConfig = {issuer = Issuer(pair.provider), client_id = "game", client_secret = "wrong"}
    testing.expect(t, oidc.LoginBegin(pair.login, wrong), oidc.LoginError(pair.login))
    browse(t, pair.login)
    testing.expect_value(t, pair.login.state, oidc.LoginState.FAILED)
    testing.expect(t, strings.contains(oidc.LoginError(pair.login), "invalid_client"), oidc.LoginError(pair.login))
    testing.expect_value(t, pair.provider.failed_authentications, 3)             // Basic, the form, then without a secret: none of it is right
    anonymous: oidc.ClientConfig = {issuer = Issuer(pair.provider), client_id = "game"}
    other: ^oidc.Login = new(oidc.Login)
    defer free(other)
    original: ^oidc.Login = pair.login
    testing.expect(t, oidc.LoginBegin(other, anonymous), oidc.LoginError(other))
    pair.login = other                                  // the idle hook polls the login of the pair
    browse(t, other)
    pair.login = original                               // `without` frees it
    testing.expect_value(t, other.state, oidc.LoginState.FAILED)
    testing.expect_value(t, pair.provider.failed_authentications, 4)             // one try: there is no secret to send another way
}

// A login of a public client (no secret) does not send any client authentication: nothing to retry
@(test)
test_a_public_client_sends_no_secret :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-12"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    testing.expect(t, oidc.LoginBegin(pair.login, {issuer = Issuer(pair.provider), client_id = "game"}), oidc.LoginError(pair.login))
    browse(t, pair.login)
    testing.expect_value(t, pair.login.state, oidc.LoginState.DONE)
    testing.expect_value(t, pair.provider.failed_authentications, 0)
}

// A login that is cancelled: the port is closed (a second login can use it), the state says so, and a later poll does not bring it back
@(test)
test_a_cancelled_login_closes_its_port :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-6"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    config: oidc.ClientConfig = {issuer = Issuer(pair.provider), client_id = "game", redirect_port = 48911}
    testing.expect(t, oidc.LoginBegin(pair.login, config), oidc.LoginError(pair.login))
    testing.expect_value(t, pair.login.state, oidc.LoginState.WAITING)
    // the port is taken while it waits
    other: ^oidc.Login = new(oidc.Login)
    defer free(other)
    testing.expect(t, !oidc.LoginBegin(other, config), "the same port cannot be used twice")
    oidc.LoginCancel(pair.login)
    testing.expect_value(t, pair.login.state, oidc.LoginState.CANCELLED)
    testing.expect_value(t, oidc.LoginPoll(pair.login), oidc.LoginState.CANCELLED)
    // and it is free again
    testing.expect(t, oidc.LoginBegin(other, config), oidc.LoginError(other))
    oidc.LoginCancel(other)
    // cancelling twice, or a login that never began, is harmless
    oidc.LoginCancel(other)
    idle: oidc.Login
    oidc.LoginCancel(&idle)
    testing.expect_value(t, idle.state, oidc.LoginState.IDLE)
}

// The address of the login goes to the opener as one argument
@(test)
test_the_login_address_is_given_to_the_opener :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-7"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    testing.expect(t, oidc.LoginBegin(pair.login, {issuer = Issuer(pair.provider), client_id = "game"}), oidc.LoginError(pair.login))
    defer oidc.LoginCancel(pair.login)
    @(static) last: string
    last = ""
    oidc.BrowserLauncher = proc(command: []string) -> bool {
        last = command[len(command) - 1]
        return true
    }
    defer oidc.BrowserLauncher = nil
    testing.expect(t, oidc.LoginOpenBrowser(pair.login))
    // the address of a login is long: on Windows it reaches the browser through a shortcut file (explorer cuts an address after 259 characters), elsewhere it is the argument itself
    when ODIN_OS == .Windows {
        testing.expect(t, strings.has_suffix(last, ".url"))
        data, error := os.read_entire_file(last, context.temp_allocator)
        testing.expect(t, error == nil)
        testing.expect(t, strings.contains(string(data), oidc.LoginUrl(pair.login)), "the shortcut holds the whole address")
        testing.expect(t, strings.contains(string(data), "code_challenge_method=S256"), "including its end")
        oidc.BrowserShortcutRemove(last)
    } else {
        testing.expect_value(t, last, oidc.LoginUrl(pair.login))
    }
}

// Revocation (RFC 7009) and the end session address: after `Revoke` the refresh token is refused, the user info is read into a struct, a provider without the endpoint says no
@(test)
test_revoking_a_refresh_token_and_the_end_session_address :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    pair: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-9", email = "a@b.c", userinfo_name = "Ada"}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    config: oidc.ClientConfig = {issuer = Issuer(pair.provider), client_id = "game"}
    testing.expect(t, oidc.LoginBegin(pair.login, config), oidc.LoginError(pair.login))
    browse(t, pair.login)
    testing.expect_value(t, pair.login.state, oidc.LoginState.DONE)
    metadata: ^oidc.Metadata = &pair.login.metadata
    testing.expect(t, metadata.revocation_endpoint != "")
    refresh: string = strings.clone(pair.login.tokens.refresh_token, context.temp_allocator)
    renewed: ^oidc.Tokens = new(oidc.Tokens)
    defer free(renewed)
    testing.expect(t, oidc.Refresh(metadata, config, refresh, renewed), renewed.error)
    testing.expect(t, oidc.Revoke(metadata, config, refresh, "refresh_token"))
    testing.expect_value(t, pair.provider.revocations, 1)
    testing.expect(t, !oidc.Refresh(metadata, config, refresh, renewed), "a revoked token is refused")
    testing.expect(t, oidc.Revoke(metadata, config, refresh, "refresh_token"), "revoking twice is no error")
    // the person is named from the user info into a struct
    info: [4096]u8
    text, got := oidc.Userinfo(metadata, pair.login.tokens.access_token, info[:])
    testing.expect(t, got)
    fields, parsed := oidc.UserinfoParse(text)
    testing.expect(t, parsed)
    testing.expect_value(t, fields.subject, "user-9")
    testing.expect_value(t, fields.name, "Ada")
    testing.expect_value(t, fields.email, "a@b.c")
    // the end session address carries the hint and the way back, encoded
    out: [1024]u8
    address: string = oidc.EndSessionUrl(metadata, "a.b.c", "http://127.0.0.1:1/back", out[:])
    testing.expect(t, strings.has_suffix(address, "/logout?id_token_hint=a.b.c&post_logout_redirect_uri=http%3A%2F%2F127.0.0.1%3A1%2Fback"), address)
    // no endpoint: nothing
    none: oidc.Metadata
    testing.expect(t, !oidc.Revoke(&none, config, refresh))
    testing.expect_value(t, oidc.EndSessionUrl(&none, "x", "", out[:]), "")
}

// A provider that leaves the nonce out (Discord with a client secret): refused unless the config says `nonce_optional`; a WRONG nonce is refused either way
@(test)
test_a_token_without_a_nonce_needs_nonce_optional :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    for optional in ([]bool{false, true}) {
        pair: Pair
        if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-3", omit_nonce = true}, .NONE, &pair) { testing.fail_now(t, "the provider does not start") }
        defer without(&pair)
        config: oidc.ClientConfig = {issuer = Issuer(pair.provider), client_id = "game", nonce_optional = optional}
        testing.expect(t, oidc.LoginBegin(pair.login, config), oidc.LoginError(pair.login))
        browse(t, pair.login)
        testing.expect_value(t, pair.login.state, oidc.LoginState.DONE if optional else oidc.LoginState.FAILED)
    }
    pair: Pair
    if !withProvider({algorithm = .ES256, client_id = "game", subject = "user-3"}, .WRONG_NONCE, &pair) { testing.fail_now(t, "the provider does not start") }
    defer without(&pair)
    config: oidc.ClientConfig = {issuer = Issuer(pair.provider), client_id = "game", nonce_optional = true}
    testing.expect(t, oidc.LoginBegin(pair.login, config), oidc.LoginError(pair.login))
    browse(t, pair.login)
    testing.expect_value(t, pair.login.state, oidc.LoginState.FAILED)
}
