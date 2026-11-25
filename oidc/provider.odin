#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

// Talking to an OpenID provider: its discovery document, the token endpoint (the code of a login, a refresh), the user info, and the device flow for a program that has no browser of its own to
// receive a redirect (a console, a TV). Strings of a result live in storage of the result (no allocation, nothing to free).

import "core:crypto"
import "core:crypto/hash"
import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:time"

PROVIDER_STORAGE :: 4096

// What the discovery document says (`{issuer}/.well-known/openid-configuration`)
Metadata :: struct {
    issuer: string,
    authorization_endpoint: string,
    token_endpoint: string,
    jwks_uri: string,
    userinfo_endpoint: string,
    device_authorization_endpoint: string,
    end_session_endpoint: string,
    revocation_endpoint: string,
    storage: [PROVIDER_STORAGE]u8,
    used: int,
}

@(private)
keep :: proc(storage: []u8, used: ^int, text: string) -> string {
    if used^ + len(text) > len(storage) { return "" }
    copy(storage[used^:], text)
    result: string = string(storage[used^:used^ + len(text)])
    used^ += len(text)
    return result
}

@(private)
jsonText :: proc(object: json.Object, key: string) -> string {
    text, _ := object[key].(json.String)
    return text
}

@(private)
parseObject :: proc(body: []u8, scratch: []u8) -> (object: json.Object, ok: bool) {
    arena: mem.Arena
    mem.arena_init(&arena, scratch)
    value, error := json.parse(body, json.DEFAULT_SPECIFICATION, true, mem.arena_allocator(&arena))
    if error != .None { return {}, false }
    object, ok = value.(json.Object)
    return
}

// Fetches and reads the discovery document of an issuer (`https://auth.example.com`, a path is kept: `https://auth.spacetimedb.com/oidc`). False when it cannot be fetched or has no
// authorization, token and keys endpoints, or names another issuer than the one asked.
Discover :: proc(issuer: string, metadata: ^Metadata) -> bool {
    metadata^ = {}
    url: string = fmt.tprintf("%s/.well-known/openid-configuration", strings.trim_right(issuer, "/"))
    buffer: [16384]u8
    response, ok := Request(url, "GET", nil, nil, buffer[:])
    if !ok || response.status != 200 { return false }
    scratch: [65536]u8
    object, parsed := parseObject(response.body, scratch[:])
    if !parsed { return false }
    metadata.issuer = keep(metadata.storage[:], &metadata.used, jsonText(object, "issuer"))
    metadata.authorization_endpoint = keep(metadata.storage[:], &metadata.used, jsonText(object, "authorization_endpoint"))
    metadata.token_endpoint = keep(metadata.storage[:], &metadata.used, jsonText(object, "token_endpoint"))
    metadata.jwks_uri = keep(metadata.storage[:], &metadata.used, jsonText(object, "jwks_uri"))
    metadata.userinfo_endpoint = keep(metadata.storage[:], &metadata.used, jsonText(object, "userinfo_endpoint"))
    metadata.device_authorization_endpoint = keep(metadata.storage[:], &metadata.used, jsonText(object, "device_authorization_endpoint"))
    metadata.end_session_endpoint = keep(metadata.storage[:], &metadata.used, jsonText(object, "end_session_endpoint"))
    metadata.revocation_endpoint = keep(metadata.storage[:], &metadata.used, jsonText(object, "revocation_endpoint"))
    // the issuer of the document has to be the one that was asked: a provider cannot speak for another one
    if strings.trim_right(metadata.issuer, "/") != strings.trim_right(issuer, "/") { return false }
    return metadata.token_endpoint != "" && metadata.jwks_uri != ""
}

// The keys of the provider
FetchKeys :: proc(metadata: ^Metadata, keys: ^KeySet) -> bool {
    buffer: [65536]u8
    response, ok := Request(metadata.jwks_uri, "GET", nil, nil, buffer[:])
    return ok && response.status == 200 && JwksParse(string(response.body), keys)
}

