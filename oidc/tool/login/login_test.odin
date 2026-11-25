package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import oidc "../.."
import mock "../../mock"

// The tool against the mock provider of oidc/mock: the whole of `run` (the settings file, the address it prints, the wait, the checks, what it prints about the person), with the browser played by an
// idle hook. The tests set globals of the tool and of the oidc library: they take a lock.

@(private = "file")
tests_lock: sync.Mutex

@(private = "file")
Player :: struct {
    provider: ^mock.Provider,
    play: bool,                 // does the "browser" open the address (false: nobody answers)
    played: bool,
}

@(private = "file")
player: Player

// The waits of the HTTP client of the oidc library step the provider, and the login of the tool (the browser's request to the loopback address is answered by it)
@(private = "file")
httpIdle :: proc(user: rawptr) {
    mock.Step(player.provider)
    if current_login != nil && current_login.state == .WAITING && !current_login.busy { oidc.LoginPoll(current_login) }
}

// What the browser does: open the login page and follow its redirect back to the program
@(private = "file")
browser :: proc(login: ^oidc.Login) {
    buffer := make([]u8, 4096)
    callback := make([]u8, 4096)
    defer { delete(buffer); delete(callback) }
    first, ok := oidc.Request(oidc.LoginUrl(login), "GET", nil, nil, buffer)
    if !ok || first.location == "" { return }
    location: string = strings.clone(first.location, context.temp_allocator)
    _, _ = oidc.Request(location, "GET", nil, nil, callback)
}

@(private = "file")
idle :: proc(login: ^oidc.Login) {
    mock.Step(player.provider)
    if login != nil && player.play && !player.played && oidc.LoginUrl(login) != "" {
        player.played = true
        browser(login)
    }
}

// Starts a provider and the hooks, runs the tool with a settings file that names `provider_name`, returns the exit code and what the tool said
@(private = "file")
runTool :: proc(options: mock.Options, fault: mock.Fault, provider_name: string, extra: []string, play: bool, output: ^strings.Builder, more_settings: string = "", browser: bool = false) -> int {
    provider := new(mock.Provider)
    defer free(provider)
    if !mock.Start(provider, options) { return -1 }
    defer mock.Stop(provider)
    provider.fault = fault
    player = {provider = provider, play = play}
    oidc.HttpIdle, oidc.HttpIdleUser = httpIdle, nil
    Idle = idle
    capture = output
    defer {
        oidc.HttpIdle, oidc.HttpIdleUser = nil, nil
        Idle, capture = nil, nil
    }
    file: string = fmt.tprintf("login_tool_test_%s.txt", provider_name)
    _ = os.write_entire_file(file, fmt.tprintf("%s.client_id = %s\n%s", provider_name, options.client_id, more_settings))
    defer _ = os.remove(file)
    arguments: [dynamic]string
    arguments.allocator = context.temp_allocator
    append(&arguments, provider_name)
    if !browser { append(&arguments, "--no-browser") }
    append(&arguments, "--file", file, "--issuer", mock.Issuer(provider), "--timeout", "20")
    append(&arguments, ..extra)
    return run(arguments[:])
}

@(test)
test_a_browser_login_prints_the_verified_claims :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    code: int = runTool({algorithm = .ES256, client_id = "game", subject = "user-1", email = "a@b.c"}, .NONE, "google", nil, true, &output)
    text: string = strings.to_string(output)
    testing.expect_value(t, code, 0)
    for part in ([]string{"google: client id game...", "redirect address to register at the provider: http://127.0.0.1:", "/callback", "open this address in a browser:", "login ok", "subject  user-1",
        "audience is the client id: true", "email    a@b.c", "refresh works: true", "userinfo:"}) {
        testing.expectf(t, strings.contains(text, part), "the output has %q: %s", part, text)
    }
    // nothing secret is printed: no JWT (they start with eyJ), no access or refresh token
    testing.expect(t, !strings.contains(text, "eyJ"), "no ID token in the output")
    testing.expect(t, !strings.contains(text, "access-"), "no access token in the output")
}

