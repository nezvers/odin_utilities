#+build !js
package demo_common

import "core:strings"
import kit "../../../demo_kit"
import st "../.."
import game_lib "../game"
import "../../../oidc"
import mock "../../../oidc/mock"

// The test of signing in: a provider of our own (oidc/mock, an OpenID Connect provider in this process), the browser played by the script, a real SpacetimeDB server that fetches the keys of the
// provider while the game connects. The player signs in, the name of the account becomes the name of the player, and two solo games (two servers) give the SAME identity: the identity of the
// person, which an anonymous player never has. Then Sign out. The real browser is never started (`oidc.BrowserLauncher` is replaced) and the pictures hold no address that changes (masked).

aimSignIn :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "menu", "Sign in") }
aimSignOut :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "menu", "Sign out") }
aimMockAccount :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "signin", "Sign in with Mock account") }
aimSignInWaitCancel :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "signin_wait", "Cancel") }

@(private = "file")
signin_mock: ^mock.Provider

@(private = "file")
launched_address: string

@(private = "file")
first_identity: st.Identity

// The waits of the clients step the provider (and the login that waits for the browser): the server asks the provider for its keys while the game connects
@(private = "file")
stepProvider :: proc(user: rawptr) {
    if signin_mock != nil { mock.Step(signin_mock) }
    if signin.login != nil && signin.login.state == .WAITING && !signin.login.busy { oidc.LoginPoll(signin.login) }
}

// Leaving a game (`session.ClearIdle`) also removes the hook of the stream: the provider has to be stepped again before the next game, or the server waits for the keys in vain
@(private = "file")
hooksOn :: proc(ctx: ^kit.Context) -> bool {
    oidc.HttpIdle, oidc.HttpIdleUser = stepProvider, nil
    st.StreamIdle, st.StreamIdleUser = stepProvider, nil
    return true
}

@(private = "file")
startProvider :: proc(ctx: ^kit.Context) -> bool {
    config.mask_codes, config.loopback = true, true
    state.name_length = copy(state.name[:], "player")
    signin_mock = new(mock.Provider)
    if !mock.Start(signin_mock, {algorithm = .ES256, client_id = "arena", subject = "user-arena-1", userinfo_name = "Ada Lovelace", email = "ada@example.com"}) { return false }
    providers := make([]Provider, 1)
    providers[0] = {label = "Mock account", config = {issuer = mock.Issuer(signin_mock), client_id = "arena"}}
    config.signin_providers = providers
    oidc.HttpIdle, oidc.HttpIdleUser = stepProvider, nil
    st.StreamIdle, st.StreamIdleUser = stepProvider, nil
    // no real browser: the opener only remembers the address
    oidc.BrowserLauncher = proc(command: []string) -> bool {
        launched_address = strings.clone(command[len(command) - 1])
        return true
    }
    return true
}

// What the browser does: open the address of the login, follow the redirect of the provider back to the program
@(private = "file")
playBrowser :: proc(ctx: ^kit.Context) -> bool {
    address: string = signinAddress()
    if address == "" { return false }
    buffer := make([]u8, 4096)
    callback := make([]u8, 4096)
    defer { delete(buffer); delete(callback) }
    first, ok := oidc.Request(address, "GET", nil, nil, buffer)
    if !ok || first.location == "" { return false }
    location: string = strings.clone(first.location, context.temp_allocator)
    _, _ = oidc.Request(location, "GET", nil, nil, callback)
    return true
}

@(private = "file")
stopProvider :: proc(ctx: ^kit.Context) -> bool {
    oidc.HttpIdle, oidc.HttpIdleUser = nil, nil
    st.StreamIdle, st.StreamIdleUser = nil, nil
    oidc.BrowserLauncher = nil
    oidc.BrowserShortcutRemove(launched_address)          // on Windows a long address goes through a shortcut file
    if signin_mock != nil {
        mock.Stop(signin_mock)
        free(signin_mock)
        signin_mock = nil
    }
    config.signin_providers = nil
    return true
}