ClientConfig :: struct {
    issuer: string,
    client_id: string,
    client_secret: string,          // "" for a public client (a game on a player's computer cannot keep a secret: use PKCE and no secret)
    scopes: string,                 // "": "openid profile email"
    redirect_port: int,             // loopback login: the port of the redirect (0: any free one; some providers want a registered one)
    oauth_only: bool,               // OAuth 2.0 without OpenID Connect (GitHub): the browser flow gives an access token and no ID token; the person is named by the user info
    extra: string,                  // more query parameters for the authorization request, already encoded (`audience=...&prompt=login`)
}

SCOPES_DEFAULT :: "openid profile email"

TOKEN_STORAGE :: 8192

// How the client proved itself at the token endpoint
ClientAuthUsed :: enum u8 {
    NONE,                   // no secret was configured
    BASIC,                  // the secret in the Authorization header
    FORM,                   // the secret in the form
    WITHOUT_SECRET,         // the provider refused the secret both ways and accepted the request without it: the client is a public one and the secret that was configured is not needed
}

// What a login gives
Tokens :: struct {
    client_auth: ClientAuthUsed,
    id_token: string,
    access_token: string,
    refresh_token: string,
    token_type: string,
    expires_in: i64,                // seconds of the access token
    storage: [TOKEN_STORAGE]u8,
    used: int,
    error: string,                  // the provider's `error` or the reason it failed here
    error_description: string,
}

@(private)
readTokens :: proc(response: Response, tokens: ^Tokens) -> bool {
    scratch: [32768]u8
    object, parsed := parseObject(response.body, scratch[:])
    tokens^ = {}
    if !parsed {
        tokens.error = "the token endpoint did not answer with JSON"
        return false
    }
    if error_text := jsonText(object, "error"); error_text != "" {
        tokens.error = keep(tokens.storage[:], &tokens.used, error_text)
        tokens.error_description = keep(tokens.storage[:], &tokens.used, jsonText(object, "error_description"))
        return false
    }
    tokens.id_token = keep(tokens.storage[:], &tokens.used, jsonText(object, "id_token"))
    tokens.access_token = keep(tokens.storage[:], &tokens.used, jsonText(object, "access_token"))
    tokens.refresh_token = keep(tokens.storage[:], &tokens.used, jsonText(object, "refresh_token"))
    tokens.token_type = keep(tokens.storage[:], &tokens.used, jsonText(object, "token_type"))
    #partial switch expires in object["expires_in"] {
    case json.Integer: tokens.expires_in = i64(expires)
    case json.Float: tokens.expires_in = i64(expires)
    }
    return response.status == 200 && (tokens.id_token != "" || tokens.access_token != "")
}

@(private)
clientAuthorization :: proc(config: ClientConfig, form: ^strings.Builder) -> string {
    FormField(form, "client_id", config.client_id)
    return ""
}

// The code of a login for tokens (RFC 6749 section 4.1.3, with the PKCE verifier of RFC 7636)
// A request to the token endpoint, with the client authentication when there is a secret. RFC 6749 asks every provider to take HTTP Basic (`client_id:client_secret`, each percent encoded, then base64), many
// also take the secret in the form; a client is registered for one of the two (SpacetimeAuth: `invalid_client` for the form when the client wants Basic). So Basic goes first and, when the provider says
// `invalid_client` (or 401), the secret is sent in the form. A PUBLIC client (SpacetimeAuth's `none`) is refused when it sends a secret at all: the last try is the request without one. `form` has no secret in
// it; the answer is in `buffer`; `used` says which way worked (or the last one that was tried).
@(private)
tokenRequest :: proc(metadata: ^Metadata, config: ClientConfig, form: string, buffer: []u8, endpoint: string = "") -> (response: Response, ok: bool, used: ClientAuthUsed) {
    url: string = endpoint if endpoint != "" else metadata.token_endpoint
    if config.client_secret == "" {
        response, ok = PostForm(url, form, buffer)
        return response, ok, .NONE
    }
    credentials: strings.Builder
    strings.builder_init(&credentials, context.temp_allocator)
    UrlEncode(config.client_id, &credentials)
    strings.write_byte(&credentials, ':')
    UrlEncode(config.client_secret, &credentials)
    encoded, _ := base64.encode(transmute([]u8)strings.to_string(credentials), allocator = context.temp_allocator)
    response, ok = PostForm(url, form, buffer, strings.concatenate({"Basic ", encoded}, context.temp_allocator))
    if !ok || !clientRefused(response) { return response, ok, .BASIC }
    in_form: strings.Builder
    strings.builder_init(&in_form, context.temp_allocator)
    strings.write_string(&in_form, form)
    FormField(&in_form, "client_secret", config.client_secret)
    response, ok = PostForm(url, strings.to_string(in_form), buffer)
    if !ok || !clientRefused(response) { return response, ok, .FORM }
    response, ok = PostForm(url, form, buffer)
    return response, ok, .WITHOUT_SECRET
}

