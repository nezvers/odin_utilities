#+build windows, linux, darwin, freebsd, openbsd, netbsd
package oidc

// The login of a program on a person's computer: the authorization code flow with PKCE and a redirect to a port on the loopback (RFC 8252, the way native apps sign in). The program opens the
// provider's login page in the browser, the person signs in there (with Google, a password, a magic link: the provider's business), the browser is sent back to `http://127.0.0.1:<port>/callback`
// where this code is listening, the code is exchanged for tokens, and the ID token is verified against the keys of the provider. The program never sees a password.
//
//     login: ^Login = new(Login)                                // about 60 KB
//     LoginBegin(login, {issuer = "https://auth.example.com", client_id = "my-client"})      // discovers, listens, builds `login.url`
//     LoginOpenBrowser(login)                                    // or show login.url
//     every frame: switch LoginPoll(login) { case .DONE: use login.tokens.id_token; case .FAILED: login.error ... }
//
// No thread: `LoginPoll` accepts the browser's request without blocking; only the exchange with the provider (one request) and the keys (one more) block, for a moment.

import "core:fmt"
import "core:net"
import "core:strings"
import "core:time"

LoginState :: enum u8 {
    IDLE,
    WAITING,                    // the browser has not come back yet
    DONE,                       // `tokens` and `claims` are filled in
    FAILED,                     // `error` says why
    CANCELLED,
}

LOGIN_TIMEOUT :: 10 * time.Minute

Login :: struct {
    state: LoginState,
    config: ClientConfig,
    metadata: Metadata,
    keys: KeySet,
    listener: net.TCP_Socket,
    port: int,
    redirect_uri: [64]u8,
    redirect_length: int,
    state_value: [32]u8,
    state_length: int,
    nonce: [32]u8,
    nonce_length: int,
    verifier: [64]u8,
    verifier_length: int,
    url: [2048]u8,              // the page to open
    url_length: int,
    started: time.Tick,
    tokens: Tokens,
    claims_storage: [4096]u8,   // the claims of the ID token (strings of `claims` point into it)
    claims: JwtClaims,
    error: [256]u8,
    error_length: int,
    userinfo: [2048]u8,         // the user info of the provider (JSON) fetched after the login, for the name and the picture that the ID token may not carry
    userinfo_length: int,
    rejected: [256]u8,         // what the last callback that was not this login's carried (an older tab, another site), the one-time `code` shown by its length only: to show why it was ignored
    rejected_length: int,
    rejected_count: int,        // how many callbacks were ignored for that reason
    busy: bool,                 // a poll is in progress (its own requests step the waiting code, which must not poll again)
}

// The JSON of the user info that was fetched after the login ("" when the provider has none)
LoginUserinfo :: proc(login: ^Login) -> string {
    return string(login.userinfo[:login.userinfo_length])
}

// What to call the person: `name`, `global_name`, `preferred_username` or `username`, from the ID token first and from the user info second
LoginDisplayName :: proc(login: ^Login) -> (name: string, found: bool) {
    fields: [4]string = {"name", "global_name", "preferred_username", "username"}
    for source in ([]string{login.claims.payload, LoginUserinfo(login)}) {
        for field in fields {
            if value, has := JsonString(source, field); has && value != "" { return value, true }
        }
    }
    return "", false
}

LoginUrl :: proc(login: ^Login) -> string {
    return string(login.url[:login.url_length])
}

LoginError :: proc(login: ^Login) -> string {
    return string(login.error[:login.error_length])
}

@(private)
fail :: proc(login: ^Login, message: string) {
    login.error_length = copy(login.error[:], message)
    login.state = .FAILED
    if login.listener != {} {
        net.close(login.listener)
        login.listener = {}
    }
}

