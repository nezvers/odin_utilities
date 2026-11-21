#+build !js
package demo_common

import "core:strings"
import kit "../../../demo_kit"
import "../session"

// The test of the screens made with the ui library: a widget is found by its name (`aim`, from the layout of the last frame) and clicked, so the script does not depend on where the layout
// puts it. A text that is not a code brings the menu back with a message, Paste and Copy use the clipboard, solo and host start a game, and Escape leaves it. The headless run has no real time,
// so the demo sleeps in every frame (`config.sleep_ms`).
target: kit.Vec2

aimPlaySolo :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "menu", "Play solo") }
aimHost :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "menu", "Host a game") }
aimJoin :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "menu", "Join a game") }
aimCode :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "join", "Code") }
aimPaste :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "join", "Paste") }
aimConnect :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "join", "Connect") }
aimBack :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "join", "Back") }
aimCopyInvite :: proc(ctx: ^kit.Context) -> bool { return aim(&target, CONNECTION_WINDOW, "Copy the invite code") }

// The right of the screen: the Players and the Connection windows (the field is on the left and changes all the time)
panel_frames: []kit.Rect = {{880, 40, 380, 660}}

menu_script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        config.mask_codes, config.loopback = true, true       // pictures cannot hold a code that is new every time; the codes of this machine and the loopback are enough to connect
        state.name_length = copy(state.name[:], "player")
        return state.phase == .MENU && state.name_length > 0
    }, "the start screen is shown with a name"),
    kit.Check(aimJoin, "the Join a game button is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .JOIN_FORM }, "Join a game opens the form"),
    // a typed text that is not a code
    kit.Check(aimCode, "the code field is on the screen"),
    kit.ClickAt(&target),
    kit.Type("not a code"),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.code[:state.code_length]) == "not a code" }, "the code field takes typing"),
    kit.Wait(15),
    kit.Capture("join_form"),
    kit.Wait(1),
    kit.Check(aimConnect, "the Connect button is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .MENU && strings.contains(string(state.status[:state.status_length]), "not an invite code") }, "a text that is not a code is refused on the start screen"),
    kit.Wait(15),
    kit.Capture("menu_refused"),
    kit.Wait(1),
    // Paste puts the clipboard into the field
    kit.Check(aimJoin, "the Join a game button is back"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { kit.ClipboardSet(ctx, "pasted-code\nsecond line"); return aimPaste(ctx) }, "the clipboard takes text and the Paste button is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return strings.has_prefix(string(state.code[:state.code_length]), "pasted-code") }, "Paste puts the clipboard into the code field"),
    kit.Check(aimBack, "the Back button is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .MENU }, "Back returns to the start screen"),
    // solo: a server and a game start, Escape leaves
    kit.Check(aimPlaySolo, "the Play solo button is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(1400),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .PLAYING && state.game != nil && state.game.phase == .PLAYING && state.game.player_count == 1 && state.game.coin_count > 0 }, "Play solo starts the game"),
    kit.Tap(.ESCAPE),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .MENU && state.host == nil && state.game != nil }, "Escape stops the server and shows the start screen again"),
    // host: the invite code is shown, Copy puts it on the clipboard
    kit.Check(aimHost, "the Host a game button is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(1400),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .PLAYING && state.host != nil && state.host.stage == .READY && aimCopyInvite(ctx) }, "Host a game starts the game and the invite is ready"),
    kit.Wait(15),
    kit.CaptureIn("host_ready", panel_frames),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { kit.ClipboardSet(ctx, ""); return true }, "the clipboard is emptied"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        buffer: [1024]u8
        return state.host != nil && kit.ClipboardGet(ctx, buffer[:]) == session.HostInvite(state.host)
    }, "Copy the invite code puts the invite on the clipboard"),
    // a friend (a guest of this process) joins the hosted game with the code: the Connection window lists it with the path of the connection
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        test_guest = new(session.Guest)
        frame_hook = proc() {
            if test_guest != nil { session.GuestUpdate(test_guest) }
            if test_host != nil { session.HostUpdate(test_host) }
        }
        if !session.GuestJoin(test_guest, session.HostInvite(state.host), {loopback = true, name = "Friend"}) { return false }
        return session.HostAcceptReply(state.host, session.GuestReply(test_guest))
    }, "a friend joins the hosted game and its reply is accepted"),
    kit.Wait(300),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return session.HostGuests(state.host) == 1 && session.GuestConnected(test_guest) }, "the friend is connected"),
    kit.Wait(15),
    kit.CaptureIn("host_with_friend", panel_frames),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        frame_hook = nil
        session.GuestStop(test_guest)
        free(test_guest)
        test_guest = nil
        return true
    }, "the friend leaves"),
    kit.Tap(.ESCAPE),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .MENU }, "and Escape leaves the hosted game"),
    // join the game of another host in this process: the steps of the connection are shown, the reply is accepted, the game starts through the tunnel
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        test_host = new(session.Host)
        if !session.HostStart(test_host, {root = "arena_test_menu_host", port = 3147, loopback = true, name = "Friend"}) { return false }
        frame_hook = proc() { if test_host != nil { session.HostUpdate(test_host) } }
        config.idle_host = test_host
        state.code_length = copy(state.code[:], session.HostInvite(test_host))
        return true
    }, "another host is running with an invite code"),
    kit.Check(aimJoin, "the Join a game button is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(aimConnect, "the code is in the field and Connect is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(40),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .CONNECTING && state.guest != nil && state.guest.stage >= .READY }, "the guest shows the connection being made and has its reply code"),
    kit.Capture("connecting"),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return session.HostAcceptReply(test_host, session.GuestReply(state.guest)) }, "the host accepts the reply code"),
    kit.Wait(600),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .PLAYING && state.game.phase == .PLAYING && state.game.player_count == 1 }, "the guest plays on the database of the other host through the tunnel"),
    kit.Wait(15),
    kit.CaptureIn("guest_playing", panel_frames),
    kit.Wait(1),
    kit.Tap(.ESCAPE),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        frame_hook = nil
        config.idle_host = nil
        if test_host != nil {
            session.HostStop(test_host)
            free(test_host)
            test_host = nil
        }
        return state.phase == .MENU
    }, "Escape leaves, the other host is stopped"),
}

test_host: ^session.Host
test_guest: ^session.Guest
