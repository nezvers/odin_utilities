package main

// A real person's ID token (Google, Discord, SpacetimeAuth ...) against a real local SpacetimeDB server and the `auth` example module:
//
//     odin run spacetimedb/tool/auth_live -- google|discord|spacetimeauth [--no-browser] [--file path] [--issuer url] [--port n] [--timeout seconds]
//
// The settings are the ones of oidc/providers/providers.local.txt. The tool starts a throw away server (in memory, port 3191), publishes module/example/auth (`odin run spacetimedb/tool/setup` builds it),
// logs you in at the provider (the browser flow, like oidc/tool/login), tells the module to trust only that issuer and your client id, connects with the ID token and shows what the module recorded.
// The server fetches the provider's discovery document and keys itself, over the internet: that is the part the tests with the mock provider cannot show. `--issuer` replaces the provider's address
// (a provider of your own, the mock of the tests). The work is in `run` (exit code, text through `say`) so that auth_live_test.odin can drive it.

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "../.."
import oidc "../../../oidc"

DEFAULT_PORT :: 3191

// Where the text goes: nil prints it as it happens (the address has to be seen before the tool waits), a test gives a builder
capture: ^strings.Builder

// Called every turn while the login waits (instead of a short sleep): a test plays the browser here
Idle: proc(login: ^oidc.Login)

// The login that is running, for the idle hooks of a test
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