@(private)
clientRefused :: proc(response: Response) -> bool {
    return response.status == 401 || strings.contains(string(response.body), "invalid_client")
}

ExchangeCode :: proc(metadata: ^Metadata, config: ClientConfig, code: string, verifier: string, redirect_uri: string, tokens: ^Tokens) -> bool {
    form: strings.Builder
    strings.builder_init(&form, context.temp_allocator)
    FormField(&form, "grant_type", "authorization_code")
    FormField(&form, "code", code)
    FormField(&form, "redirect_uri", redirect_uri)
    FormField(&form, "client_id", config.client_id)
    FormField(&form, "code_verifier", verifier)
    buffer: [16384]u8
    response, ok, used := tokenRequest(metadata, config, strings.to_string(form), buffer[:])
    if !ok {
        tokens^ = {}
        tokens.error = "the token endpoint could not be reached"
        return false
    }
    result: bool = readTokens(response, tokens)
    tokens.client_auth = used
    return result
}

// The client credentials grant (RFC 6749 section 4.4): a program that is not a person (a dedicated server, a service) gets an access token for itself with its client id and secret. The access
// token of most providers is a JWT that `JwtVerify` can check (audience: the API it is for).
ClientCredentials :: proc(metadata: ^Metadata, config: ClientConfig, scope: string, tokens: ^Tokens) -> bool {
    form: strings.Builder
    strings.builder_init(&form, context.temp_allocator)
    FormField(&form, "grant_type", "client_credentials")
    FormField(&form, "client_id", config.client_id)
    if scope != "" { FormField(&form, "scope", scope) }
    buffer: [16384]u8
    response, ok, used := tokenRequest(metadata, config, strings.to_string(form), buffer[:])
    if !ok {
        tokens^ = {}
        tokens.error = "the token endpoint could not be reached"
        return false
    }
    result: bool = readTokens(response, tokens)
    tokens.client_auth = used
    return result
}

// A new access token (and usually a new ID token) from the refresh token, without the person
Refresh :: proc(metadata: ^Metadata, config: ClientConfig, refresh_token: string, tokens: ^Tokens) -> bool {
    form: strings.Builder
    strings.builder_init(&form, context.temp_allocator)
    FormField(&form, "grant_type", "refresh_token")
    FormField(&form, "refresh_token", refresh_token)
    FormField(&form, "client_id", config.client_id)
    buffer: [16384]u8
    response, ok, used := tokenRequest(metadata, config, strings.to_string(form), buffer[:])
    if !ok {
        tokens^ = {}
        tokens.error = "the token endpoint could not be reached"
        return false
    }
    ok = readTokens(response, tokens)
    tokens.client_auth = used
    if ok && tokens.refresh_token == "" { tokens.refresh_token = keep(tokens.storage[:], &tokens.used, refresh_token) }   // the provider keeps the old one
    return ok
}

// The user info (`sub` and what the scopes allow: email, name ...) as the JSON of the answer. `out` holds the whole answer, headers included (a CDN's are kilobytes: 16 KB is safe); the result is a
// slice of it, and it is empty (not ok) when the answer does not fit.
Userinfo :: proc(metadata: ^Metadata, access_token: string, out: []u8) -> (json_text: string, ok: bool) {
    if metadata.userinfo_endpoint == "" { return "", false }
    headers: [1]Header = {{"Authorization", fmt.tprintf("Bearer %s", access_token)}}
    response, requested := Request(metadata.userinfo_endpoint, "GET", headers[:], nil, out)
    if !requested || response.status != 200 { return "", false }
    return string(response.body), true
}

