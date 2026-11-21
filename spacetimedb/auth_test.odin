#+build !js
package spacetimedb

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "../oidc"
import mock "../oidc/mock"

// A game that signs its players in with OpenID Connect, end to end on one computer: a provider of our own (oidc/mock), the login of the oidc library (a browser that is played by the test), a
// SpacetimeDB server that is asked to trust a token of that provider (it fetches the discovery document and the keys from the provider while the client connects), and a module (module/example/auth)
// that lets in only the issuer and audience that it was told. Skipped without the server and the module (`odin run spacetimedb/tool/setup`).

@(private = "file")
AuthPair :: struct {
    provider: ^mock.Provider,
    login: ^oidc.Login,
}

@(private = "file")
authIdle :: proc(user: rawptr) {
    pair: ^AuthPair = cast(^AuthPair)user
    mock.Step(pair.provider)
    if pair.login != nil && pair.login.state == .WAITING && !pair.login.busy { oidc.LoginPoll(pair.login) }
}

@(test)
test_a_module_lets_in_the_players_of_the_provider_it_trusts :: proc(t: ^testing.T) {
    module_path: string = FixturePath("auth-odin")
    if module_path == "" || !os.exists(ServerCliPath()) {
        fmt.println("[spacetimedb] no server or no auth module: run `odin run spacetimedb/tool/setup`")
        return
    }
    module, read_error := os.read_entire_file(module_path, context.temp_allocator)
    testing.expect(t, read_error == nil)
    root: string = "spacetimedb_test_server_auth_login"
    defer ServerRemove(root)
    server: Server
    testing.expect(t, ServerStart(&server, {root = root, port = 3190, in_memory = true}), "the server starts")
    defer ServerStop(&server)

    first_login: ^oidc.Login = new(oidc.Login)
    pair: AuthPair = {provider = new(mock.Provider), login = first_login}
    defer free(pair.provider)
    defer free(first_login)
    testing.expect(t, mock.Start(pair.provider, {algorithm = .ES256, client_id = "game", subject = "user-1", email = "a@b.c"}), "the provider starts")
    defer mock.Stop(pair.provider)
    // the waits of the client, of the login and of the server's own requests to the provider all step the provider
    oidc.HttpIdle, oidc.HttpIdleUser = authIdle, &pair
    StreamIdle, StreamIdleUser = authIdle, &pair
    defer {
        oidc.HttpIdle, oidc.HttpIdleUser = nil, nil
        StreamIdle, StreamIdleUser = nil, nil
    }
    issuer: string = mock.Issuer(pair.provider)

    // the owner publishes the module
    response := make([]u8, 8192)
    defer delete(response)
    _, token_view, made := IdentityCreate(server.endpoint, response)
    testing.expect(t, made)
    owner_token: string = strings.clone(string(token_view), context.temp_allocator)
    published: HttpResult = DatabasePublish(server.endpoint, "auth", module, owner_token, response)
    testing.expectf(t, published.ok && published.status == 200, "the module is published: %d %s", published.status, string(published.body))

    // a player signs in at the provider (the browser is played here)
    login: ^oidc.Login = pair.login
    testing.expect(t, oidc.LoginBegin(login, {issuer = issuer, client_id = "game"}), oidc.LoginError(login))
    buffer := make([]u8, 4096)
    callback := make([]u8, 4096)
    defer { delete(buffer); delete(callback) }
    first, ok := oidc.Request(oidc.LoginUrl(login), "GET", nil, nil, buffer)
    testing.expect(t, ok && first.status == 302)
    location: string = strings.clone(first.location, context.temp_allocator)
    _, _ = oidc.Request(location, "GET", nil, nil, callback)
    testing.expectf(t, login.state == .DONE, "the login: %s", oidc.LoginError(login))
    session: ^AuthSession = new(AuthSession)
    defer free(session)
    testing.expect(t, AuthSessionFrom(session, login))
    testing.expect(t, AuthToken(session) != "" && session.expires > 0)

    arena: runtime.Arena
    allocator: runtime.Allocator = runtime.arena_allocator(&arena)
    defer runtime.arena_destroy(&arena)

    // the connections and their buffers are big: on the heap
    owner := new(Connection)
    anonymous := new(Connection)
    player := new(Connection)
    stranger := new(Connection)
    defer { free(owner); free(anonymous); free(player); free(stranger) }
    receive := make([]u8, 1 << 16)
    message := make([]u8, 1 << 16)
    defer { delete(receive); delete(message) }

    // the owner connects (no policy yet: anybody may) and says who is trusted
    testing.expect(t, ConnectionOpen(owner, {endpoint = server.endpoint, database = "auth", token = owner_token}, receive, message), owner.error)
    defer ConnectionClose(owner)
    _, greeted := ConnectionWait(owner, isInitial, nil, allocator)
    testing.expect(t, greeted)
    arguments: [256]u8
    writer: Writer = WriterMake(arguments[:])
    WriteString(&writer, issuer)
    WriteString(&writer, "game")
    request: u32 = ConnectionCallReducer(owner, "set_policy", WriterBytes(&writer))
    result, result_got := ConnectionWait(owner, proc(message: ServerMessage, user: rawptr) -> bool {
        _, is_result := message.(ReducerResult)
        return is_result
    }, nil, allocator)
    reducer_result, is_result := result.(ReducerResult)
    testing.expect(t, result_got && is_result && reducer_result.request_id == request && reducer_result.outcome == .OK, "the policy is set")

    // an anonymous player (a token of the server itself) is turned away now
    opened: bool = ConnectionOpen(anonymous, {endpoint = server.endpoint, database = "auth"}, receive, message)
    refused: bool = !opened
    if opened {
        _, got := ConnectionWait(anonymous, isInitial, nil, allocator)
        refused = !got
        ConnectionClose(anonymous)
    }
    testing.expect(t, refused, "an anonymous player is refused: the issuer is not the trusted one")

    // the player of the provider gets in, with the claims of the token
    player_receive := make([]u8, 1 << 16)
    player_message := make([]u8, 1 << 16)
    defer { delete(player_receive); delete(player_message) }
    testing.expect(t, ConnectionOpen(player, {endpoint = server.endpoint, database = "auth", token = AuthToken(session), refresh = AuthRefresh, refresh_user = session}, player_receive, player_message), player.error)
    defer ConnectionClose(player)
    _, player_greeted := ConnectionWait(player, isInitial, nil, allocator)
    testing.expect(t, player_greeted, "the player of the trusted provider is let in")
    sql: HttpResult = DatabaseSql(server.endpoint, "auth", "SELECT * FROM login", AuthToken(session), response)
    text: string = string(sql.body)
    testing.expectf(t, strings.contains(text, "user-1") && strings.contains(text, issuer) && strings.contains(text, "a@b.c") && strings.contains(text, "game"), "the module recorded the claims: %s", text)

    // a token of the same provider for another application is refused by the audience
    pair.provider.options.client_id = "other-game"
    other_login: ^oidc.Login = new(oidc.Login)
    defer free(other_login)
    pair.login = other_login
    testing.expect(t, oidc.LoginBegin(other_login, {issuer = issuer, client_id = "other-game"}), oidc.LoginError(other_login))
    other_first, other_ok := oidc.Request(oidc.LoginUrl(other_login), "GET", nil, nil, buffer)
    testing.expect(t, other_ok && other_first.status == 302)
    other_location: string = strings.clone(other_first.location, context.temp_allocator)
    _, _ = oidc.Request(other_location, "GET", nil, nil, callback)
    other_session: ^AuthSession = new(AuthSession)
    defer free(other_session)
    testing.expect(t, other_login.state == .DONE && AuthSessionFrom(other_session, other_login))
    stranger_opened: bool = ConnectionOpen(stranger, {endpoint = server.endpoint, database = "auth", token = AuthToken(other_session)}, receive, message)
    stranger_refused: bool = !stranger_opened
    if stranger_opened {
        _, got := ConnectionWait(stranger, isInitial, nil, allocator)
        stranger_refused = !got
        ConnectionClose(stranger)
    }
    testing.expect(t, stranger_refused, "a token for another application is refused")
}
