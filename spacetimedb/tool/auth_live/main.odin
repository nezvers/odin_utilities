package main

// A real person's ID token (Google, Discord, SpacetimeAuth ...) against a real local SpacetimeDB server and the `auth` example module:
//
//     odin run spacetimedb/tool/auth_live -- google|discord|spacetimeauth [--no-browser]
//
// The settings are the ones of oidc/providers/providers.local.txt. The tool starts a throw away server (in memory, port 3191), publishes module/example/auth (`odin run spacetimedb/tool/setup` builds it),
// logs you in at the provider (the browser flow, like oidc/tool/login), tells the module to trust only that issuer and your client id, connects with the ID token and shows what the module recorded.
// The server fetches the provider's discovery document and keys itself, over the internet: that is the part the tests with the mock provider cannot show.

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "../.."
import oidc "../../../oidc"

PORT :: 3191

main :: proc() {
    name: string
    open_browser: bool = true
    for i := 1; i < len(os.args); i += 1 {
        if os.args[i] == "--no-browser" { open_browser = false } else { name = os.args[i] }
    }
    preset: oidc.Preset
    switch name {
    case "google": preset = .GOOGLE
    case "discord": preset = .DISCORD
    case "spacetimeauth": preset = .SPACETIMEAUTH
    case:
        fmt.eprintln("usage: odin run spacetimedb/tool/auth_live -- google|discord|spacetimeauth [--no-browser]")
        os.exit(2)
    }
    settings, read_error := os.read_entire_file("oidc/providers/providers.local.txt", context.allocator)
    if read_error != nil {
        fmt.eprintln("no oidc/providers/providers.local.txt: see oidc/README.md (Getting a client id)")
        os.exit(2)
    }
    config: oidc.ClientConfig = oidc.ClientConfigRead(string(settings), name, oidc.PresetConfig(preset, ""))
    if config.client_id == "" || strings.has_prefix(config.client_id, "YOUR_") {
        fmt.eprintfln("%s.client_id is not set", name)
        os.exit(2)
    }
    module_path: string = spacetimedb.FixturePath("auth-odin")
    if module_path == "" || !os.exists(spacetimedb.ServerCliPath()) {
        fmt.eprintln("no server or no auth module: run `odin run spacetimedb/tool/setup`")
        os.exit(2)
    }
    module, module_error := os.read_entire_file(module_path, context.allocator)
    if module_error != nil { fail("cannot read the module") }

    root: string = "auth_live_server"
    defer spacetimedb.ServerRemove(root)
    server: ^spacetimedb.Server = new(spacetimedb.Server)
    if !spacetimedb.ServerStart(server, {root = root, port = PORT, in_memory = true}) { fail("the server does not start") }
    defer spacetimedb.ServerStop(server)
    fmt.printfln("server up on port %d", PORT)

    response := make([]u8, 16384)
    _, owner_token, made := spacetimedb.IdentityCreate(server.endpoint, response)
    if !made { fail("no identity for the owner") }
    owner: string = strings.clone(owner_token)
    published := spacetimedb.DatabasePublish(server.endpoint, "auth", module, owner, response)
    if !published.ok || published.status != 200 { fail(fmt.tprintf("publish: %d %s", published.status, string(published.body))) }
    fmt.println("module published")

    // the login of the person at the provider
    login: ^oidc.Login = new(oidc.Login)
    if !oidc.LoginBegin(login, config) { fail(fmt.tprintf("login: %s", oidc.LoginError(login))) }
    if open_browser && oidc.LoginOpenBrowser(login) {
        fmt.println("the browser was opened; log in there")
    } else {
        fmt.printfln("open this address in a browser:\n%s", oidc.LoginUrl(login))
    }
    started: time.Tick = time.tick_now()
    for oidc.LoginPoll(login) == .WAITING {
        if time.duration_seconds(time.tick_since(started)) > 300 { fail("no answer in five minutes") }
        time.sleep(50 * time.Millisecond)
    }
    if login.state != .DONE { fail(fmt.tprintf("login failed: %s", oidc.LoginError(login))) }
    fmt.printfln("login ok: %s, subject %s", login.claims.issuer, login.claims.subject)
    session: ^spacetimedb.AuthSession = new(spacetimedb.AuthSession)
    if !spacetimedb.AuthSessionFrom(session, login) { fail("the session does not fit") }
    token: string = spacetimedb.AuthToken(session)

    arena: runtime.Arena
    allocator: runtime.Allocator = runtime.arena_allocator(&arena)
    receive := make([]u8, 1 << 16)
    message := make([]u8, 1 << 16)
    connection: ^spacetimedb.Connection = new(spacetimedb.Connection)

    // the owner says who is trusted: this issuer and this client id
    if !spacetimedb.ConnectionOpen(connection, {endpoint = server.endpoint, database = "auth", token = owner}, receive, message) { fail(connection.error) }
    if _, greeted := spacetimedb.ConnectionWait(connection, isInitial, nil, allocator); !greeted { fail("the owner is not greeted") }
    arguments: [512]u8
    writer: spacetimedb.Writer = spacetimedb.WriterMake(arguments[:])
    spacetimedb.WriteString(&writer, login.claims.issuer)
    spacetimedb.WriteString(&writer, config.client_id)
    request: u32 = spacetimedb.ConnectionCallReducer(connection, "set_policy", spacetimedb.WriterBytes(&writer))
    result, got := spacetimedb.ConnectionWait(connection, isResult, nil, allocator)
    reducer_result, is_result := result.(spacetimedb.ReducerResult)
    if !got || !is_result || reducer_result.request_id != request || reducer_result.outcome != .OK { fail("the policy was not set") }
    spacetimedb.ConnectionClose(connection)
    fmt.printfln("the module trusts only %s with audience %s", login.claims.issuer, config.client_id[:min(8, len(config.client_id))])

    // anonymous: turned away
    anonymous: ^spacetimedb.Connection = new(spacetimedb.Connection)
    refused: bool = !spacetimedb.ConnectionOpen(anonymous, {endpoint = server.endpoint, database = "auth"}, receive, message)
    if !refused {
        _, greeted := spacetimedb.ConnectionWait(anonymous, isInitial, nil, allocator)
        refused = !greeted
        spacetimedb.ConnectionClose(anonymous)
    }
    fmt.printfln("an anonymous player is refused: %v", refused)

    // the person, with the real ID token of the provider
    player: ^spacetimedb.Connection = new(spacetimedb.Connection)
    player_receive := make([]u8, 1 << 16)
    player_message := make([]u8, 1 << 16)
    opened: bool = spacetimedb.ConnectionOpen(player, {endpoint = server.endpoint, database = "auth", token = token, refresh = spacetimedb.AuthRefresh, refresh_user = session}, player_receive, player_message)
    if !opened { fail(fmt.tprintf("the server did not accept the ID token: %s", player.error)) }
    greeting, greeted := spacetimedb.ConnectionWait(player, isInitial, nil, allocator)
    initial, is_initial := greeting.(spacetimedb.InitialConnection)
    if !greeted || !is_initial { fail("the server did not accept the ID token (no greeting)") }
    hex: [64]u8
    fmt.printfln("let in, identity %s", spacetimedb.IdentityHex(initial.identity, hex[:]))
    sql := spacetimedb.DatabaseSql(server.endpoint, "auth", "SELECT * FROM login", token, response)
    fmt.printfln("the module recorded (email hidden):\n%s", hideEmail(string(sql.body)))
    spacetimedb.ConnectionClose(player)
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

fail :: proc(reason: string) {
    fmt.eprintln(reason)
    os.exit(1)
}
