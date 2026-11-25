#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc_mock

// An OpenID provider of our own, small enough to run inside of a test and stepped by hand (no thread): the discovery document, the keys, the authorization endpoint (it approves at once and sends
// the browser back with a code), the token endpoint (authorization code with PKCE, refresh token, device code), the user info. Tokens are signed with ES256 or RS256, like the ones of a real
// provider, so what is tested is what a provider does: the client of `odin_utilities/oidc`, and a SpacetimeDB server that is asked to trust the issuer (it fetches the discovery document and the keys).
//
//     provider: ^Provider = new(Provider)
//     Start(provider, {client_id = "game", subject = "user-1"})          // listens on 127.0.0.1:<port>; the issuer is provider.issuer
//     oidc.HttpIdle, oidc.HttpIdleUser = Idle, provider                   // the requests of the client step the provider while they wait
//
// `fault` makes it misbehave on purpose (a wrong signature, a wrong audience ...) to see that the client refuses it.

import "core:crypto/ecdsa"
import "core:crypto/hash"
import "core:crypto/rsa"
import "core:encoding/base64"
import "core:fmt"
import "core:net"
import "core:strings"
import "core:time"
import ".."

Algorithm :: enum u8 {
    ES256,
    RS256,
}

Fault :: enum u8 {
    NONE,
    BAD_SIGNATURE,          // the ID token is signed with a key that is not in the JWKS
    WRONG_AUDIENCE,
    WRONG_ISSUER,
    WRONG_NONCE,
    EXPIRED,
    HS256,                  // an algorithm that must never be accepted
}

// How the client may present its secret at the token endpoint (a client is registered for one of the two at most providers)
ClientAuth :: enum u8 {
    EITHER,                 // HTTP Basic or the form
    BASIC_ONLY,             // SpacetimeAuth for a client registered with client_secret_basic
    POST_ONLY,              // client_secret_post
    PUBLIC,                 // a public client (SpacetimeAuth `none`): the request must carry NO secret, one that does is `invalid_client`
}

Options :: struct {
    client_secret: string,  // not "": the token endpoint wants this secret (code exchange, refresh, client credentials), `invalid_client` without it
    client_auth: ClientAuth,
    algorithm: Algorithm,
    client_id: string,
    subject: string,
    email: string,
    lifetime: i64,          // seconds of the ID token (0: 600)
    port: int,              // 0: any
    refresh_secret: string, // not "": a refresh needs this client_secret, as at Discord (`invalid_client` without it)
    header_padding: int,    // the user info answer has a header of this many bytes (real providers send kilobytes of headers)
    rotate_refresh: bool,   // a refresh token can be used once: the answer has a new one (providers that rotate), the old one is `invalid_grant`
    userinfo_name: string,  // not "": the user info carries this `name` (the ID token never does, as at Discord)
    omit_nonce: bool,       // the ID token has no nonce claim (Discord with a client secret)
    service_secret: string, // not "": the client credentials grant works with this client_secret (a service token without `sub`, audience = the scope), otherwise it is `invalid_client`
}

MAX_CODES :: 8

Code :: struct {
    value: [32]u8,
    value_length: int,
    challenge: [64]u8,
    challenge_length: int,
    nonce: [64]u8,
    nonce_length: int,
    used: bool,
    kind: u8,               // 1 authorization code, 2 refresh token, 3 device code
    polls: int,             // a device code is pending for a few polls
}

Provider :: struct {
    listener: net.TCP_Socket,
    port: int,
    issuer: [48]u8,
    issuer_length: int,
    options: Options,
    es_key: ecdsa.Private_Key,
    rs_key: rsa.Private_Key,
    other_key: ecdsa.Private_Key,       // the key of a wrong signature
    codes: [MAX_CODES]Code,
    fault: Fault,
    failed_authentications: int,        // token requests refused for their client authentication (a test sees the retry)
    requests: int,                      // how many requests were answered (a test can see that the provider was asked)
    authorize_requests: int,
    revocations: int,                   // tokens the client asked to revoke (and that were known)
    nonce_of_last_code: [64]u8,
}

Issuer :: proc(provider: ^Provider) -> string {
    return string(provider.issuer[:provider.issuer_length])
}