failed :: proc(text: string, code: int = 1) -> int {
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
    port: int = DEFAULT_PORT
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
        case "--port":
            i += 1
            if i < len(arguments) { port = number(arguments[i], DEFAULT_PORT) }
        case "--timeout":
            i += 1
            if i < len(arguments) { timeout = f64(number(arguments[i], 300)) }
        case: name = arguments[i]
        }
    }
    preset: oidc.Preset
    switch name {
    case "google": preset = .GOOGLE
    case "discord": preset = .DISCORD
    case "spacetimeauth": preset = .SPACETIMEAUTH
    case: return failed("usage: odin run spacetimedb/tool/auth_live -- google|discord|spacetimeauth [--no-browser] [--file path] [--issuer url] [--port n] [--timeout seconds]", 2)
    }
    path: string = settings_path if settings_path != "" else "oidc/providers/providers.local.txt"
    settings, read_error := os.read_entire_file(path, context.temp_allocator)
    if read_error != nil { return failed("no oidc/providers/providers.local.txt: see oidc/README.md (Getting a client id)", 2) }
    config: oidc.ClientConfig = oidc.ClientConfigRead(string(settings), name, oidc.PresetConfig(preset, ""))
    if issuer != "" { config.issuer = issuer }
    if config.client_id == "" || strings.has_prefix(config.client_id, "YOUR_") { return failed(fmt.tprintf("%s.client_id is not set", name), 2) }
    module_path: string = spacetimedb.FixturePath("auth-odin")
    if module_path == "" || !os.exists(spacetimedb.ServerCliPath()) { return failed("no server or no auth module: run `odin run spacetimedb/tool/setup`", 2) }
    module, module_error := os.read_entire_file(module_path, context.allocator)
    if module_error != nil { return failed("cannot read the module") }
    defer delete(module)

    root: string = fmt.tprintf("auth_live_server_%d", port)
    defer spacetimedb.ServerRemove(root)
    server: ^spacetimedb.Server = new(spacetimedb.Server)
    defer free(server)
    if !spacetimedb.ServerStart(server, {root = root, port = port, in_memory = true}) { return failed("the server does not start") }
    defer spacetimedb.ServerStop(server)
    say(fmt.tprintf("server up on port %d", port))

    response := make([]u8, 16384)
    defer delete(response)
    _, owner_token, made := spacetimedb.IdentityCreate(server.endpoint, response)
    if !made { return failed("no identity for the owner") }
    owner: string = strings.clone(owner_token, context.temp_allocator)
    published := spacetimedb.DatabasePublish(server.endpoint, "auth", module, owner, response)
    if !published.ok || published.status != 200 { return failed(fmt.tprintf("publish: %d %s", published.status, string(published.body))) }
    say("module published")

    // the login of the person at the provider
    login: ^oidc.Login = new(oidc.Login)
    defer free(login)
    current_login = login
    defer current_login = nil
    if !oidc.LoginBegin(login, config) { return failed(fmt.tprintf("login: %s", oidc.LoginError(login))) }
    // the address is always printed: a browser that starts cold takes seconds, or opens somewhere else
    say(fmt.tprintf("open this address in a browser:\n%s", oidc.LoginUrl(login)))
    if open_browser && oidc.LoginOpenBrowser(login) { say("the browser was asked to open it") }
    started: time.Tick = time.tick_now()
    for oidc.LoginPoll(login) == .WAITING {
        if time.duration_seconds(time.tick_since(started)) > timeout { return failed("no answer in time") }
        if Idle != nil { Idle(login) } else { time.sleep(50 * time.Millisecond) }
    }
    if login.state != .DONE { return failed(fmt.tprintf("login failed: %s", oidc.LoginError(login))) }
    say(fmt.tprintf("login ok: %s, subject %s", login.claims.issuer, login.claims.subject))
    session: ^spacetimedb.AuthSession = new(spacetimedb.AuthSession)
    defer free(session)
    if !spacetimedb.AuthSessionFrom(session, login) { return failed("the session does not fit") }
    token: string = spacetimedb.AuthToken(session)

    arena: runtime.Arena
    allocator: runtime.Allocator = runtime.arena_allocator(&arena)
    defer runtime.arena_destroy(&arena)
    receive := make([]u8, 1 << 16)
    message := make([]u8, 1 << 16)
    defer { delete(receive); delete(message) }
    connection: ^spacetimedb.Connection = new(spacetimedb.Connection)
    defer free(connection)

    // the owner says who is trusted: this issuer and this client id
    if !spacetimedb.ConnectionOpen(connection, {endpoint = server.endpoint, database = "auth", token = owner}, receive, message) { return failed(connection.error) }
    if _, greeted := spacetimedb.ConnectionWait(connection, isInitial, nil, allocator); !greeted { return failed("the owner is not greeted") }
    arguments_storage: [512]u8
    writer: spacetimedb.Writer = spacetimedb.WriterMake(arguments_storage[:])
    spacetimedb.WriteString(&writer, login.claims.issuer)
    spacetimedb.WriteString(&writer, config.client_id)
    request: u32 = spacetimedb.ConnectionCallReducer(connection, "set_policy", spacetimedb.WriterBytes(&writer))
    result, got := spacetimedb.ConnectionWait(connection, isResult, nil, allocator)
    reducer_result, is_result := result.(spacetimedb.ReducerResult)
    if !got || !is_result || reducer_result.request_id != request || reducer_result.outcome != .OK { return failed("the policy was not set") }
    spacetimedb.ConnectionClose(connection)
    say(fmt.tprintf("the module trusts only %s with audience %s", login.claims.issuer, config.client_id[:min(8, len(config.client_id))]))

    // anonymous: turned away
    anonymous: ^spacetimedb.Connection = new(spacetimedb.Connection)
    defer free(anonymous)
    refused: bool = !spacetimedb.ConnectionOpen(anonymous, {endpoint = server.endpoint, database = "auth"}, receive, message)
    if !refused {
        _, anonymous_greeted := spacetimedb.ConnectionWait(anonymous, isInitial, nil, allocator)
        refused = !anonymous_greeted
        spacetimedb.ConnectionClose(anonymous)
    }
    say(fmt.tprintf("an anonymous player is refused: %v", refused))

    // the person, with the real ID token of the provider
    player: ^spacetimedb.Connection = new(spacetimedb.Connection)
    defer free(player)
    player_receive := make([]u8, 1 << 16)
    player_message := make([]u8, 1 << 16)
    defer { delete(player_receive); delete(player_message) }
    opened: bool = spacetimedb.ConnectionOpen(player, {endpoint = server.endpoint, database = "auth", token = token, refresh = spacetimedb.AuthRefresh, refresh_user = session}, player_receive, player_message)
    if !opened { return failed(fmt.tprintf("the server did not accept the ID token: %s", player.error)) }
    defer spacetimedb.ConnectionClose(player)
    greeting, greeted := spacetimedb.ConnectionWait(player, isInitial, nil, allocator)
    initial, is_initial := greeting.(spacetimedb.InitialConnection)
    if !greeted || !is_initial { return failed("the server did not accept the ID token (no greeting)") }
    hex: [64]u8
    say(fmt.tprintf("let in, identity %s", spacetimedb.IdentityHex(initial.identity, hex[:])))
    sql := spacetimedb.DatabaseSql(server.endpoint, "auth", "SELECT * FROM login", token, response)
    say(fmt.tprintf("the module recorded (email hidden):\n%s", hideEmail(string(sql.body))))
    return 0
}

number :: proc(text: string, fallback: int) -> int {
    value: int
    for c in text {
        if c < '0' || c > '9' { return fallback }
        value = value * 10 + int(c - '0')
    }
    return value if value > 0 else fallback
}

isInitial :: proc(message: spacetimedb.ServerMessage, user: rawptr) -> bool {
    _, initial := message.(spacetimedb.InitialConnection)
    return initial
}

isResult :: proc(message: spacetimedb.ServerMessage, user: rawptr) -> bool {
    _, is_result := message.(spacetimedb.ReducerResult)
    return is_result
}

// The table is printed for the person who ran the tool, but it may end up in a pasted report: the address is replaced
hideEmail :: proc(text: string) -> string {
    at: int = strings.index_byte(text, '@')
    if at < 0 { return text }
    start: int = at
    for start > 0 && text[start - 1] != '"' { start -= 1 }
    end: int = at
    for end < len(text) && text[end] != '"' { end += 1 }
    return strings.concatenate({text[:start], "<email>", text[end:]}, context.temp_allocator)
}