@(test)
test_a_token_for_another_application_ends_the_login :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    code: int = runTool({algorithm = .RS256, client_id = "game", subject = "user-1"}, .WRONG_AUDIENCE, "discord", nil, true, &output)
    text: string = strings.to_string(output)
    testing.expect_value(t, code, 1)
    testing.expectf(t, strings.contains(text, "login failed"), "it says so: %s", text)
    testing.expect(t, !strings.contains(text, "login ok"), "no success is claimed")
}

@(test)
test_a_provider_that_wants_the_secret_for_a_refresh :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    code: int = runTool({algorithm = .RS256, client_id = "game", subject = "user-1", refresh_secret = "s3cret"}, .NONE, "discord", nil, true, &output)
    text: string = strings.to_string(output)
    testing.expect_value(t, code, 0)
    testing.expectf(t, strings.contains(text, "refresh works: false") && strings.contains(text, "refresh answer: invalid_client"), "the refusal is shown: %s", text)
    testing.expectf(t, strings.contains(text, "client_secret") && strings.contains(text, "git ignored"), "and what to do about it: %s", text)

    // with the secret in the settings file the refresh works, and the hint is not shown
    strings.builder_reset(&output)
    code = runTool({algorithm = .RS256, client_id = "game", subject = "user-1", refresh_secret = "s3cret"}, .NONE, "discord", nil, true, &output, "discord.client_secret = s3cret\n")
    text = strings.to_string(output)
    testing.expect_value(t, code, 0)
    testing.expectf(t, strings.contains(text, "refresh works: true") && !strings.contains(text, "refresh answer"), "the secret of the file is used: %s", text)
    testing.expect(t, !strings.contains(text, "s3cret"), "the secret is never printed")
}

// SpacetimeAuth: a client registered as public refuses a secret; the login works without it and the tool tells the person that the secret in the settings is not needed
@(test)
test_a_secret_for_a_public_client_is_reported :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    code: int = runTool({algorithm = .ES256, client_id = "game", subject = "user-1", client_auth = .PUBLIC}, .NONE, "spacetimeauth", nil, true, &output, "spacetimeauth.client_secret = not-needed\n")
    text: string = strings.to_string(output)
    testing.expect_value(t, code, 0)
    testing.expectf(t, strings.contains(text, "login ok") && strings.contains(text, "WITHOUT it") && strings.contains(text, "Delete client_secret"), "the login works and the person is told: %s", text)
    testing.expect(t, !strings.contains(text, "not-needed"), "the secret is never printed")

    // a client that takes the secret: Basic, said so
    strings.builder_reset(&output)
    code = runTool({algorithm = .ES256, client_id = "game", subject = "user-1", client_secret = "s3", client_auth = .BASIC_ONLY}, .NONE, "spacetimeauth", nil, true, &output, "spacetimeauth.client_secret = s3\n")
    text = strings.to_string(output)
    testing.expect_value(t, code, 0)
    testing.expectf(t, strings.contains(text, "HTTP Basic") && !strings.contains(text, "WITHOUT it"), "Basic: %s", text)

    // no secret in the settings: said so
    strings.builder_reset(&output)
    code = runTool({algorithm = .ES256, client_id = "game", subject = "user-1"}, .NONE, "spacetimeauth", nil, true, &output)
    text = strings.to_string(output)
    testing.expect_value(t, code, 0)
    testing.expectf(t, strings.contains(text, "none (a public client"), "no secret: %s", text)
}

@(test)
test_the_name_comes_from_the_user_info_when_the_token_has_none :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    code: int = runTool({algorithm = .RS256, client_id = "game", subject = "user-1", userinfo_name = "Ada Lovelace"}, .NONE, "discord", nil, true, &output)
    text: string = strings.to_string(output)
    testing.expect_value(t, code, 0)
    testing.expectf(t, strings.contains(text, "name     Ada Lovelace"), "the name of the user info is shown: %s", text)
}

@(test)
test_a_login_nobody_answers_times_out :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    code: int = runTool({algorithm = .ES256, client_id = "game", subject = "user-1"}, .NONE, "google", {"--timeout", "1"}, false, &output)
    text: string = strings.to_string(output)
    testing.expect_value(t, code, 1)
    testing.expectf(t, strings.contains(text, "no answer in time") && strings.contains(text, "open this address"), "the address was shown and the wait ended: %s", text)
}

