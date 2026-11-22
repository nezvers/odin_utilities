package main

// A whole login against a real provider, to try the settings of oidc/providers/providers.local.txt:
//
//     odin run oidc/tool/login -- discord|google|github|spacetimeauth [--no-browser] [--file path]
//
// Discord, Google, SpacetimeAuth: the browser flow (a page opens, you log in, the browser comes back to 127.0.0.1) and the claims of the verified ID token are printed. GitHub: the device flow (a code is
// printed, you type it at github.com/login/device) and the user from api.github.com. Tokens are never printed in full, and nothing is stored.

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import oidc "../.."

SETTINGS_PATHS :: [?]string{"oidc/providers/providers.local.txt", "providers/providers.local.txt", "providers.local.txt"}

main :: proc() {
    name: string
    settings_path: string
    open_browser: bool = true
    for i := 1; i < len(os.args); i += 1 {
        switch os.args[i] {
        case "--no-browser": open_browser = false
        case "--file":
            i += 1
            if i < len(os.args) { settings_path = os.args[i] }
        case: name = os.args[i]
        }
    }
    preset: oidc.Preset
    switch name {
    case "discord": preset = .DISCORD
    case "google": preset = .GOOGLE
    case "github": preset = .GITHUB
    case "spacetimeauth": preset = .SPACETIMEAUTH
    case:
        fmt.eprintln("usage: odin run oidc/tool/login -- discord|google|github|spacetimeauth [--no-browser] [--file path]")
        os.exit(2)
    }
    text: string = readSettings(settings_path)
    config: oidc.ClientConfig = oidc.ClientConfigRead(text, name, oidc.PresetConfig(preset, ""))
    if config.client_id == "" || strings.has_prefix(config.client_id, "YOUR_") {
        fmt.eprintfln("%s.client_id is not set in the settings file (see oidc/providers/README.md)", name)
        os.exit(2)
    }
    fmt.printfln("%s: client id %s...", name, config.client_id[:min(6, len(config.client_id))])
    if preset == .GITHUB {
        githubDevice(config)
    } else {
        browserLogin(config, open_browser)
    }
}

readSettings :: proc(explicit: string) -> string {
    paths: [3]string = SETTINGS_PATHS
    if explicit != "" {
        data, error := os.read_entire_file(explicit, context.allocator)
        if error == nil { return string(data) }
        fmt.eprintfln("cannot read %s", explicit)
        os.exit(2)
    }
    for path in paths {
        data, error := os.read_entire_file(path, context.allocator)
        if error == nil { return string(data) }
    }
    fmt.eprintln("no settings file: copy oidc/providers/providers.example.txt to oidc/providers/providers.local.txt")
    os.exit(2)
}

browserLogin :: proc(config: oidc.ClientConfig, open_browser: bool) {
    login: ^oidc.Login = new(oidc.Login)
    if !oidc.LoginBegin(login, config) {
        fmt.eprintfln("login did not start: %s", oidc.LoginError(login))
        os.exit(1)
    }
    fmt.printfln("redirect address to register at the provider: %s", redirectOf(login))
    if open_browser && oidc.LoginOpenBrowser(login) {
        fmt.println("the browser was opened; log in there")
    } else {
        fmt.printfln("open this address in a browser:\n%s", oidc.LoginUrl(login))
    }
    started: time.Tick = time.tick_now()
    for oidc.LoginPoll(login) == .WAITING {
        if time.duration_seconds(time.tick_since(started)) > 300 {
            fmt.eprintln("no answer in five minutes")
            os.exit(1)
        }
        time.sleep(50 * time.Millisecond)
    }
    if login.state != .DONE {
        fmt.eprintfln("login failed: %s", oidc.LoginError(login))
        os.exit(1)
    }
    claims: oidc.JwtClaims = login.claims
    fmt.println("login ok, the ID token is verified (signature, issuer, audience, expiry, nonce)")
    fmt.printfln("  issuer   %s", claims.issuer)
    fmt.printfln("  subject  %s", claims.subject)
    fmt.printfln("  audience is the client id: %v", oidc.JwtAudienceHas(claims, config.client_id))
    for field in ([]string{"name", "global_name", "preferred_username", "email", "email_verified", "picture"}) {
        if value, found := oidc.JsonString(claims.payload, field); found { fmt.printfln("  %-8s %s", field, value) }
    }
    fmt.printfln("  refresh token: %v, ID token %d characters, expires in %d s", login.tokens.refresh_token != "", len(login.tokens.id_token), login.tokens.expires_in)
    if login.tokens.refresh_token != "" {
        refreshed: ^oidc.Tokens = new(oidc.Tokens)
        fmt.printfln("  refresh works: %v", oidc.Refresh(&login.metadata, config, login.tokens.refresh_token, refreshed))
        if refreshed.error != "" { fmt.printfln("  refresh answer: %s %s", refreshed.error, refreshed.error_description) }
    }
    info: [4096]u8
    if text, ok := oidc.Userinfo(&login.metadata, login.tokens.access_token, info[:]); ok {
        fmt.printfln("  userinfo: %d bytes of JSON, subject %s", len(text), oidc.JsonString(text, "sub") or_else "?")
    }
}

redirectOf :: proc(login: ^oidc.Login) -> string {
    url: string = oidc.LoginUrl(login)
    at: int = strings.index_byte(url, '?')
    if at < 0 { return "(see the address)" }
    buffer := make([]u8, 256, context.temp_allocator)
    query: string = oidc.QueryValue(url[at + 1:], "redirect_uri", buffer)
    return query if query != "" else "(see the address)"
}

githubDevice :: proc(config: oidc.ClientConfig) {
    metadata: ^oidc.Metadata = new(oidc.Metadata)
    oidc.PresetMetadataGithub(metadata)
    device: ^oidc.DeviceCode = new(oidc.DeviceCode)
    if !oidc.DeviceStart(metadata, config, device) {
        fmt.eprintln("GitHub refused the device flow: is \"Enable Device Flow\" ticked for the OAuth App, and is the client id right?")
        os.exit(1)
    }
    fmt.printfln("open %s and type the code  %s", device.verification_uri, device.user_code)
    tokens: ^oidc.Tokens = new(oidc.Tokens)
    started: time.Tick = time.tick_now()
    for {
        state: oidc.DevicePollState = oidc.DevicePoll(metadata, config, device, tokens)
        if state == .DONE { break }
        if state != .PENDING {
            fmt.eprintfln("device flow ended: %v (%s)", state, tokens.error)
            os.exit(1)
        }
        if time.duration_seconds(time.tick_since(started)) > f64(device.expires_in) {
            fmt.eprintln("the code expired")
            os.exit(1)
        }
        time.sleep(500 * time.Millisecond)
    }
    info: [8192]u8
    text, ok := oidc.Userinfo(metadata, tokens.access_token, info[:])
    if !ok {
        fmt.eprintln("login ok but the user could not be read")
        os.exit(1)
    }
    fmt.println("login ok (GitHub gives an access token, not an ID token)")
    for field in ([]string{"login", "name", "html_url"}) {
        if value, found := oidc.JsonString(text, field); found { fmt.printfln("  %-8s %s", field, value) }
    }
    if id, found := oidc.JsonInt(text, "id"); found { fmt.printfln("  id       %d", id) }
}
