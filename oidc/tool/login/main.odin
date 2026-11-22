package main

// A whole login against a real provider, to try the settings of oidc/providers/providers.local.txt:
//
//     odin run oidc/tool/login -- discord|google|github|spacetimeauth [--no-browser] [--file path] [--timeout seconds] [--issuer url]
//
// Discord, Google, SpacetimeAuth: the browser flow (a page opens, you log in, the browser comes back to 127.0.0.1) and the claims of the verified ID token are printed. GitHub: the device flow (a code is
// printed, you type it at github.com/login/device) and the user from api.github.com. Tokens are never printed, and nothing is stored.
// `--issuer` replaces the provider's address (a provider of your own, or the mock of the tests); for github it names a server with the GitHub style endpoints /device, /token and /userinfo.
// The work is in `run` (returns the exit code, writes through `say`) so that login_test.odin can drive it against the mock provider.

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import oidc "../.."

SETTINGS_PATHS :: [?]string{"oidc/providers/providers.local.txt", "providers/providers.local.txt", "providers.local.txt"}

// Where the text goes: nil prints it as it happens (the address has to be seen before the tool waits), a test gives a builder
capture: ^strings.Builder

// Called every turn while a login waits (instead of a short sleep): a test plays the browser and steps the provider here. `login` is nil in the device flow.
Idle: proc(login: ^oidc.Login)

// The login that is running, for the idle hook of a test
current_login: ^oidc.Login

main :: proc() {
    os.exit(run(os.args[1:]))
}

say :: proc(text: string) {
    if capture != nil {
        strings.write_string(capture, text)
        strings.write_byte(capture, '\n')
    } else {
        fmt.println(text)
    }
}

failed :: proc(text: string, code: int) -> int {
    if capture != nil {
        strings.write_string(capture, "error: ")
        strings.write_string(capture, text)
        strings.write_byte(capture, '\n')
    } else {
        fmt.eprintln(text)
    }
    return code
}

run :: proc(arguments: []string) -> int {
    name: string
    settings_path: string
    issuer: string
    open_browser: bool = true
    timeout: f64 = 300
    for i := 0; i < len(arguments); i += 1 {
        switch arguments[i] {
        case "--no-browser": open_browser = false
        case "--file":
            i += 1
            if i < len(arguments) { settings_path = arguments[i] }
        case "--issuer":
            i += 1
            if i < len(arguments) { issuer = arguments[i] }
        case "--timeout":
            i += 1
            if i < len(arguments) {
                seconds: f64
                for c in arguments[i] {
                    if c < '0' || c > '9' { seconds = 0; break }
                    seconds = seconds * 10 + f64(c - '0')
                }
                if seconds > 0 { timeout = seconds }
            }
        case: name = arguments[i]
        }
    }
    preset: oidc.Preset
    switch name {
    case "discord": preset = .DISCORD
    case "google": preset = .GOOGLE
    case "github": preset = .GITHUB
    case "spacetimeauth": preset = .SPACETIMEAUTH
    case: return failed("usage: odin run oidc/tool/login -- discord|google|github|spacetimeauth [--no-browser] [--file path] [--timeout seconds] [--issuer url]", 2)
    }
    text, found := readSettings(settings_path)
    if !found { return failed("no settings file: copy oidc/providers/providers.example.txt to oidc/providers/providers.local.txt", 2) }
    config: oidc.ClientConfig = oidc.ClientConfigRead(text, name, oidc.PresetConfig(preset, ""))
    if issuer != "" { config.issuer = issuer }
    if config.client_id == "" || strings.has_prefix(config.client_id, "YOUR_") {
        return failed(fmt.tprintf("%s.client_id is not set in the settings file (see oidc/providers/README.md)", name), 2)
    }
    say(fmt.tprintf("%s: client id %s...", name, config.client_id[:min(6, len(config.client_id))]))
    if preset == .GITHUB { return githubDevice(config, issuer, timeout) }
    return browserLogin(config, open_browser, timeout)
}

readSettings :: proc(explicit: string) -> (text: string, found: bool) {
    paths: [3]string = SETTINGS_PATHS
    if explicit != "" {
        data, error := os.read_entire_file(explicit, context.temp_allocator)
        return string(data), error == nil
    }
    for path in paths {
        data, error := os.read_entire_file(path, context.temp_allocator)
        if error == nil { return string(data), true }
    }
    return "", false
}

waitTurn :: proc(login: ^oidc.Login) {
    if Idle != nil { Idle(login) } else { time.sleep(50 * time.Millisecond) }
}

