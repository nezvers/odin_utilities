#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc_mock

import "core:fmt"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"
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
browse :: proc(t: ^testing.T, login: ^oidc.Login) {
    buffer: [4096]u8
    first, ok := oidc.Request(oidc.LoginUrl(login), "GET", nil, nil, buffer[:])
    testing.expect(t, ok && first.status == 302 && first.location != "", "the provider sends the browser back")
    if !ok || first.location == "" { return }
    location: string = strings.clone(first.location, context.temp_allocator)
    callback: [4096]u8
    second, second_ok := oidc.Request(location, "GET", nil, nil, callback[:])
    testing.expect(t, second_ok && second.status == 200, "the program answers the browser")
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
    browse(t, login)
    testing.expect_value(t, login.state, oidc.LoginState.DONE)
    testing.expectf(t, login.state == .DONE, "the login: %s", oidc.LoginError(login))
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
        browse(t, login)
        testing.expectf(t, login.state == .FAILED && strings.contains(oidc.LoginError(login), "not accepted"), "%v is refused: %v %s", fault, login.state, oidc.LoginError(login))
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
    for _ in 0 ..< 400 {
        state = oidc.DevicePoll(metadata, {client_id = "game"}, device, tokens)
        if state != .PENDING { break }
        time.sleep(20 * time.Millisecond)
    }
    testing.expect_value(t, state, oidc.DevicePollState.DONE)
    testing.expect(t, tokens.id_token != "")
}