// Fields of the user info that programs use, read without a copy: the strings point into the JSON text that was given. A field that is not there is "".
UserinfoFields :: struct {
    subject: string,
    name: string,
    preferred_username: string,       // Discord names the person here
    email: string,
    picture: string,
    email_verified: bool,
}

UserinfoParse :: proc(json_text: string) -> (fields: UserinfoFields, ok: bool) {
    fields.subject, ok = JsonString(json_text, "sub")
    if !ok {
        // GitHub has no `sub`: `id` is the number that names the person
        if id, has_id := JsonInt(json_text, "id"); has_id {
            fields.subject, ok = fmt.tprintf("%d", id), true
        }
    }
    fields.name, _ = JsonString(json_text, "name")
    fields.preferred_username, _ = JsonString(json_text, "preferred_username")
    if fields.preferred_username == "" { fields.preferred_username, _ = JsonString(json_text, "login") }
    fields.email, _ = JsonString(json_text, "email")
    fields.picture, _ = JsonString(json_text, "picture")
    if raw, has := JsonValue(json_text, "email_verified"); has { fields.email_verified = raw == "true" }
    return fields, ok
}

// ---- ending a login: token revocation (RFC 7009) and the end session address (OpenID RP-Initiated Logout) ------------------------------------------------------------------

// Tells the provider that a token is not wanted any more (a refresh token: the sign in cannot be renewed from any copy of it; an access token). `hint` is "refresh_token" or "access_token" or "".
// True when the provider answered 2xx (it does for a token it does not know too, by the RFC). False when the provider has no revocation endpoint (the metadata holds none: Google and Discord have one,
// GitHub's is a different API) or could not be reached: forgetting the token locally is still right, but a copy of it elsewhere stays good until it expires.
Revoke :: proc(metadata: ^Metadata, config: ClientConfig, token: string, hint: string = "") -> bool {
    if metadata.revocation_endpoint == "" || token == "" { return false }
    form: strings.Builder
    strings.builder_init(&form, context.temp_allocator)
    FormField(&form, "token", token)
    if hint != "" { FormField(&form, "token_type_hint", hint) }
    FormField(&form, "client_id", config.client_id)
    buffer: [8192]u8
    response, ok, _ := tokenRequest(metadata, config, strings.to_string(form), buffer[:], metadata.revocation_endpoint)
    return ok && response.status >= 200 && response.status < 300
}

// The address where the person ends the session at the provider (the browser has to open it): `end_session_endpoint` with the ID token as a hint, and where to go back to (it has to be registered
// at the provider; "" sends none). The result is in `out`; "" when the provider has no such endpoint or `out` is too small.
EndSessionUrl :: proc(metadata: ^Metadata, id_token_hint: string, return_to: string, out: []u8) -> string {
    if metadata.end_session_endpoint == "" { return "" }
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    strings.write_string(&builder, metadata.end_session_endpoint)
    strings.write_byte(&builder, '&' if strings.contains(metadata.end_session_endpoint, "?") else '?')
    query: strings.Builder
    strings.builder_init(&query, context.temp_allocator)
    if id_token_hint != "" { FormField(&query, "id_token_hint", id_token_hint) }
    if return_to != "" { FormField(&query, "post_logout_redirect_uri", return_to) }
    text: string = strings.concatenate({strings.to_string(builder), strings.to_string(query)}, context.temp_allocator)
    if len(text) > len(out) { return "" }
    return string(out[:copy(out, text)])
}

// ---- the device flow (RFC 8628) -------------------------------------------------------------------------------------------------------------------------------------------

DeviceCode :: struct {
    device_code: string,
    user_code: string,              // what the person types
    verification_uri: string,       // where
    verification_uri_complete: string,
    expires_in: i64,
    interval: i64,                  // seconds between polls
    storage: [1024]u8,
    used: int,
    next_poll: time.Tick,
}

DevicePollState :: enum u8 {
    PENDING,                        // the person has not finished: ask again after `interval`
    DONE,
    DENIED,
    EXPIRED,
    FAILED,
}