browserLogin :: proc(config: oidc.ClientConfig, open_browser: bool, timeout: f64) -> int {
    login: ^oidc.Login = new(oidc.Login)
    defer free(login)
    current_login = login
    defer current_login = nil
    if !oidc.LoginBegin(login, config) { return failed(fmt.tprintf("login did not start: %s", oidc.LoginError(login)), 1) }
    say(fmt.tprintf("redirect address to register at the provider: %s", redirectOf(login)))
    // the address is always printed: a browser that starts cold takes seconds, or opens somewhere else
    say(fmt.tprintf("open this address in a browser:\n%s", oidc.LoginUrl(login)))
    if open_browser && oidc.LoginOpenBrowser(login) { say("the browser was asked to open it") }
    started: time.Tick = time.tick_now()
    for oidc.LoginPoll(login) == .WAITING {
        if time.duration_seconds(time.tick_since(started)) > timeout { return failed("no answer in time", 1) }
        waitTurn(login)
    }
    if login.state != .DONE { return failed(fmt.tprintf("login failed: %s", oidc.LoginError(login)), 1) }
    claims: oidc.JwtClaims = login.claims
    say("login ok, the ID token is verified (signature, issuer, audience, expiry, nonce)")
    say(fmt.tprintf("  issuer   %s", claims.issuer))
    say(fmt.tprintf("  subject  %s", claims.subject))
    say(fmt.tprintf("  audience is the client id: %v", oidc.JwtAudienceHas(claims, config.client_id)))
    for field in ([]string{"name", "global_name", "preferred_username", "email", "email_verified", "picture"}) {
        if value, has := oidc.JsonString(claims.payload, field); has { say(fmt.tprintf("  %-8s %s", field, value)) }
    }
    say(fmt.tprintf("  refresh token: %v, ID token %d characters, expires in %d s", login.tokens.refresh_token != "", len(login.tokens.id_token), login.tokens.expires_in))
    if login.tokens.refresh_token != "" {
        refreshed: ^oidc.Tokens = new(oidc.Tokens)
        defer free(refreshed)
        say(fmt.tprintf("  refresh works: %v", oidc.Refresh(&login.metadata, config, login.tokens.refresh_token, refreshed)))
        if refreshed.error != "" { say(fmt.tprintf("  refresh answer: %s %s", refreshed.error, refreshed.error_description)) }
    }
    info: [4096]u8
    if user, ok := oidc.Userinfo(&login.metadata, login.tokens.access_token, info[:]); ok {
        subject, _ := oidc.JsonString(user, "sub")
        say(fmt.tprintf("  userinfo: %d bytes of JSON, subject %s", len(user), subject))
    }
    return 0
}

redirectOf :: proc(login: ^oidc.Login) -> string {
    url: string = oidc.LoginUrl(login)
    at: int = strings.index_byte(url, '?')
    if at < 0 { return "(see the address)" }
    buffer := make([]u8, 256, context.temp_allocator)
    query: string = oidc.QueryValue(url[at + 1:], "redirect_uri", buffer)
    return query if query != "" else "(see the address)"
}

githubDevice :: proc(config: oidc.ClientConfig, issuer: string, timeout: f64) -> int {
    metadata: ^oidc.Metadata = new(oidc.Metadata)
    defer free(metadata)
    oidc.PresetMetadataGithub(metadata)
    if issuer != "" {
        metadata.device_authorization_endpoint = fmt.tprintf("%s/device", issuer)
        metadata.token_endpoint = fmt.tprintf("%s/token", issuer)
        metadata.userinfo_endpoint = fmt.tprintf("%s/userinfo", issuer)
    }
    device: ^oidc.DeviceCode = new(oidc.DeviceCode)
    defer free(device)
    if !oidc.DeviceStart(metadata, config, device) {
        return failed("GitHub refused the device flow: is \"Enable Device Flow\" ticked for the OAuth App, and is the client id right?", 1)
    }
    say(fmt.tprintf("open %s and type the code  %s", device.verification_uri, device.user_code))
    tokens: ^oidc.Tokens = new(oidc.Tokens)
    defer free(tokens)
    started: time.Tick = time.tick_now()
    limit: f64 = min(timeout, f64(device.expires_in)) if device.expires_in > 0 else timeout
    for {
        state: oidc.DevicePollState = oidc.DevicePoll(metadata, config, device, tokens)
        if state == .DONE { break }
        if state != .PENDING { return failed(fmt.tprintf("device flow ended: %v (%s)", state, tokens.error), 1) }
        if time.duration_seconds(time.tick_since(started)) > limit { return failed("the code expired", 1) }
        waitTurn(nil)
    }
    info: [8192]u8
    user, ok := oidc.Userinfo(metadata, tokens.access_token, info[:])
    if !ok { return failed("login ok but the user could not be read", 1) }
    say("login ok (GitHub gives an access token, not an ID token)")
    for field in ([]string{"login", "name", "html_url", "sub"}) {
        if value, has := oidc.JsonString(user, field); has { say(fmt.tprintf("  %-8s %s", field, value)) }
    }
    if id, has := oidc.JsonInt(user, "id"); has { say(fmt.tprintf("  id       %d", id)) }
    return 0
}