// The name of this client's player in the database
@(private = "file")
game_lib_me :: proc() -> (name: string, found: bool) {
    me, ok := game_lib.GameMe(state.game)
    if !ok { return "", false }
    return me.name, true
}

@(private = "file")
playsSolo :: proc(ctx: ^kit.Context) -> bool {
    return state.phase == .PLAYING && state.game != nil && state.game.phase == .PLAYING && state.game.player_count == 1 && state.game.coin_count > 0
}

signin_script: []kit.Step = {
    kit.Wait(4),
    kit.Check(startProvider, "a provider of our own is running and the browser is not the real one"),
    kit.Check(aimSignIn, "the start screen has Sign in"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .SIGN_IN && signin.provider_count == 1 }, "Sign in lists the accounts that are set up"),
    kit.Wait(15),
    kit.Capture("signin_providers"),
    kit.Wait(1),
    kit.Check(aimMockAccount, "the account of the provider is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(30),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .SIGN_IN_WAIT && launched_address != "" && strings.contains(signinAddress(), "code_challenge_method=S256") }, "the provider was contacted and the page was opened (not by a real browser)"),
    kit.Wait(15),
    kit.Capture("signin_waiting"),
    kit.Wait(1),
    kit.Check(playBrowser, "the browser signs in at the provider and comes back"),
    kit.Wait(40),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return state.phase == .MENU && signin.account != nil && string(state.name[:state.name_length]) == "Ada Lovelace" && signin.account.subject_length > 0
    }, "the ID token is verified, the account is kept and its name is the name of the player"),
    kit.Wait(15),
    kit.Capture("signed_in"),
    kit.Wait(1),
    // the first game: the identity of the account
    kit.Check(aimPlaySolo, "the start screen has Play solo"),
    kit.ClickAt(&target),
    kit.Wait(1400),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !playsSolo(ctx) { return false }
        first_identity = state.game.connection.identity
        me, found := game_lib_me()
        return found && first_identity != st.Identity{} && me == "Ada Lovelace"
    }, "the server accepted the ID token and the player is Ada Lovelace"),
    kit.Tap(.ESCAPE),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .MENU && signin.account != nil }, "Escape leaves the game and the account stays"),
    // the second game, on a new server: the same identity (an anonymous player gets a new one every time)
    kit.Check(hooksOn, "the provider is stepped again"),
    kit.Check(aimPlaySolo, "the start screen has Play solo again"),
    kit.ClickAt(&target),
    kit.Wait(1400),
    kit.Check(playsSolo, "the second game started on a new server"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        return state.game != nil && state.game.connection.identity == first_identity
    }, "and it has the same identity: it is the identity of the person"),
    kit.Tap(.ESCAPE),
    kit.Wait(10),
    kit.Check(aimSignOut, "the start screen has Sign out"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return signin.account == nil && aimSignIn(ctx) }, "Sign out forgets the account"),
    // an anonymous game: not the identity of the account
    kit.Check(hooksOn, "the provider is stepped again"),
    kit.Check(aimPlaySolo, "the start screen has Play solo"),
    kit.ClickAt(&target),
    kit.Wait(1400),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return playsSolo(ctx) && state.game.connection.identity != first_identity }, "without an account the identity is another one"),
    kit.Tap(.ESCAPE),
    kit.Wait(10),
    // a login that is cancelled
    kit.Check(aimSignIn, "the start screen has Sign in"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(aimMockAccount, "the account is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(30),
    kit.Check(aimSignInWaitCancel, "the waiting screen has Cancel"),
    kit.ClickAt(&target),
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .SIGN_IN && signin.login == nil && signin.account == nil }, "Cancel stops the login and shows the accounts again"),
    kit.Check(stopProvider, "the provider is stopped"),
}
