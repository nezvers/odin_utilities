#+build !js
package session

import "core:fmt"
import "core:os"
import "core:testing"
import "core:time"
import st ".."

// The stages of a connection give a slower device more time
@(test)
test_the_stage_times_follow_the_time_scale :: proc(t: ^testing.T) {
    testing.expect_value(t, stageMsFor(STAGE_GATHER_MS, 1), 5000)
    testing.expect_value(t, stageMsFor(STAGE_RELAY_MS, 3), 24000)
    testing.expect_value(t, stageMsFor(STAGE_FIND_MS, 0.5), 15000)
    testing.expect_value(t, stageMs(STAGE_GATHER_MS), stageMsFor(STAGE_GATHER_MS, st.TimeScale))
}

@(private = "file")
lobbyWait :: proc(a: ^Lobby, b: ^Lobby, milliseconds: int, done: proc(a: ^Lobby, b: ^Lobby) -> bool) -> bool {
    deadline: time.Tick = time.tick_now()
    for time.duration_milliseconds(time.tick_since(deadline)) < f64(milliseconds) {
        LobbyUpdate(a)
        LobbyUpdate(b)
        if done(a, b) { return true }
        time.sleep(3 * time.Millisecond)
    }
    return false
}

// Nothing of this is the arena: the module is the `basic` example (a table `person`), the database is called "basic", and the guest reaches it through the tunnel with a plain ping and a table read.
// Skipped without the server and the module (`odin run spacetimedb/tool/setup`).
@(test)
test_a_lobby_hosts_and_joins_any_module :: proc(t: ^testing.T) {
    module: string = st.FixturePath("basic-odin")
    if module == "" || !os.exists(st.ServerCliPath()) {
        fmt.println("[session] no server or no basic module: run `odin run spacetimedb/tool/setup` to test the lobby")
        return
    }
    root: string = "session_test_host"
    st.ServerRemove(root)
    defer st.ServerRemove(root)
    host := new(Lobby)                    // on the heap: SetIdle keeps pointers into the guest
    guest := new(Lobby)
    defer free(host)
    defer free(guest)
    testing.expect(t, LobbyHost(host, {root = root, port = 3147, module_path = module, database = "basic", name = "Ada", loopback = true}), LobbyError(host))
    defer LobbyLeave(host)
    testing.expect(t, host.ready, "a host is ready as soon as its server is up")
    testing.expect_value(t, LobbyDatabase(host), "basic")
    testing.expect(t, lobbyWait(host, guest, 20000, proc(a: ^Lobby, b: ^Lobby) -> bool { return LobbyInvite(a) != "" }), "the invite is made")
    kind, from, _ := CodeInspect(LobbyInvite(host))
    testing.expect_value(t, kind, CodeKind.INVITE)
    testing.expect_value(t, from, "Ada")

    testing.expect(t, LobbyJoin(guest, LobbyInvite(host), "basic", {name = "Bob", loopback = true}), LobbyError(guest))
    defer LobbyLeave(guest)
    testing.expect(t, !guest.ready, "a guest is not ready before the tunnel is open")
    // the invite names no relay: the guest has a reply that the host accepts
    testing.expect(t, lobbyWait(host, guest, 20000, proc(a: ^Lobby, b: ^Lobby) -> bool { return LobbyStage(b) == .READY || LobbyStage(b) == .CONNECTED }), "the guest makes its reply")
    testing.expect(t, LobbyNeedsReply(guest))
    testing.expect(t, LobbyAcceptReply(host, LobbyReply(guest)))
    testing.expect(t, lobbyWait(host, guest, 30000, proc(a: ^Lobby, b: ^Lobby) -> bool { return b.ready }), fmt.tprintf("the guest is connected: %v %s", LobbyStage(guest), LobbyNotice(guest)))
    testing.expect(t, lobbyWait(host, guest, 10000, proc(a: ^Lobby, b: ^Lobby) -> bool { return LobbyGuests(a) == 1 }), "the host counts its friend")

    // the guest's endpoint is the host's database: the blocking calls step the tunnel through SetIdle
    testing.expect(t, st.ServerPing(guest.endpoint), "the host's server answers through the tunnel")
    testing.expect(t, guest.endpoint.port != host.endpoint.port, "the guest talks to a local port of its tunnel")
    response: [8192]u8
    _, token_view, made := st.IdentityCreate(guest.endpoint, response[:])
    testing.expect(t, made, "an identity can be made through the tunnel")
    token: string = fmt.tprintf("%s", token_view)
    schema: [8192]u8
    result: st.HttpResult = st.DatabaseSchema(guest.endpoint, "basic", token, schema[:])
    testing.expectf(t, result.ok && result.status == 200, "the schema of the published module is readable through the tunnel: %v %d", result.ok, result.status)

    // a bad code fails with a text and no crash
    bad := new(Lobby)
    defer free(bad)
    testing.expect(t, !LobbyJoin(bad, "not a code", "basic", {name = "X"}))
    testing.expect(t, bad.failed && LobbyError(bad) != "")
    LobbyLeave(bad)
}