Start :: proc(provider: ^Provider, options: Options) -> bool {
    provider^ = {options = options}
    if provider.options.lifetime == 0 { provider.options.lifetime = 600 }
    listener, listen_error := net.listen_tcp({address = net.IP4_Loopback, port = options.port})
    if listen_error != nil { return false }
    endpoint, endpoint_error := net.bound_endpoint(listener)
    if endpoint_error != nil { return false }
    net.set_blocking(listener, false)
    provider.listener, provider.port = listener, endpoint.port
    provider.issuer_length = copy(provider.issuer[:], fmt.tprintf("http://127.0.0.1:%d", endpoint.port))
    if options.algorithm == .ES256 {
        if !ecdsa.private_key_generate(&provider.es_key, .SECP256R1) { return false }
    } else {
        if !rsa.private_key_generate(&provider.rs_key, 2048) { return false }
    }
    return ecdsa.private_key_generate(&provider.other_key, .SECP256R1)
}

Stop :: proc(provider: ^Provider) {
    net.close(provider.listener)
}

// For `oidc.HttpIdle`: the provider answers what is waiting
Idle :: proc(user: rawptr) {
    Step(cast(^Provider)user)
}

// Answers the requests that are waiting (one connection per call)
Step :: proc(provider: ^Provider) {
    client, _, accept_error := net.accept_tcp(provider.listener)
    if accept_error != nil { return }
    defer net.close(client)
    net.set_option(client, .Receive_Timeout, 2 * time.Second)
    buffer: [8192]u8
    length: int
    header_end: int = -1
    for length < len(buffer) {
        count, error := net.recv_tcp(client, buffer[length:])
        if count > 0 { length += count }
        if header_end < 0 { header_end = indexOf(buffer[:length], "\r\n\r\n") }
        if header_end >= 0 {
            wanted: int = contentLength(string(buffer[:header_end]))
            if length - (header_end + 4) >= wanted { break }
        }
        if error != nil && error != .Would_Block { break }
        if error == .Would_Block { time.sleep(time.Millisecond) }
        if count == 0 && error == nil { break }
    }
    if header_end < 0 { return }
    provider.requests += 1
    head: string = string(buffer[:header_end])
    body: string = string(buffer[header_end + 4:length])
    first_line: string = head[:strings.index(head, "\r\n")] if strings.contains(head, "\r\n") else head
    parts: []string = strings.split(first_line, " ", context.temp_allocator)
    if len(parts) < 2 { return }
    method, target: string = parts[0], parts[1]
    path: string = target
    query: string
    if question := strings.index_byte(target, '?'); question >= 0 {
        path, query = target[:question], target[question + 1:]
    }
    switch path {
    case "/.well-known/openid-configuration":
        issuer: string = Issuer(provider)
        document: string = fmt.tprintf("{{\"issuer\":\"%s\",\"authorization_endpoint\":\"%s/authorize\",\"token_endpoint\":\"%s/token\",\"jwks_uri\":\"%s/jwks\",\"revocation_endpoint\":\"%s/revoke\",\"end_session_endpoint\":\"%s/logout\",\"userinfo_endpoint\":\"%s/userinfo\",\"device_authorization_endpoint\":\"%s/device\",\"response_types_supported\":[\"code\"],\"id_token_signing_alg_values_supported\":[\"%s\"]}}",
            issuer, issuer, issuer, issuer, issuer, issuer, issuer, issuer, "ES256" if provider.options.algorithm == .ES256 else "RS256")
        respond(client, 200, "application/json", document)
    case "/jwks":
        jwk: [1024]u8
        key_text: string
        if provider.options.algorithm == .ES256 { key_text = oidc.JwkOfEs256(&provider.es_key, "mock-key", jwk[:]) } else { key_text = oidc.JwkOfRs256(&provider.rs_key, "mock-key", jwk[:]) }
        respond(client, 200, "application/json", fmt.tprintf("{{\"keys\":[%s]}}", key_text))
    case "/authorize":
        provider.authorize_requests += 1
        scratch: [512]u8
        redirect: string = strings.clone(oidc.QueryValue(query, "redirect_uri", scratch[:]), context.temp_allocator)
        state: string = strings.clone(oidc.QueryValue(query, "state", scratch[:]), context.temp_allocator)
        nonce: string = strings.clone(oidc.QueryValue(query, "nonce", scratch[:]), context.temp_allocator)
        challenge: string = strings.clone(oidc.QueryValue(query, "code_challenge", scratch[:]), context.temp_allocator)
        if oidc.QueryValue(query, "client_id", scratch[:]) != provider.options.client_id || redirect == "" || oidc.QueryValue(query, "code_challenge_method", scratch[:]) != "S256" {
            respond(client, 400, "text/plain", "bad authorization request")
            return
        }
        code := newCode(provider, 1, challenge, nonce)
        copy(provider.nonce_of_last_code[:], nonce)
        location: string = fmt.tprintf("%s%scode=%s&state=%s", redirect, "&" if strings.contains(redirect, "?") else "?", string(code.value[:code.value_length]), state)
        redirectTo(client, location)
    case "/token":
        token(provider, client, body, head)
    case "/revoke":
        // RFC 7009: the client is authenticated like at the token endpoint; an unknown token is answered 200 too
        if !clientAuthenticated(provider, body, head) {
            provider.failed_authentications += 1
            respond(client, 401, "application/json", `{"error":"invalid_client"}`)
            return
        }
        revoke_scratch: [512]u8
        if code := findCode(provider, oidc.QueryValue(body, "token", revoke_scratch[:]), 2); code != nil {
            code.used = true
            provider.revocations += 1
        }
        respond(client, 200, "application/json", "")
    case "/device":
        code := newCode(provider, 3, "", "")
        respond(client, 200, "application/json", fmt.tprintf("{{\"device_code\":\"%s\",\"user_code\":\"WDJB-MJHT\",\"verification_uri\":\"%s/activate\",\"expires_in\":300,\"interval\":1}}", string(code.value[:code.value_length]), Issuer(provider)))
    case "/userinfo":
        if strings.contains(head, "Bearer access-") {
            if provider.options.userinfo_name != "" {
                respond(client, 200, "application/json", fmt.tprintf("{{\"sub\":\"%s\",\"email\":\"%s\",\"name\":\"%s\"}}", provider.options.subject, provider.options.email, provider.options.userinfo_name), provider.options.header_padding)
            } else {
                respond(client, 200, "application/json", fmt.tprintf("{{\"sub\":\"%s\",\"email\":\"%s\"}}", provider.options.subject, provider.options.email), provider.options.header_padding)
            }
        } else {
            respond(client, 401, "application/json", "{\"error\":\"invalid_token\"}")
        }
    case:
        _ = method
        respond(client, 404, "text/plain", "not found")
    }
}

