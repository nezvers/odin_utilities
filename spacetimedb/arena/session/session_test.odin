#+build !js
package arena_session

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import st "../.."
import game_lib "../game"
import schema "../schema"

// The whole chain on one computer: a host (server, module, p2p invite), a guest that joins by the codes and reaches the host's database through the tunnel, and a game client on each side
// that plays: both see both players and the coins, the guest holds a key and its player moves on the host's screen too. Skipped without the server and the module
// (`odin run spacetimedb/tool/setup`).

@(private = "file")
step :: proc(host: ^Host, guest: ^Guest, a: ^game_lib.Game, b: ^game_lib.Game) {
    HostUpdate(host)
    GuestUpdate(guest)
    game_lib.GamePoll(a)
    game_lib.GamePoll(b)
    time.sleep(time.Millisecond)
}

@(test)
test_two_players_play_through_a_p2p_tunnel :: proc(t: ^testing.T) {
    if st.FixturePath("arena-odin") == "" || !os.exists(st.ServerCliPath()) {
        fmt.println("[arena] no server or no arena module: run `odin run spacetimedb/tool/setup` to test the game")
        return
    }
    root: string = "arena_test_host"
    defer st.ServerRemove(root)
    host := new(Host)                    // on the heap: SetIdle keeps pointers to them
    defer free(host)
    if !HostStart(host, {root = root, port = 3143, loopback = true, name = "Ada"}) {
        testing.fail_now(t, host.error)
    }
    defer HostStop(host)

    // the codes: the guest pastes the invite, the host pastes the reply
    guest := new(Guest)
    defer free(guest)
    testing.expect(t, GuestJoin(guest, HostInvite(host), {loopback = true, name = "Bob"}), guest.error)
    defer GuestStop(guest)
    testing.expect(t, HostAcceptReply(host, GuestReply(guest)))
    for _ in 0 ..< 600 {
        HostUpdate(host)
        GuestUpdate(guest)
        time.sleep(time.Millisecond)
        if GuestConnected(guest) && HostGuests(host) == 1 { break }
    }
    testing.expect(t, GuestConnected(guest) && HostGuests(host) == 1, "the guest is connected to the host")
    testing.expect(t, GuestStartTunnel(guest))
    SetIdle(guest, host)
    defer ClearIdle()

    // a client for each: the host's one connects to its own server, the guest's one to the tunnel
    host_game := new(game_lib.Game)
    guest_game := new(game_lib.Game)
    defer free(host_game)
    defer free(guest_game)
    testing.expect(t, game_lib.GameOpen(host_game, host.server.endpoint, "Ada"), host_game.error)
    testing.expect(t, game_lib.GameOpen(guest_game, GuestEndpoint(guest), "Bob"), guest_game.error)
    defer game_lib.GameClose(host_game)
    defer game_lib.GameClose(guest_game)

    ready: bool
    for _ in 0 ..< 5000 {
        step(host, guest, host_game, guest_game)
        if host_game.phase == .PLAYING && guest_game.phase == .PLAYING && host_game.player_count == 2 && guest_game.player_count == 2 && host_game.coin_count > 0 && guest_game.coin_count > 0 {
            ready = true
            break
        }
    }
    testing.expectf(t, ready, "both clients see two players and the coins: host %v %d players %d coins, guest %v %d players %d coins (%s %s)", host_game.phase, host_game.player_count, host_game.coin_count, guest_game.phase, guest_game.player_count, guest_game.coin_count, host_game.error, guest_game.error)
    if !ready { return }
    testing.expect_value(t, host_game.coin_count, 8)

    // Bob holds right: his player moves, on his screen and on Ada's
    bob_before, found := game_lib.GameMe(guest_game)
    testing.expect(t, found)
    start_x: f32 = bob_before.x
    game_lib.GameInput(guest_game, 1, 0)
    moved: bool
    for _ in 0 ..< 3000 {
        step(host, guest, host_game, guest_game)
        game_lib.GameInput(guest_game, 1, 0)
        seen: ^schema.Player
        for i in 0 ..< host_game.player_count {
            if host_game.players[i].owner == guest_game.connection.identity { seen = &host_game.players[i] }
        }
        mine, mine_found := game_lib.GameMe(guest_game)
        if seen != nil && mine_found && (seen.x > start_x + 30 || start_x > 700) && (mine.x > start_x + 30 || start_x > 700) {
            moved = true
            break
        }
    }
    testing.expect(t, moved, "Bob moved right on both screens")

    // Bob leaves: his row goes (the database sees the disconnect)
    game_lib.GameClose(guest_game)
    gone: bool
    for _ in 0 ..< 3000 {
        HostUpdate(host)
        GuestUpdate(guest)
        game_lib.GamePoll(host_game)
        time.sleep(time.Millisecond)
        if host_game.player_count == 1 {
            gone = true
            break
        }
    }
    testing.expect(t, gone, "a player who leaves leaves the field")
}