// Discovers the provider, starts listening on the loopback and builds the page to open. False (and `LoginError`) when the provider cannot be reached or no port can be bound.
LoginBegin :: proc(login: ^Login, config: ClientConfig) -> bool {
    login^ = {}
    login.config = config
    if !Discover(config.issuer, &login.metadata) {
        fail(login, "the provider does not answer, or its discovery document is not usable")
        return false
    }
    if login.metadata.authorization_endpoint == "" {
        fail(login, "the provider has no authorization endpoint")
        return false
    }
    listener, listen_error := net.listen_tcp({address = net.IP4_Loopback, port = config.redirect_port})
    if listen_error != nil {
        fail(login, "no port for the redirect of the login")
        return false
    }
    endpoint, endpoint_error := net.bound_endpoint(listener)
    if endpoint_error != nil {
        net.close(listener)
        fail(login, "no port for the redirect of the login")
        return false
    }
    net.set_blocking(listener, false)
    login.listener, login.port = listener, endpoint.port
    login.redirect_length = copy(login.redirect_uri[:], fmt.tprintf("http://127.0.0.1:%d/callback", login.port))
    login.state_length = len(RandomText(16, login.state_value[:]))
    login.nonce_length = len(RandomText(16, login.nonce[:]))
    login.verifier_length = len(PkceVerifier(login.verifier[:]))
    challenge_buffer: [64]u8
    challenge: string = PkceChallenge(string(login.verifier[:login.verifier_length]), challenge_buffer[:])

    url: strings.Builder
    strings.builder_init(&url, context.temp_allocator)
    strings.write_string(&url, login.metadata.authorization_endpoint)
    strings.write_string(&url, "?" if !strings.contains(login.metadata.authorization_endpoint, "?") else "&")
    FormField(&url, "response_type", "code")
    FormField(&url, "client_id", config.client_id)
    FormField(&url, "redirect_uri", string(login.redirect_uri[:login.redirect_length]))
    FormField(&url, "scope", config.scopes if config.scopes != "" else SCOPES_DEFAULT)
    FormField(&url, "state", string(login.state_value[:login.state_length]))
    FormField(&url, "nonce", string(login.nonce[:login.nonce_length]))
    FormField(&url, "code_challenge", challenge)
    FormField(&url, "code_challenge_method", "S256")
    if config.extra != "" {
        strings.write_byte(&url, '&')
        strings.write_string(&url, config.extra)
    }
    login.url_length = copy(login.url[:], strings.to_string(url))
    login.started = time.tick_now()
    login.state = .WAITING
    return true
}

// Cancels a login that waits (the port is closed)
LoginCancel :: proc(login: ^Login) {
    if login.listener != {} {
        net.close(login.listener)
        login.listener = {}
    }
    if login.state == .WAITING { login.state = .CANCELLED }
}

// One step: has the browser come back? The answer to the browser is a small page; the code is exchanged and the ID token checked before `.DONE`. Call it once a frame.
LoginPoll :: proc(login: ^Login) -> LoginState {
    if login.state != .WAITING || login.busy { return login.state }
    login.busy = true
    defer login.busy = false
    if time.tick_since(login.started) > LOGIN_TIMEOUT {
        fail(login, "nobody signed in in time")
        return login.state
    }
    client, _, accept_error := net.accept_tcp(login.listener)
    if accept_error != nil { return .WAITING }
    defer net.close(client)
    net.set_option(client, .Receive_Timeout, 2 * time.Second)
    request: [4096]u8
    length: int
    for length < len(request) {
        count, error := net.recv_tcp(client, request[length:])
        if count > 0 { length += count }
        if error != nil || count == 0 || indexOf(request[:length], "\r\n") >= 0 { break }
    }
    line_end: int = indexOf(request[:length], "\r\n")
    if line_end < 0 {
        reply(client, 400, "Bad request")
        return .WAITING
    }
    parts: []string = strings.split(string(request[:line_end]), " ", context.temp_allocator)      // GET /callback?code=..&state=.. HTTP/1.1
    if len(parts) < 2 || !strings.has_prefix(parts[1], "/callback") {
        reply(client, 404, "Not found")                  // a favicon request, a scanner: the login goes on waiting
        return .WAITING
    }
    query: string = parts[1][strings.index_byte(parts[1], '?') + 1:] if strings.contains(parts[1], "?") else ""
    scratch: [2048]u8
    state_scratch: [64]u8
    if received := QueryValue(query, "state", state_scratch[:]); received != string(login.state_value[:login.state_length]) {
        login.rejected_length = copy(login.rejected[:], redactCode(query, login.rejected[:]))
        login.rejected_count += 1
        _ = received
        reply(client, 400, "This page does not belong to the login that is running now: it is probably a tab of an older attempt. Close it and open the address that the program printed last.")
        return .WAITING                                  // a request that was not asked for (CSRF): ignored, the real one may still come
    }
    if provider_error := QueryValue(query, "error", scratch[:]); provider_error != "" {
        description_scratch: [512]u8
        reply(client, 200, "Sign in was cancelled. You can close this window.")
        fail(login, fmt.tprintf("the provider refused the login: %s %s", provider_error, QueryValue(query, "error_description", description_scratch[:])))
        return login.state
    }
    code: string = QueryValue(query, "code", scratch[:])
    if code == "" {
        reply(client, 400, "No code.")
        fail(login, "the provider sent no code")
        return login.state
    }
    // the browser is answered at the end, when the program knows: a page that says "signed in" before the code is exchanged and the ID token checked would claim a login that may still fail
    if !ExchangeCode(&login.metadata, login.config, code, string(login.verifier[:login.verifier_length]), string(login.redirect_uri[:login.redirect_length]), &login.tokens) {
        failPage(client, login, fmt.tprintf("the code could not be exchanged: %s %s", login.tokens.error, login.tokens.error_description))
        return login.state
    }
    if login.tokens.id_token == "" {
        failPage(client, login, "the provider gave no ID token (is the scope openid asked?)")
        return login.state
    }
    if !FetchKeys(&login.metadata, &login.keys) {
        failPage(client, login, "the keys of the provider could not be fetched")
        return login.state
    }
    claims, error := JwtVerify(login.tokens.id_token, &login.keys, {issuer = login.metadata.issuer, audience = login.config.client_id, nonce = string(login.nonce[:login.nonce_length])}, login.claims_storage[:])
    if error != .NONE {
        failPage(client, login, fmt.tprintf("the ID token is not accepted: %s", VerifyErrorText(error)))
        return login.state
    }
    login.claims = claims
    net.close(login.listener)
    login.listener = {}
    login.state = .DONE
    // some providers (Discord) keep the name out of the ID token: the user info has it (best effort: a login does not fail because of it)
    if login.metadata.userinfo_endpoint != "" && login.tokens.access_token != "" {
        // the buffer holds the whole answer, headers too (a CDN's are kilobytes): big, and only the body is kept
        answer: [16384]u8
        text, fetched := Userinfo(&login.metadata, login.tokens.access_token, answer[:])
        if fetched { login.userinfo_length = copy(login.userinfo[:], text) }
    }
    name, has_name := LoginDisplayName(login)
    reply(client, 200, fmt.tprintf("Login verified. The program checked the ID token (signature, issuer, audience, expiry, nonce).\nIssuer: %s\nSubject: %s\nName: %s\nYou can close this window and go back to the program.", claims.issuer, claims.subject, name if has_name else "(none in the token)"))
    return .DONE
}

