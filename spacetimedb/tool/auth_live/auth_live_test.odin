package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "../.."
import oidc "../../../oidc"
import mock "../../../oidc/mock"

// The tool against a real local SpacetimeDB server, the `auth` module and the mock provider: `run` as a person would run it, with the browser played by an idle hook. The server fetches the discovery
// document and the keys of the mock itself, so the provider has to be stepped while the server and the client wait. Skipped (and said) without the server and the module: `odin run spacetimedb/tool/setup`.
// The tests set globals of the tool and of the libraries: they take a lock.

@(private = "file")
tests_lock: sync.Mutex

@(private = "file")
Player :: struct {
    provider: ^mock.Provider,
    play: bool,
    played: bool,
}

@(private = "file")
player: Player

// The waits of the clients (HTTP of oidc, the stream of spacetimedb) step the provider, and the login of the tool
@(private = "file")
stepIdle :: proc(user: rawptr) {
    mock.Step(player.provider)
    if current_login != nil && current_login.state == .WAITING && !current_login.busy { oidc.LoginPoll(current_login) }
}

@(private = "file")
idle :: proc(login: ^oidc.Login) {
    mock.Step(player.provider)
    if player.play && !player.played && oidc.LoginUrl(login) != "" {
        player.played = true
        buffer := make([]u8, 4096)
        callback := make([]u8, 4096)
        defer { delete(buffer); delete(callback) }
        first, ok := oidc.Request(oidc.LoginUrl(login), "GET", nil, nil, buffer)
        if !ok || first.location == "" { return }
        location: string = strings.clone(first.location, context.temp_allocator)
        _, _ = oidc.Request(location, "GET", nil, nil, callback)
    }
}

@(private = "file")
available :: proc() -> bool {
    if spacetimedb.FixturePath("auth-odin") == "" || !os.exists(spacetimedb.ServerCliPath()) {
        fmt.println("[auth_live] no server or no auth module: run `odin run spacetimedb/tool/setup`")
        return false
    }
    return true
}

@(private = "file")
runTool :: proc(options: mock.Options, fault: mock.Fault, port: int, extra: []string, play: bool, output: ^strings.Builder) -> int {
    provider := new(mock.Provider)
    defer free(provider)
    if !mock.Start(provider, options) { return -1 }
    defer mock.Stop(provider)
    provider.fault = fault
    player = {provider = provider, play = play}
    oidc.HttpIdle, oidc.HttpIdleUser = stepIdle, nil
    spacetimedb.StreamIdle, spacetimedb.StreamIdleUser = stepIdle, nil
    Idle = idle
    capture = output
    defer {
        oidc.HttpIdle, oidc.HttpIdleUser = nil, nil
        spacetimedb.StreamIdle, spacetimedb.StreamIdleUser = nil, nil
        Idle, capture = nil, nil
    }
    file: string = fmt.tprintf("auth_live_test_%d.txt", port)
    _ = os.write_entire_file(file, fmt.tprintf("google.client_id = %s\n", options.client_id))
    defer _ = os.remove(file)
    arguments: [dynamic]string
    arguments.allocator = context.temp_allocator
    append(&arguments, "google", "--no-browser", "--file", file, "--issuer", mock.Issuer(provider), "--port", fmt.tprintf("%d", port), "--timeout", "20")
    append(&arguments, ..extra)
    return run(arguments[:])
}

