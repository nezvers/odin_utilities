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
import "core:time"
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
    restoring: bool,                // SIGNING_IN is the return of a stored sign in (no browser), not a new login
    saved: [512]u8,                 // the refresh token that is in the store file now: a new one (the provider rotates) is written when it differs
    saved_length: int,
    revoked: bool,                  // the provider took the refresh token back at the last Sign out (false: offline, or no endpoint)
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
    signinKeepStored()
    switch state.phase {
    case .SIGNING_IN:
        if signin.delay > 0 {
            signin.delay -= 1
            return
        }
        if signin.restoring {
            signinRestore()
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
    signinSave()
    // a system that cannot protect a credential stores none: the person is told that the next start asks again
    if !oidc.StoreAvailable() { setStatus("Signed in. This system cannot keep a sign in safely yet, so you will sign in again next time.") }
}

signinOut :: proc() {
    if signin.account != nil {
        // signing out forgets the stored sign in of THIS account (another window may be signed in with another one: its file stays)
        if path := signinStoreFile(string(signin.account.provider[:signin.account.provider_length])); path != "" { oidc.StoreRemove(path) }
        // the provider is told too (best effort: offline it still works), so a copy of the stored token elsewhere is dead as well
        if token := signin.account.session.tokens.refresh_token; token != "" {
            signin.revoked = oidc.Revoke(&signin.account.session.metadata, signin.account.session.config, token, "refresh_token")
        }
        free(signin.account)
        signin.account = nil
    }
    signin.saved_length = 0
}

// ---- remembering the sign in between runs ------------------------------------------------------------------------------------------------------------------------
//
// The refresh token of the account goes into a file of the user (`config.signin_store`, see oidc/store.odin for what is kept and why), so that the next start signs in again without the browser.

// The file of a provider: every provider has its own, so that two windows signed in with different accounts (or one program run by two people of the computer) do not replace each other's sign in
signinStoreFile :: proc(label: string) -> string {
    if config.signin_store == "" { return "" }
    return oidc.StoreVariant(config.signin_store, label)
}

// Writes the store file for the account that is signed in (nothing when there is no store, or the provider gave no refresh token)
signinSave :: proc() {
    account: ^Account = signin.account
    if account == nil || config.signin_store == "" { return }
    token: string = account.session.tokens.refresh_token
    if token == "" { return }
    label: string = string(account.provider[:account.provider_length])
    stored: oidc.Stored = {
        provider = label,
        issuer = account.session.config.issuer,
        client_id = account.session.config.client_id,
        name = string(account.name[:account.name_length]),
        refresh_token = token,
    }
    if oidc.StoreWrite(signinStoreFile(label), stored) { signin.saved_length = copy(signin.saved[:], token) }
}

// The provider may hand out a new refresh token when the ID token is renewed (during a game, at a reconnect): the file follows, or the next start would find the old one refused
@(private = "file")
signinKeepStored :: proc() {
    account: ^Account = signin.account
    if account == nil || config.signin_store == "" { return }
    token: string = account.session.tokens.refresh_token
    if token != "" && token != string(signin.saved[:signin.saved_length]) { signinSave() }
}

// The first version kept one file for every provider (`signin.txt`): it becomes the file of its provider (when that provider is set up), and the old one is deleted
@(private = "file")
signinMigrate :: proc() {
    buffer: [oidc.STORE_MAX_SIZE]u8
    defer oidc.StoreWipe(buffer[:])
    stored, found := oidc.StoreRead(config.signin_store, buffer[:])
    if !found { return }
    for i in 0 ..< signin.provider_count {
        provider: Provider = signin.providers[i]
        if provider.label == stored.provider && provider.config.issuer == stored.issuer && provider.config.client_id == stored.client_id {
            if oidc.StoreWrite(signinStoreFile(provider.label), stored) { oidc.StoreRemove(config.signin_store) }
            return
        }
    }
}

// At the start: the stored sign in that was used LAST, of the providers that are set up, begins to be restored (no browser). Files of another provider, or of another client id, are left alone.
signinRestoreBegin :: proc() {
    if config.signin_store == "" { return }
    signinLoad()
    signinMigrate()
    best: int = -1
    best_time: time.Time
    for i in 0 ..< signin.provider_count {
        provider: Provider = signin.providers[i]
        path: string = signinStoreFile(provider.label)
        buffer: [oidc.STORE_MAX_SIZE]u8
        stored, found := oidc.StoreRead(path, buffer[:])
        matches: bool = found && stored.provider == provider.label && stored.issuer == provider.config.issuer && stored.client_id == provider.config.client_id
        oidc.StoreWipe(buffer[:])                          // the token must not stay on the stack
        if !matches { continue }
        modified, known := oidc.StoreModified(path)
        if known && (best < 0 || time.diff(best_time, modified) > 0) { best, best_time = i, modified }
    }
    if best >= 0 {
        signin.chosen, signin.restoring, signin.delay = best, true, 2
        state.phase = .SIGNING_IN
    }
}

// The restore: the provider renews the stored token. Refused (revoked, expired, ended at the provider): the file of that provider is deleted and the person is told to sign in. Not reachable: the file stays.
@(private = "file")
signinRestore :: proc() {
    signin.restoring = false
    provider: Provider = signin.providers[signin.chosen]
    path: string = signinStoreFile(provider.label)
    buffer: [oidc.STORE_MAX_SIZE]u8
    defer oidc.StoreWipe(buffer[:])                        // the token must not stay on the stack
    stored, found := oidc.StoreRead(path, buffer[:])
    if !found {
        state.phase = .MENU
        return
    }
    account: ^Account = new(Account)
    if !st.AuthSessionFromRefresh(&account.session, provider.config, stored.refresh_token) {
        reason: string = account.session.error
        free(account)
        state.phase = .MENU
        if reason == st.AUTH_UNREACHABLE {
            setStatus(fmt.tprintf("%s cannot be reached: you are not signed in for now.", provider.label))
        } else {
            oidc.StoreRemove(path)
            setStatus(fmt.tprintf("Your sign in with %s has ended: sign in again.", provider.label))
        }
        return
    }
    claims, _ := oidc.JwtClaimsRead(account.session.tokens.id_token, account.session.claims_scratch[:])
    account.provider_length = copy(account.provider[:], provider.label)
    account.subject_length = copy(account.subject[:], claims.subject)
    account.name_length = copy(account.name[:], stored.name if stored.name != "" else claims.subject)
    signin.account = account
    state.name_length = copy(state.name[:], string(account.name[:min(account.name_length, len(state.name))]))
    state.phase = .MENU
    setStatus("")
    signinSave()                                          // the provider may have replaced the refresh token
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