// The query with `code=` replaced by its length: a rejected callback is shown to the person, but the code is a one-time secret
@(private)
redactCode :: proc(query: string, out: []u8) -> string {
    at: int
    rest: string = query
    for len(rest) > 0 && at < len(out) {
        amp: int = strings.index_byte(rest, '&')
        pair: string = rest if amp < 0 else rest[:amp]
        rest = "" if amp < 0 else rest[amp + 1:]
        text: string = pair
        if strings.has_prefix(pair, "code=") { text = fmt.tprintf("code=<%d characters>", len(pair) - 5) }
        if at > 0 && at < len(out) { out[at] = '&'; at += 1 }
        at += copy(out[at:], text)
    }
    return string(out[:at])
}

// The login failed after the browser came back: the page says why, and the state of the login says it too
@(private)
failPage :: proc(client: net.TCP_Socket, login: ^Login, message: string) {
    reply(client, 400, fmt.tprintf("Login failed.\n%s", message))
    fail(login, message)
}

// The text of a page may hold what the provider sent (an error description): `<`, `>`, `&` and quotes are escaped, a line break becomes a paragraph break
@(private)
htmlEscape :: proc(text: string) -> string {
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    for c in transmute([]u8)text {
        switch c {
        case '<': strings.write_string(&builder, "&lt;")
        case '>': strings.write_string(&builder, "&gt;")
        case '&': strings.write_string(&builder, "&amp;")
        case '"': strings.write_string(&builder, "&quot;")
        case '\'': strings.write_string(&builder, "&#39;")
        case '\n': strings.write_string(&builder, "<br>")
        case: strings.write_byte(&builder, c)
        }
    }
    return strings.to_string(builder)
}

@(private)
reply :: proc(client: net.TCP_Socket, status: int, text: string) {
    reason: string = "OK" if status == 200 else "Error"
    page: string = fmt.tprintf("<html><body style=\"font-family:sans-serif\"><p>%s</p></body></html>", htmlEscape(text))
    head: string = fmt.tprintf("HTTP/1.1 %d %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n", status, reason, len(page))
    net.send_tcp(client, transmute([]u8)head)
    net.send_tcp(client, transmute([]u8)page)
}

// ---- the browser --------------------------------------------------------------------------------------------------------------------------------------------------------

// Opens the login page in the browser of the person (the default one). No shell is used: the address is an argument, so its `&` and `?` are not interpreted.
LoginOpenBrowser :: proc(login: ^Login) -> bool {
    return BrowserOpen(LoginUrl(login))
}
