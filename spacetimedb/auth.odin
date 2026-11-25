package spacetimedb

// Signing in with an OpenID Connect provider (SpacetimeAuth, Auth0, Keycloak, Google through them, a provider of your own): the library `odin_utilities/oidc` does the login (a browser, PKCE, the
// keys of the provider checked); this file hands its ID token to the connection. SpacetimeDB takes the ID token as the token of the client, fetches the provider's keys itself, and makes the identity
// from the issuer and the subject: the same person is the same identity on every device and every database that trusts the provider.
//
//     login: ^oidc.Login = new(oidc.Login)
//     oidc.LoginBegin(login, AuthSpacetimeAuth("my-client-id")); oidc.LoginOpenBrowser(login)
//     for oidc.LoginPoll(login) == .WAITING { ... a frame ... }
//     session: AuthSession = AuthSessionFrom(login)
//     ConnectionOpen(&connection, {endpoint = ..., database = ..., token = AuthToken(&session), refresh = AuthRefresh, refresh_user = &session}, ...)
//
// `refresh` makes a reconnect use a fresh token: the ID token is short lived, the refresh token (when the provider gave one) gets a new one without the person. A module decides which providers
// it trusts: module.RequireClaims (spacetimedb/module/jwt.odin).

import "../oidc"

AUTH_SPACETIMEAUTH :: "https://auth.spacetimedb.com/oidc"

// The configuration of a client of SpacetimeAuth (a project of its own on spacetimedb.com: its client id; the redirect `http://127.0.0.1:<port>/callback` has to be one of the redirect URIs of
// that client, so give `redirect_port` a fixed port and register it)
AuthSpacetimeAuth :: proc(client_id: string, redirect_port: int = 0) -> oidc.ClientConfig {
    return {issuer = AUTH_SPACETIMEAUTH, client_id = client_id, redirect_port = redirect_port}
}

// What a connection needs of a login, kept between the first connection and the next ones
AuthSession :: struct {
    metadata: oidc.Metadata,
    config: oidc.ClientConfig,
    tokens: oidc.Tokens,
    claims_scratch: [4096]u8,
    expires: i64,               // when the ID token stops being good (seconds since the Unix epoch)
    error: string,
}

// A session from a login that is DONE (the tokens and the provider's document are copied)
AuthSessionFrom :: proc(session: ^AuthSession, login: ^oidc.Login) -> bool {
    if login.state != .DONE { return false }
    session.metadata, session.config, session.tokens = login.metadata, login.config, login.tokens
    // a copy of a struct that keeps its strings in its own storage still points into the original: the strings are made again over the copy
    rebaseMetadata(&session.metadata, uintptr(raw_data(login.metadata.storage[:])))
    rebaseTokens(&session.tokens, uintptr(raw_data(login.tokens.storage[:])))
    claims, ok := oidc.JwtClaimsRead(session.tokens.id_token, session.claims_scratch[:])
    session.expires = claims.expires
    return ok
}

// A session from a refresh token that was kept from an earlier sign in (`oidc.StoreRead`): the provider is discovered, the token is renewed, and the new ID token is verified like one of a login (signature,
// issuer, audience, expiry; there is no nonce, nobody was redirected). The refresh token may be replaced by the provider: keep `session.tokens.refresh_token` (`oidc.StoreWrite`). False, and
// `session.error`, when the provider cannot be reached, refuses the token (revoked, expired: the person has to sign in again) or sends no ID token (ask `offline_access` and `openid`).
AUTH_UNREACHABLE :: "the provider cannot be reached"          // the only error that is no answer of the provider: the stored sign in may still be good

AuthSessionFromRefresh :: proc(session: ^AuthSession, config: oidc.ClientConfig, refresh_token: string) -> bool {
    session^ = {}
    session.config = config
    if !oidc.Discover(config.issuer, &session.metadata) {
        session.error = AUTH_UNREACHABLE
        return false
    }
    if !oidc.Refresh(&session.metadata, config, refresh_token, &session.tokens) {
        session.error = "the provider refused the stored sign in"
        return false
    }
    if session.tokens.id_token == "" {
        session.error = "the provider sent no ID token"
        return false
    }
    keys: ^oidc.KeySet = new(oidc.KeySet)
    defer free(keys)
    if !oidc.FetchKeys(&session.metadata, keys) {
        session.error = "the keys of the provider could not be fetched"
        return false
    }
    claims, error := oidc.JwtVerify(session.tokens.id_token, keys, {issuer = session.metadata.issuer, audience = config.client_id}, session.claims_scratch[:])
    if error != .NONE {
        session.error = oidc.VerifyErrorText(error)
        return false
    }
    session.expires = claims.expires
    return true
}

@(private)
rebased :: proc(storage: []u8, old_start: uintptr, text: string) -> string {
    if len(text) == 0 { return "" }
    start: int = int(uintptr(raw_data(text)) - old_start)
    return string(storage[start:start + len(text)])
}

@(private)
rebaseMetadata :: proc(metadata: ^oidc.Metadata, old_start: uintptr) {
    metadata.issuer = rebased(metadata.storage[:], old_start, metadata.issuer)
    metadata.authorization_endpoint = rebased(metadata.storage[:], old_start, metadata.authorization_endpoint)
    metadata.token_endpoint = rebased(metadata.storage[:], old_start, metadata.token_endpoint)
    metadata.jwks_uri = rebased(metadata.storage[:], old_start, metadata.jwks_uri)
    metadata.userinfo_endpoint = rebased(metadata.storage[:], old_start, metadata.userinfo_endpoint)
    metadata.device_authorization_endpoint = rebased(metadata.storage[:], old_start, metadata.device_authorization_endpoint)
    metadata.end_session_endpoint = rebased(metadata.storage[:], old_start, metadata.end_session_endpoint)
    metadata.revocation_endpoint = rebased(metadata.storage[:], old_start, metadata.revocation_endpoint)
}

@(private)
rebaseTokens :: proc(tokens: ^oidc.Tokens, old_start: uintptr) {
    tokens.id_token = rebased(tokens.storage[:], old_start, tokens.id_token)
    tokens.access_token = rebased(tokens.storage[:], old_start, tokens.access_token)
    tokens.refresh_token = rebased(tokens.storage[:], old_start, tokens.refresh_token)
    tokens.token_type = rebased(tokens.storage[:], old_start, tokens.token_type)
    tokens.error, tokens.error_description = "", ""
}

// The token for the connection: the ID token
AuthToken :: proc(session: ^AuthSession) -> string {
    return session.tokens.id_token
}

// For `ConnectionConfig.refresh`: the ID token, renewed with the refresh token when it is about to expire (or has). A provider that cannot be reached leaves the old one in use: the server says
// when it is no longer good.
AuthRefresh :: proc(user: rawptr) -> string {
    session: ^AuthSession = cast(^AuthSession)user
    if session.tokens.refresh_token != "" && oidc.NowUnix() + 60 >= session.expires {
        renewed: ^oidc.Tokens = new(oidc.Tokens)
        defer free(renewed)
        if oidc.Refresh(&session.metadata, session.config, session.tokens.refresh_token, renewed) && renewed.id_token != "" {
            session.tokens = renewed^
            rebaseTokens(&session.tokens, uintptr(raw_data(renewed.storage[:])))
            claims, ok := oidc.JwtClaimsRead(session.tokens.id_token, session.claims_scratch[:])
            if ok { session.expires = claims.expires }
        } else {
            session.error = "the login could not be renewed"
        }
    }
    return session.tokens.id_token
}