@(test)
test_a_person_with_a_token_of_the_provider_gets_into_the_module :: proc(t: ^testing.T) {
    if !available() { return }
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    code: int = runTool({algorithm = .ES256, client_id = "game", subject = "user-1", email = "a@b.c"}, .NONE, 3192, nil, true, &output)
    text: string = strings.to_string(output)
    testing.expectf(t, code == 0, "exit code %d: %s", code, text)
    for part in ([]string{"server up on port 3192", "module published", "open this address in a browser:", "login ok: http://127.0.0.1:", ", subject user-1", "the module trusts only http://127.0.0.1:",
        "an anonymous player is refused: true", "let in, identity ", "the module recorded (email hidden):", "user-1", "game", "<email>"}) {
        testing.expectf(t, strings.contains(text, part), "the output has %q: %s", part, text)
    }
    testing.expect(t, !strings.contains(text, "a@b.c"), "the email address is hidden")
    testing.expect(t, !strings.contains(text, "eyJ"), "no token in the output")
    // the throw away server is gone and its folder removed
    testing.expect(t, !spacetimedb.ServerPing({host = "127.0.0.1", port = 3192}), "the server was stopped")
    testing.expect(t, !os.exists("auth_live_server_3192"), "its folder was removed")
}

@(test)
test_a_token_for_another_application_never_reaches_the_server :: proc(t: ^testing.T) {
    if !available() { return }
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    code: int = runTool({algorithm = .RS256, client_id = "game", subject = "user-1"}, .WRONG_AUDIENCE, 3193, nil, true, &output)
    text: string = strings.to_string(output)
    testing.expect_value(t, code, 1)
    testing.expectf(t, strings.contains(text, "login failed"), "the login is refused by the client: %s", text)
    testing.expect(t, !strings.contains(text, "let in"), "nobody is let in")
    testing.expect(t, !spacetimedb.ServerPing({host = "127.0.0.1", port = 3193}), "the server was stopped also after a failure")
}

@(test)
test_a_login_nobody_answers_ends_and_stops_the_server :: proc(t: ^testing.T) {
    if !available() { return }
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    code: int = runTool({algorithm = .ES256, client_id = "game", subject = "user-1"}, .NONE, 3194, {"--timeout", "1"}, false, &output)
    text: string = strings.to_string(output)
    testing.expect_value(t, code, 1)
    testing.expectf(t, strings.contains(text, "no answer in time"), "the wait ended: %s", text)
    testing.expect(t, !spacetimedb.ServerPing({host = "127.0.0.1", port = 3194}), "the server was stopped")
}

@(test)
test_usage_and_settings_errors_end_with_code_2 :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    capture = &output
    defer capture = nil
    _ = os.write_entire_file("auth_live_test_placeholder.txt", "google.client_id = YOUR_ID.apps.googleusercontent.com\n")
    defer _ = os.remove("auth_live_test_placeholder.txt")

    testing.expect_value(t, run({}), 2)
    testing.expect(t, strings.contains(strings.to_string(output), "usage"))
    strings.builder_reset(&output)
    testing.expect_value(t, run({"github"}), 2)       // GitHub has no ID token: this tool is for the OpenID Connect providers
    testing.expect(t, strings.contains(strings.to_string(output), "usage"))
    strings.builder_reset(&output)
    testing.expect_value(t, run({"google", "--file", "auth_live_test_does_not_exist.txt"}), 2)
    testing.expect(t, strings.contains(strings.to_string(output), "providers.local.txt"))
    strings.builder_reset(&output)
    testing.expect_value(t, run({"google", "--file", "auth_live_test_placeholder.txt"}), 2)
    testing.expect(t, strings.contains(strings.to_string(output), "google.client_id is not set"))
}

@(test)
test_the_email_is_hidden_and_the_rest_is_kept :: proc(t: ^testing.T) {
    testing.expect_value(t, hideEmail(`[["x","a@b.c","y"]]`), `[["x","<email>","y"]]`)
    testing.expect_value(t, hideEmail(`no address here`), `no address here`)
    testing.expect_value(t, hideEmail(`"first.last+tag@example.com"`), `"<email>"`)
    testing.expect_value(t, hideEmail(``), ``)
}

@(test)
test_numbers_of_the_arguments :: proc(t: ^testing.T) {
    testing.expect_value(t, number("3192", 1), 3192)
    testing.expect_value(t, number("31x2", 7), 7)
    testing.expect_value(t, number("", 7), 7)
    testing.expect_value(t, number("0", 7), 7)
}