// Asks the provider for a code to show: the person goes to `verification_uri` (any device) and types `user_code`
DeviceStart :: proc(metadata: ^Metadata, config: ClientConfig, device: ^DeviceCode) -> bool {
    device^ = {}
    if metadata.device_authorization_endpoint == "" { return false }
    form: strings.Builder
    strings.builder_init(&form, context.temp_allocator)
    FormField(&form, "client_id", config.client_id)
    FormField(&form, "scope", config.scopes if config.scopes != "" else SCOPES_DEFAULT)
    buffer: [8192]u8
    response, ok := PostForm(metadata.device_authorization_endpoint, strings.to_string(form), buffer[:])
    if !ok || response.status != 200 { return false }
    scratch: [16384]u8
    object, parsed := parseObject(response.body, scratch[:])
    if !parsed { return false }
    device.device_code = keep(device.storage[:], &device.used, jsonText(object, "device_code"))
    device.user_code = keep(device.storage[:], &device.used, jsonText(object, "user_code"))
    device.verification_uri = keep(device.storage[:], &device.used, jsonText(object, "verification_uri"))
    device.verification_uri_complete = keep(device.storage[:], &device.used, jsonText(object, "verification_uri_complete"))
    device.interval = 5
    #partial switch value in object["interval"] {
    case json.Integer: device.interval = i64(value)
    }
    #partial switch value in object["expires_in"] {
    case json.Integer: device.expires_in = i64(value)
    }
    device.next_poll = time.tick_now()
    return device.device_code != "" && device.user_code != ""
}

// The next poll is `interval` seconds away and a second more: a provider counts from when the request arrives, and a poll that is a hair early is slow_down
@(private)
deviceSchedule :: proc(device: ^DeviceCode) {
    device.next_poll = time.tick_add(time.tick_now(), time.Duration(device.interval + 1) * time.Second)
}

// Asks whether the person has finished (no more often than `interval`: a call before that returns PENDING without a request)
DevicePoll :: proc(metadata: ^Metadata, config: ClientConfig, device: ^DeviceCode, tokens: ^Tokens) -> DevicePollState {
    if time.tick_since(device.next_poll) < 0 { return .PENDING }
    deviceSchedule(device)
    form: strings.Builder
    strings.builder_init(&form, context.temp_allocator)
    FormField(&form, "grant_type", "urn:ietf:params:oauth:grant-type:device_code")
    FormField(&form, "device_code", device.device_code)
    FormField(&form, "client_id", config.client_id)
    buffer: [16384]u8
    response, ok := PostForm(metadata.token_endpoint, strings.to_string(form), buffer[:])
    if !ok { return .FAILED }
    if readTokens(response, tokens) { return .DONE }
    switch tokens.error {
    case "authorization_pending": return .PENDING
    case "slow_down":
        // the provider wants a longer wait: five more seconds, counted from now (GitHub found live: keeping the old schedule polled too early again, every answer was slow_down and the approval was never seen)
        device.interval += 5
        deviceSchedule(device)
        return .PENDING
    case "access_denied": return .DENIED
    case "expired_token": return .EXPIRED
    }
    return .FAILED
}

// ---- PKCE and the random values of a request ----------------------------------------------------------------------------------------------------------------------------

// `bytes` random bytes as base64url (a state, a nonce): 16 bytes are 22 letters
RandomText :: proc(bytes: int, out: []u8) -> string {
    random: [64]u8
    count: int = min(bytes, len(random))
    crypto.rand_bytes(random[:count])
    return Base64UrlEncode(random[:count], out)
}

// The code verifier of PKCE (RFC 7636): 43 letters of 32 random bytes
PkceVerifier :: proc(out: []u8) -> string {
    return RandomText(32, out)
}

// base64url(sha256(verifier)): what is sent in the authorization request
PkceChallenge :: proc(verifier: string, out: []u8) -> string {
    digest: [32]u8
    hash.hash_bytes_to_buffer(.SHA256, transmute([]u8)verifier, digest[:])
    return Base64UrlEncode(digest[:], out)
}