@(private)
newCode :: proc(provider: ^Provider, kind: u8, challenge: string, nonce: string) -> ^Code {
    slot: int
    for i in 0 ..< MAX_CODES {
        if provider.codes[i].value_length == 0 || provider.codes[i].used {
            slot = i
            break
        }
    }
    code: ^Code = &provider.codes[slot]
    code^ = {kind = kind}
    text: [32]u8
    code.value_length = copy(code.value[:], oidc.RandomText(18, text[:]))
    code.challenge_length = copy(code.challenge[:], challenge)
    code.nonce_length = copy(code.nonce[:], nonce)
    return code
}

// The person ended the session at the provider (or the refresh tokens expired): every refresh token that was handed out is now refused
RevokeRefreshTokens :: proc(provider: ^Provider) {
    for i in 0 ..< MAX_CODES {
        if provider.codes[i].kind == 2 { provider.codes[i].used = true }
    }
}

@(private)
findCode :: proc(provider: ^Provider, value: string, kind: u8) -> ^Code {
    for i in 0 ..< MAX_CODES {
        code: ^Code = &provider.codes[i]
        if code.kind == kind && !code.used && string(code.value[:code.value_length]) == value { return code }
    }
    return nil
}

// Does the request prove the client: the secret in an `Authorization: Basic` header (`id:secret`, each percent encoded, base64) or in the form, as far as `client_auth` allows
@(private)
clientAuthenticated :: proc(provider: ^Provider, form: string, head: string) -> bool {
    wanted: string = provider.options.client_secret
    scratch: [512]u8
    if provider.options.client_auth == .PUBLIC {
        return oidc.QueryValue(form, "client_secret", scratch[:]) == "" && !strings.contains(head, "Authorization: Basic ")
    }
    if wanted == "" { return true }
    if provider.options.client_auth != .BASIC_ONLY && oidc.QueryValue(form, "client_secret", scratch[:]) == wanted { return true }
    if provider.options.client_auth != .POST_ONLY {
        marker: string = "Authorization: Basic "
        at: int = strings.index(head, marker)
        if at >= 0 {
            rest: string = head[at + len(marker):]
            end: int = strings.index_byte(rest, 13)          // the end of the header line (CR)
            if end < 0 { end = len(rest) }
            decoded, error := base64.decode(rest[:end], allocator = context.temp_allocator)
            if error == nil {
                pair: string = string(decoded)
                colon: int = strings.index_byte(pair, ':')
                if colon >= 0 {
                    id_scratch: [128]u8
                    secret_scratch: [128]u8
                    id: string = oidc.QueryValue(fmt.tprintf("v=%s", pair[:colon]), "v", id_scratch[:])
                    secret: string = oidc.QueryValue(fmt.tprintf("v=%s", pair[colon + 1:]), "v", secret_scratch[:])
                    return id == provider.options.client_id && secret == wanted
                }
            }
        }
    }
    return false
}

