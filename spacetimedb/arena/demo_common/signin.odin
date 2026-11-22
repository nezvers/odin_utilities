#+build !js
package demo_common

// Signing in with an account (Google, Discord, SpacetimeAuth ... through the `oidc` library): the start screen offers it, the player's ID token goes to the game connection, so the identity in the
// database is the one of the PERSON: the same in every game, on every computer (SpacetimeDB makes it from the issuer and the subject of the token), and the name comes from the account.
// Without signing in the identity is a new anonymous one each time (the game keeps its token in memory only). The providers are the ones of `oidc/providers/providers.local.txt` (see oidc/README.md,
// "Getting a client id"); a test or a script puts its own in `config.signin_providers`.
//
// The login runs without blocking the frame except for the steps that are requests (discovering the provider, exchanging the code): `LoginPoll` once per update. The browser page is opened and the
// address is shown too (a browser that starts cold takes seconds, or opens in another window).

import "core:fmt"
import "core:os"
import "core:strings"
import st "../.."
import "../../../oidc"

SIGNIN_PROVIDERS_MAX :: 6
SIGNIN_SETTINGS :: "oidc/providers/providers.local.txt"

// What the person can sign in with
Provider :: struct {
    label: string,                  // "Google": the button says "Sign in with Google"
    config: oidc.ClientConfig,
}

// Who is signed in: the session keeps the tokens (renewed at a reconnect), the rest is for the screens
Account :: struct {
    session: st.AuthSession,
    provider: [32]u8,
    provider_length: int,
    name: [64]u8,
    name_length: int,
    subject: [96]u8,
    subject_length: int,
}

Signin :: struct {
    providers: [SIGNIN_PROVIDERS_MAX]Provider,
    provider_count: int,
    loaded: bool,
    settings: string,               // the text of the settings file: the strings of the provider configs point into it, it stays as long as the program
    chosen: int,                    // the provider of the login in progress
    login: ^oidc.Login,
    account: ^Account,
    delay: int,                     // frames to wait before the provider is contacted, so that the screen that says so is drawn first
    message: [240]u8,               // why a sign in did not work
    message_length: int,
}

signin: Signin

// Forgets everything: the login in progress and the account (a new start of the demo)
signinReset :: proc() {
    if signin.login != nil {
        oidc.LoginCancel(signin.login)
        free(signin.login)
    }
    if signin.account != nil { free(signin.account) }
    signin = {}
}

signinMessage :: proc() -> string {
    return string(signin.message[:signin.message_length])
}

// The providers that can be offered: the ones a test or script put in `config.signin_providers`, else the ones of the settings file that have a client id
signinLoad :: proc() {
    if signin.loaded { return }
    signin.loaded = true
    if len(config.signin_providers) > 0 {
        for provider in config.signin_providers {
            if signin.provider_count < SIGNIN_PROVIDERS_MAX {
                signin.providers[signin.provider_count] = provider
                signin.provider_count += 1
            }
        }
        return
    }
    data, error := os.read_entire_file(SIGNIN_SETTINGS, context.allocator)
    if error != nil { return }
    signin.settings = string(data)
    known := [?]struct { key: string, label: string, preset: oidc.Preset }{
        {"google", "Google", .GOOGLE},
        {"discord", "Discord", .DISCORD},
        {"spacetimeauth", "SpacetimeAuth", .SPACETIMEAUTH},
    }
    for item in known {
        provider_config: oidc.ClientConfig = oidc.ClientConfigRead(signin.settings, item.key, oidc.PresetConfig(item.preset, ""))
        if provider_config.client_id == "" || strings.has_prefix(provider_config.client_id, "YOUR_") { continue }
        signin.providers[signin.provider_count] = {label = item.label, config = provider_config}
        signin.provider_count += 1
    }
}

signinFail :: proc(message: string) {
    if signin.login != nil {
        oidc.LoginCancel(signin.login)
        free(signin.login)
        signin.login = nil
    }
    signin.message_length = copy(signin.message[:], message)
    state.phase = .SIGN_IN
}

// The provider was chosen on the screen: the login begins in a moment (the screen that says "contacting" is drawn first)
signinChoose :: proc(index: int) {
    signin.chosen = index
    signin.message_length = 0
    signin.delay = 2
    state.phase = .SIGNING_IN
}

// Once an update: contacts the provider when its turn has come, and asks the login in progress whether the browser came back
signinUpdate :: proc() {
    switch state.phase {
    case .SIGNING_IN:
        if signin.delay > 0 {
            signin.delay -= 1
            return
        }
        provider: Provider = signin.providers[signin.chosen]
        signin.login = new(oidc.Login)
        if !oidc.LoginBegin(signin.login, provider.config) {
            signinFail(fmt.tprintf("%s: %s", provider.label, oidc.LoginError(signin.login)))
            return
        }
        _ = oidc.LoginOpenBrowser(signin.login)
        state.phase = .SIGN_IN_WAIT
    case .SIGN_IN_WAIT:
        login: ^oidc.Login = signin.login
        switch oidc.LoginPoll(login) {
        case .DONE: signinDone()
        case .FAILED: signinFail(oidc.LoginError(login))
        case .CANCELLED: signinFail("cancelled")
        case .IDLE, .WAITING:
        }
    case .MENU, .JOIN_FORM, .STARTING, .CONNECTING, .PLAYING, .FAILED, .SIGN_IN:
    }
}

// The login is verified: the account is kept, the name of the person is the name of the player
@(private = "file")
signinDone :: proc() {
    login: ^oidc.Login = signin.login
    account: ^Account = new(Account)
    if !st.AuthSessionFrom(&account.session, login) {
        free(account)
        signinFail("the login could not be kept")
        return
    }
    provider: Provider = signin.providers[signin.chosen]
    account.provider_length = copy(account.provider[:], provider.label)
    account.subject_length = copy(account.subject[:], login.claims.subject)
    name, found := oidc.LoginDisplayName(login)
    account.name_length = copy(account.name[:], name if found else login.claims.subject)
    if signin.account != nil { free(signin.account) }
    signin.account = account
    free(login)
    signin.login = nil
    // the name of the player: the one of the account
    state.name_length = copy(state.name[:], string(account.name[:min(account.name_length, len(state.name))]))
    state.phase = .MENU
    setStatus("")
}

signinOut :: proc() {
    if signin.account != nil {
        free(signin.account)
        signin.account = nil
    }
}

// The cancel button of the waiting screen
signinCancel :: proc() {
    if signin.login != nil {
        oidc.LoginCancel(signin.login)
        free(signin.login)
        signin.login = nil
    }
    signin.message_length = 0
    state.phase = .SIGN_IN
}

// The ID token that the game connects with, and what renews it ("" and nil when nobody is signed in: the game then takes an anonymous identity)
signinToken :: proc() -> (token: string, refresh: proc(user: rawptr) -> string, user: rawptr) {
    if signin.account == nil { return "", nil, nil }
    return st.AuthToken(&signin.account.session), st.AuthRefresh, &signin.account.session
}

signinAddress :: proc() -> string {
    if signin.login == nil { return "" }
    return oidc.LoginUrl(signin.login)
}

signinOpenBrowser :: proc() {
    if signin.login != nil { _ = oidc.LoginOpenBrowser(signin.login) }
}
