#+build !js
package demo_common

import "core:os"
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
    config.loopback = true
    state.name_length = copy(state.name[:], "player")
    signin_mock = new(mock.Provider)
    if !mock.Start(signin_mock, {algorithm = .ES256, client_id = "arena", subject = "user-arena-1", userinfo_name = "Ada Lovelace", email = "ada@example.com", rotate_refresh = true}) { return false }
    providers := make([]Provider, 2)
    providers[0] = {label = "Mock account", config = {issuer = mock.Issuer(signin_mock), client_id = "arena"}}
    providers[1] = {label = "Second account", config = {issuer = mock.Issuer(signin_mock), client_id = "arena"}}
    config.signin_providers = providers
    config.signin_store = "arena_test_signin_store/signin.txt"
    removeStores()
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
    removeStores()
    _ = os.remove("arena_test_signin_store")
    config.signin_store = ""
    return true
}

// The name of this client's player in the database
@(private = "file")
game_lib_me :: proc() -> (name: string, found: bool) {
    me, ok := game_lib.GameMe(state.game)
    if !ok { return "", false }
    return me.name, true
}

// A new start of the program: everything of the demo is forgotten except the store file, and the start screen looks at it
@(private = "file")
restart :: proc(ctx: ^kit.Context) -> bool {
    launched_address = ""
    signinReset()
    state.phase = .MENU
    setStatus("")
    signinRestoreBegin()
    return true
}

// The store file of the first account, of the second, and the old single file of the first version
@(private = "file")
storeFile :: proc() -> string { return signinStoreFile("Mock account") }
@(private = "file")
storeFileTwo :: proc() -> string { return signinStoreFile("Second account") }

@(private = "file")
removeStores :: proc() {
    oidc.StoreRemove(storeFile())
    oidc.StoreRemove(storeFileTwo())
    oidc.StoreRemove(config.signin_store)
}

// What the store file of the first account holds now
@(private = "file")
stored_token :: proc() -> (token: string, found: bool) {
    @(static) buffer: [oidc.STORE_MAX_SIZE]u8
    stored, ok := oidc.StoreRead(storeFile(), buffer[:])
    return stored.refresh_token, ok
}

@(private = "file")
writeStoreAt :: proc(path: string, label: string, issuer: string, client_id: string, token: string) -> bool {
    return oidc.StoreWrite(path, {provider = label, issuer = issuer, client_id = client_id, name = "Ada Lovelace", refresh_token = token})
}