@(private)
token :: proc(provider: ^Provider, client: net.TCP_Socket, form: string, head: string) {
    scratch: [512]u8
    grant: string = strings.clone(oidc.QueryValue(form, "grant_type", scratch[:]), context.temp_allocator)
    if grant != "urn:ietf:params:oauth:grant-type:device_code" && !clientAuthenticated(provider, form, head) {
        provider.failed_authentications += 1
        respond(client, 401, "application/json", `{"error":"invalid_client","error_description":"client authentication failed"}`)
        return
    }
    switch grant {
    case "authorization_code":
        code := findCode(provider, oidc.QueryValue(form, "code", scratch[:]), 1)
        if code == nil {
            respond(client, 400, "application/json", "{\"error\":\"invalid_grant\",\"error_description\":\"unknown or used code\"}")
            return
        }
        code.used = true
        digest: [32]u8
        hash.hash_bytes_to_buffer(.SHA256, transmute([]u8)oidc.QueryValue(form, "code_verifier", scratch[:]), digest[:])
        challenge: [64]u8
        if oidc.Base64UrlEncode(digest[:], challenge[:]) != string(code.challenge[:code.challenge_length]) {
            respond(client, 400, "application/json", "{\"error\":\"invalid_grant\",\"error_description\":\"PKCE verification failed\"}")
            return
        }
        issue(provider, client, string(code.nonce[:code.nonce_length]))
    case "client_credentials":
        // with `client_secret` the client was authenticated above (Basic or form); with only `service_secret` the secret has to be in the form
        service_allowed: bool = provider.options.client_secret != "" || (provider.options.service_secret != "" && oidc.QueryValue(form, "client_secret", scratch[:]) == provider.options.service_secret)
        if !service_allowed || oidc.QueryValue(form, "client_id", scratch[:]) != provider.options.client_id {
            respond(client, 401, "application/json", "{\"error\":\"invalid_client\"}")
            return
        }
        issueService(provider, client, oidc.QueryValue(form, "scope", scratch[:]))
    case "refresh_token":
        if provider.options.refresh_secret != "" && oidc.QueryValue(form, "client_secret", scratch[:]) != provider.options.refresh_secret {
            respond(client, 401, "application/json", "{\"error\":\"invalid_client\"}")
            return
        }
        code := findCode(provider, oidc.QueryValue(form, "refresh_token", scratch[:]), 2)
        if code == nil {
            respond(client, 400, "application/json", "{\"error\":\"invalid_grant\"}")
            return
        }
        if provider.options.rotate_refresh { code.used = true }
        issue(provider, client, "")
    case "urn:ietf:params:oauth:grant-type:device_code":
        code := findCode(provider, oidc.QueryValue(form, "device_code", scratch[:]), 3)
        if code == nil {
            respond(client, 400, "application/json", "{\"error\":\"expired_token\"}")
            return
        }
        code.polls += 1
        if code.polls < 3 {
            respond(client, 400, "application/json", "{\"error\":\"authorization_pending\"}")
            return
        }
        code.used = true
        issue(provider, client, "")
    case:
        respond(client, 400, "application/json", "{\"error\":\"unsupported_grant_type\"}")
    }
}

