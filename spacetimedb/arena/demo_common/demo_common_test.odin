#+build !js
package demo_common

import "core:fmt"
import "core:os"
import "core:sync"
import "core:testing"
import kit "../../../demo_kit"
import st "../.."

// The tests share the demo's state (it is a package global like the demos of the other libraries): one at a time
tests_lock: sync.Mutex

// The demo with its script, headless: the program starts a server of its own and a game on it, the simulated keys move the player. Skipped without the server and the module
// (`odin run spacetimedb/tool/setup`).
@(test)
test_the_arena_demo_plays_its_script :: proc(t: ^testing.T) {
    if st.FixturePath("arena-odin") == "" || !os.exists(st.ServerCliPath()) {
        fmt.println("[arena] no server or no arena module: the demo test is skipped")
        return
    }
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    config = {parsed = true, mode = .SOLO, name = "Tester", root = "arena_test_demo", port = 3145, sleep_ms = 2}
    defer st.ServerRemove("arena_test_demo")
    headless: kit.HeadlessState
    backend: kit.Backend
    kit.HeadlessInit(&backend, &headless)
    report: kit.Report = kit.TestDemo(demo_arena_solo, &backend)
    for failure in report.failures[:min(report.failed, kit.MAX_FAILURES)] {
        testing.expectf(t, false, "frame %d: %s", failure.frame, failure.message)
    }
    testing.expect(t, report.finished, "the script reached its end")
    testing.expect(t, report.draw_calls > 0, "something was drawn")
}

// The start screen with its script: clicks, typing, Paste and Copy, solo, host and Escape. Needs the server and the module like the other test.
@(test)
test_the_arena_start_screen_plays_its_script :: proc(t: ^testing.T) {
    if st.FixturePath("arena-odin") == "" || !os.exists(st.ServerCliPath()) {
        fmt.println("[arena] no server or no arena module: the start screen test is skipped")
        return
    }
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    config = {parsed = true, menu = true, name = "Tester", root = "arena_test_menu", port = 3146, sleep_ms = 2, loopback = true}
    defer st.ServerRemove("arena_test_menu")
    defer st.ServerRemove("arena_test_menu_host")
    headless: kit.HeadlessState
    backend: kit.Backend
    kit.HeadlessInit(&backend, &headless)
    report: kit.Report = kit.TestDemo(demo_arena, &backend)
    for failure in report.failures[:min(report.failed, kit.MAX_FAILURES)] {
        testing.expectf(t, false, "frame %d: %s", failure.frame, failure.message)
    }
    testing.expect(t, report.finished, "the script reached its end")
}

// Signing in: the whole flow against a provider of our own and a real server: the identity of the account is the same in two games on two servers, an anonymous player's is not.
@(test)
test_the_arena_sign_in_plays_its_script :: proc(t: ^testing.T) {
    if st.FixturePath("arena-odin") == "" || !os.exists(st.ServerCliPath()) {
        fmt.println("[arena] no server or no arena module: the sign in test is skipped")
        return
    }
    sync.mutex_lock(&tests_lock)
    defer sync.mutex_unlock(&tests_lock)
    config = {parsed = true, menu = true, name = "Tester", root = "arena_test_signin", port = 3149, sleep_ms = 2, loopback = true}
    defer st.ServerRemove("arena_test_signin")
    headless: kit.HeadlessState
    backend: kit.Backend
    kit.HeadlessInit(&backend, &headless)
    report: kit.Report = kit.TestDemo(demo_arena_signin, &backend)
    for failure in report.failures[:min(report.failed, kit.MAX_FAILURES)] {
        testing.expectf(t, false, "frame %d: %s", failure.frame, failure.message)
    }
    testing.expect(t, report.finished, "the script reached its end")
}

@(test)
test_room_names_are_told_from_invite_codes :: proc(t: ^testing.T) {
    testing.expect(t, looksLikeRoom("maple-otter-22"))
    testing.expect(t, looksLikeRoom("amber-fjord-4"))
    testing.expect(t, !looksLikeRoom("0M0TC-2WC12-0P280-R1TJ2-1BR6A-HJQ6X-35E81-09B0R-P00Z9-S84R2-M5G1Q-MWM00"), "an invite code")
    testing.expect(t, !looksLikeRoom("maple otter 22"), "spaces")
    testing.expect(t, !looksLikeRoom("maple-otter"), "no relay number")
    testing.expect(t, !looksLikeRoom(""))
}