// Needs the internet: `ARENA_LIVE=1 odin test spacetimedb/arena/session`. The invite names a free DERP relay and the guest joins with no reply code at all.
@(test)
test_a_guest_joins_through_a_derp_relay_without_a_reply_code :: proc(t: ^testing.T) {
    if os.get_env("ARENA_LIVE", context.temp_allocator) != "1" { return }
    if st.FixturePath("arena-odin") == "" || !os.exists(st.ServerCliPath()) { return }
    root: string = "arena_test_derp"
    defer st.ServerRemove(root)
    host := new(Host)
    defer free(host)
    if !HostStart(host, {root = root, port = 3144, internet = true, derp = true, name = "Ada"}) { testing.fail_now(t, host.error) }
    defer HostStop(host)
    guest := new(Guest)
    defer free(guest)
    testing.expect(t, GuestJoin(guest, HostInvite(host), {internet = true, name = "Bob"}), guest.error)
    defer GuestStop(guest)
    // no HostAcceptReply: the relay carries the answer
    for _ in 0 ..< 1500 {
        HostUpdate(host)
        GuestUpdate(guest)
        time.sleep(10 * time.Millisecond)
        if GuestConnected(guest) && HostGuests(host) == 1 { break }
    }
    testing.expect(t, GuestConnected(guest) && HostGuests(host) == 1, "connected with the one code")
}

// Needs the internet (`ARENA_LIVE=1`): the host has a room name, the guest types only that name: the relay says who hosts it, the host answers with its invite, they connect. No code at all.
@(test)
test_a_guest_joins_a_room_by_its_name :: proc(t: ^testing.T) {
    if os.get_env("ARENA_LIVE", context.temp_allocator) != "1" { return }
    if st.FixturePath("arena-odin") == "" || !os.exists(st.ServerCliPath()) { return }
    root: string = "arena_test_room"
    defer st.ServerRemove(root)
    host := new(Host)
    defer free(host)
    if !HostStart(host, {root = root, port = 3148, internet = true, derp = true, name = "Ada"}) { testing.fail_now(t, host.error) }
    defer HostStop(host)
    room: string = HostRoom(host)
    testing.expect(t, room != "" && strings.count(room, "-") == 2, "the host has a room name and the number of its relay")
    guest := new(Guest)
    defer free(guest)
    testing.expect(t, GuestBeginRoom(guest, room, {internet = true, name = "Bob"}), guest.error)
    defer GuestStop(guest)
    for _ in 0 ..< 3000 {
        HostUpdate(host)
        GuestUpdate(guest)
        time.sleep(10 * time.Millisecond)
        if guest.stage == .CONNECTED || guest.stage == .FAILED { break }
    }
    testing.expectf(t, guest.stage == .CONNECTED && HostGuests(host) == 1, "joined by the room name %s: %v %s", room, guest.stage, guest.error)
    // a room that nobody hosts
    lonely := new(Guest)
    defer free(lonely)
    testing.expect(t, GuestBeginRoom(lonely, "no-such-room-4", {internet = true, name = "Eve"}))
    defer GuestStop(lonely)
    _ = lonely
}