@(test)
test_the_github_device_flow :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    code: int = runTool({algorithm = .ES256, client_id = "game", subject = "user-9"}, .NONE, "github", nil, false, &output)
    text: string = strings.to_string(output)
    testing.expect_value(t, code, 0)
    for part in ([]string{"WDJB-MJHT", "login ok (GitHub gives an access token, not an ID token)", "sub      user-9"}) {
        testing.expectf(t, strings.contains(text, part), "the output has %q: %s", part, text)
    }
    testing.expect(t, !strings.contains(text, "access-"), "no access token in the output")
}

@(test)
test_the_github_device_flow_opens_the_browser_at_the_code_page :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    opened = false
    oidc.BrowserLauncher = proc(command: []string) -> bool {
        for part in command {
            if strings.contains(part, "/activate") { opened = true }
        }
        return true
    }
    defer oidc.BrowserLauncher = nil
    code: int = runTool({algorithm = .ES256, client_id = "game", subject = "user-9"}, .NONE, "github", nil, false, &output, "", true)
    text: string = strings.to_string(output)
    testing.expect_value(t, code, 0)
    testing.expectf(t, opened && strings.contains(text, "the browser was asked to open it"), "the page of the code was opened: %s", text)
}

@(private = "file")
opened: bool

@(test)
test_the_device_code_of_an_unknown_client_is_refused :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    capture = &output
    defer capture = nil
    _ = os.write_entire_file("login_tool_test_refused.txt", "github.client_id = some-id\n")
    defer _ = os.remove("login_tool_test_refused.txt")
    // nothing listens at this address: the device flow cannot start
    code: int = run({"github", "--file", "login_tool_test_refused.txt", "--issuer", "http://127.0.0.1:9", "--timeout", "2"})
    testing.expect_value(t, code, 1)
    testing.expect(t, strings.contains(strings.to_string(output), "refused the device flow"))
}

@(test)
test_usage_and_settings_errors_end_with_code_2 :: proc(t: ^testing.T) {
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    output: strings.Builder
    defer strings.builder_destroy(&output)
    capture = &output
    defer capture = nil
    _ = os.write_entire_file("login_tool_test_placeholder.txt", "discord.client_id = YOUR_DISCORD_APPLICATION_ID\n")
    _ = os.write_entire_file("login_tool_test_empty.txt", "# nothing\n")
    defer {
        _ = os.remove("login_tool_test_placeholder.txt")
        _ = os.remove("login_tool_test_empty.txt")
    }

    testing.expect_value(t, run({}), 2)
    testing.expect(t, strings.contains(strings.to_string(output), "usage"), "no provider: the usage")
    strings.builder_reset(&output)
    testing.expect_value(t, run({"facebook"}), 2)
    testing.expect(t, strings.contains(strings.to_string(output), "usage"), "an unknown provider: the usage")
    strings.builder_reset(&output)
    testing.expect_value(t, run({"discord", "--file", "login_tool_test_does_not_exist.txt"}), 2)
    testing.expect(t, strings.contains(strings.to_string(output), "no settings file"), "a missing file")
    strings.builder_reset(&output)
    testing.expect_value(t, run({"discord", "--file", "login_tool_test_placeholder.txt"}), 2)
    testing.expect(t, strings.contains(strings.to_string(output), "discord.client_id is not set"), "the placeholder of the example file is not an id")
    strings.builder_reset(&output)
    testing.expect_value(t, run({"google", "--file", "login_tool_test_empty.txt"}), 2)
    testing.expect(t, strings.contains(strings.to_string(output), "google.client_id is not set"), "a provider that is not in the file")
}

@(test)
test_the_settings_reader_reports_a_missing_file :: proc(t: ^testing.T) {
    _, found := readSettings("login_tool_test_nothing_here.txt")
    testing.expect(t, !found)
}

@(test)
test_the_field_names_of_json_are_listed_without_values :: proc(t: ^testing.T) {
    testing.expect_value(t, fieldNames(`{"sub":"secret-1","email":"a@b.c","picture":"https://x/y.png"}`), "email, picture, sub")
    testing.expect_value(t, fieldNames(`{}`), "")
    testing.expect_value(t, fieldNames(`[1,2]`), "(not an object)")
    testing.expect_value(t, fieldNames(`not json`), "(not JSON)")
    testing.expect(t, !strings.contains(fieldNames(`{"sub":"secret-1"}`), "secret-1"), "never a value")
}