@(private)
issue :: proc(provider: ^Provider, client: net.TCP_Socket, nonce: string) {
    now: i64 = oidc.NowUnix()
    issuer: string = Issuer(provider)
    audience: string = provider.options.client_id
    expires: i64 = now + provider.options.lifetime
    switch provider.fault {
    case .WRONG_AUDIENCE: audience = "another-client"
    case .WRONG_ISSUER: issuer = "http://127.0.0.1:1"
    case .EXPIRED: expires = now - 3600
    case .NONE, .BAD_SIGNATURE, .WRONG_NONCE, .HS256:
    }
    shown_nonce: string = "not-the-nonce" if provider.fault == .WRONG_NONCE else nonce
    nonce_claim: string = "" if provider.options.omit_nonce else fmt.tprintf(",\"nonce\":\"%s\"", shown_nonce)
    payload: string = fmt.tprintf("{{\"iss\":\"%s\",\"sub\":\"%s\",\"aud\":\"%s\",\"exp\":%d,\"iat\":%d%s,\"email\":\"%s\"}}", issuer, provider.options.subject, audience, expires, now, nonce_claim, provider.options.email)
    out: [3072]u8
    id_token: string
    switch {
    case provider.fault == .HS256:
        hs: [3072]u8
        id_token = fmt.tprintf("%s.%s.AAAA", oidc.Base64UrlEncode(transmute([]u8)string("{\"alg\":\"HS256\",\"typ\":\"JWT\"}"), hs[:128]), oidc.Base64UrlEncode(transmute([]u8)payload, hs[128:]))
    case provider.fault == .BAD_SIGNATURE:
        id_token = oidc.JwtSignEs256(&provider.other_key, "mock-key", payload, out[:])
    case provider.options.algorithm == .ES256:
        id_token = oidc.JwtSignEs256(&provider.es_key, "mock-key", payload, out[:])
    case:
        id_token = oidc.JwtSignRs256(&provider.rs_key, "mock-key", payload, out[:])
    }
    refresh := newCode(provider, 2, "", "")
    access: [32]u8
    respond(client, 200, "application/json", fmt.tprintf("{{\"token_type\":\"Bearer\",\"expires_in\":%d,\"id_token\":\"%s\",\"access_token\":\"access-%s\",\"refresh_token\":\"%s\"}}", provider.options.lifetime, id_token, oidc.RandomText(12, access[:]), string(refresh.value[:refresh.value_length])))
}

// The access token of a service (client credentials): a JWT without `sub`, the audience is the scope that was asked for, no ID token and no refresh token
@(private)
issueService :: proc(provider: ^Provider, client: net.TCP_Socket, scope: string) {
    now: i64 = oidc.NowUnix()
    lifetime: i64 = provider.options.lifetime if provider.options.lifetime != 0 else 600
    payload: string = fmt.tprintf("{{\"iss\":\"%s\",\"aud\":\"%s\",\"client_id\":\"%s\",\"exp\":%d,\"iat\":%d}}", Issuer(provider), scope, provider.options.client_id, now + lifetime, now)
    out: [3072]u8
    token: string
    if provider.options.algorithm == .ES256 {
        token = oidc.JwtSignEs256(&provider.es_key, "mock-key", payload, out[:])
    } else {
        token = oidc.JwtSignRs256(&provider.rs_key, "mock-key", payload, out[:])
    }
    respond(client, 200, "application/json", fmt.tprintf("{{\"token_type\":\"Bearer\",\"expires_in\":%d,\"access_token\":\"%s\"}}", lifetime, token))
}

@(private)
respond :: proc(client: net.TCP_Socket, status: int, content_type: string, body: string, padding: int = 0) {
    // `padding`: a header of that many bytes (real providers send kilobytes of headers: CDN, cookies, security policies)
    extra: string = fmt.tprintf("X-Padding: %s\r\n", strings.repeat("a", padding, context.temp_allocator)) if padding > 0 else ""
    head: string = fmt.tprintf("HTTP/1.1 %d X\r\nContent-Type: %s\r\nContent-Length: %d\r\n%sConnection: close\r\n\r\n", status, content_type, len(body), extra)
    net.send_tcp(client, transmute([]u8)head)
    net.send_tcp(client, transmute([]u8)body)
}

@(private)
redirectTo :: proc(client: net.TCP_Socket, location: string) {
    head: string = fmt.tprintf("HTTP/1.1 302 Found\r\nLocation: %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", location)
    net.send_tcp(client, transmute([]u8)head)
}

@(private)
indexOf :: proc(bytes: []u8, needle: string) -> int {
    if len(bytes) < len(needle) { return -1 }
    for i in 0 ..< len(bytes) - len(needle) + 1 {
        if string(bytes[i:i + len(needle)]) == needle { return i }
    }
    return -1
}

@(private)
contentLength :: proc(head: string) -> int {
    rest: string = head
    for line in strings.split_lines_iterator(&rest) {
        if strings.has_prefix(strings.to_lower(line, context.temp_allocator), "content-length:") {
            value: int
            for c in strings.trim_space(line[15:]) { value = value * 10 + int(c - '0') }
            return value
        }
    }
    return 0
}