@(private = "file")
writeStore :: proc(issuer: string, client_id: string) -> bool {
    return writeStoreAt(storeFile(), "Mock account", issuer, client_id, "stored-token")
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
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .SIGN_IN && signin.provider_count == 2 }, "Sign in lists the accounts that are set up"),
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
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        token, found := stored_token()
        data, _ := os.read_entire_file(storeFile(), context.temp_allocator)
        // what is on the disk is encrypted: no token, no name, no provider in it
        text: string = string(data)
        return found && signin.account != nil && token == signin.account.session.tokens.refresh_token && !strings.contains(text, "eyJ") && !strings.contains(text, "Ada Lovelace") && !strings.contains(text, token) && !strings.contains(text, "arena")
    }, "the sign in is remembered: it is in the store file, encrypted (no token, no name, no ID token to read)"),
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
    // the program is started again: the account comes back without the browser, and the refresh token in the file is the new one
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        before, _ := stored_token()
        @(static) previous: [512]u8
        copy(previous[:], before)
        return hooksOn(ctx) && restart(ctx) && state.phase == .SIGNING_IN && signin.account == nil
    }, "after a restart the stored sign in begins to be restored"),
    kit.Wait(40),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        token, found := stored_token()
        return state.phase == .MENU && signin.account != nil && launched_address == "" && string(state.name[:state.name_length]) == "Ada Lovelace" && found && token == signin.account.session.tokens.refresh_token
    }, "the account is back with its name, no browser was opened, the file has the rotated token"),
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
    kit.Check(proc(ctx: ^kit.Context) -> bool { if !oidc.StoreAvailable() { return true }; return !os.exists(storeFile()) && restart(ctx) && state.phase == .MENU && signin.account == nil }, "Sign out deletes the store file: a restart restores nothing"),
    // an anonymous game: not the identity of the account
    kit.Check(hooksOn, "the provider is stepped again"),
    kit.Check(aimPlaySolo, "the start screen has Play solo"),
    kit.ClickAt(&target),
    kit.Wait(1400),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return playsSolo(ctx) && state.game.connection.identity != first_identity }, "without an account the identity is another one"),
    kit.Tap(.ESCAPE),
    kit.Wait(10),
    // the session was ended at the provider: the stored sign in is refused, the file is deleted and the person is told
    kit.Check(hooksOn, "the provider is stepped again"),
    kit.Check(aimSignIn, "the start screen has Sign in"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(aimMockAccount, "the account is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(30),
    kit.Check(playBrowser, "the browser signs in again"),
    kit.Wait(40),
    kit.Check(proc(ctx: ^kit.Context) -> bool { if !oidc.StoreAvailable() { return true }; _, found := stored_token(); return signin.account != nil && found }, "signed in again, and remembered"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { if !oidc.StoreAvailable() { return true }; mock.RevokeRefreshTokens(signin_mock); return restart(ctx) && state.phase == .SIGNING_IN }, "the provider ended the session, the program is started again"),
    kit.Wait(40),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        _, found := stored_token()
        return state.phase == .MENU && signin.account == nil && !found && strings.contains(string(state.status[:state.status_length]), "has ended")
    }, "the refused sign in is not restored, the file is deleted, the person is told to sign in"),
    // a provider that cannot be reached (offline): the file stays, the person is told
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        signinLoad()
        signin.providers[0].config.issuer = "http://127.0.0.1:9"
        launched_address = ""
        state.phase = .MENU
        if !writeStore("http://127.0.0.1:9", "arena") { return false }
        signinRestoreBegin()
        return state.phase == .SIGNING_IN
    }, "a stored sign in of a provider that cannot be reached begins to be restored"),
    kit.Wait(40),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        _, found := stored_token()
        return state.phase == .MENU && signin.account == nil && found && strings.contains(string(state.status[:state.status_length]), "cannot be reached")
    }, "offline is not the end of the sign in: the file stays and the person is told"),
    // a file of another client id, or one that is not a store: nothing is restored and the file is not touched by the restore
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        restart(ctx)
        signinLoad()
        if !writeStore(signin.providers[0].config.issuer, "somebody-else") { return false }
        signinRestoreBegin()
        return state.phase == .MENU && signin.account == nil && os.exists(storeFile())
    }, "a stored sign in of another client id is left alone"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        restart(ctx)
        _ = os.write_entire_file(storeFile(), "junk that is not a store")
        signinRestoreBegin()
        return state.phase == .MENU && signin.account == nil
    }, "a file that is not a store restores nothing"),
    // two windows with two accounts: every provider has its own file, the one used last is restored at the start, and what one does to its file does not touch the other's
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        removeStores()
        restart(ctx)
        issuer: string = signin.providers[0].config.issuer
        return writeStoreAt(storeFile(), "Mock account", issuer, "arena", "token-one")
    }, "the first account has its file"),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        return writeStoreAt(storeFileTwo(), "Second account", signin.providers[0].config.issuer, "arena", "token-two")
    }, "the second account, signed in later, has another file"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        if !os.exists(storeFile()) || !os.exists(storeFileTwo()) { return false }
        restart(ctx)
        return state.phase == .SIGNING_IN && signin.chosen == 1
    }, "both files are there and the account that was used last is the one that is restored"),
    kit.Wait(40),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        // the stored token of the second account is not one of the provider (it was made up): refused, so ONLY its file is deleted
        return state.phase == .MENU && signin.account == nil && !os.exists(storeFileTwo()) && os.exists(storeFile()) && strings.contains(string(state.status[:state.status_length]), "Second account")
    }, "a refused sign in deletes the file of its own provider only"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        restart(ctx)
        return state.phase == .SIGNING_IN && signin.chosen == 0
    }, "the other account is what is restored next"),
    kit.Wait(40),
    // the single file of the first version becomes the file of its provider
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        removeStores()
        return state.phase == .MENU && writeStoreAt(config.signin_store, "Mock account", signin.providers[0].config.issuer, "arena", "old-single-file-token")
    }, "an old single file exists"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        if !oidc.StoreAvailable() { return true }
        restart(ctx)
        // it is moved to the file of its provider (same token) and the old file is gone
        token, found := stored_token()
        return state.phase == .SIGNING_IN && found && token == "old-single-file-token" && !os.exists(config.signin_store)
    }, "the old file is moved to the file of its provider"),
    kit.Wait(40),
    kit.Check(proc(ctx: ^kit.Context) -> bool { removeStores(); return true }, "the stores are emptied"),
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
