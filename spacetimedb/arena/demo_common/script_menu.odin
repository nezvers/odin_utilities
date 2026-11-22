#+build !js
package demo_common

import "core:strings"
import kit "../../../demo_kit"
import "../../../p2p"
import "../session"

// The test of the screens made with the ui library: a widget is found by its name (`aim`, from the layout of the last frame) and clicked, so the script does not depend on where the layout
// puts it. A text that is not a code brings the menu back with a message, Paste and Copy use the clipboard, solo and host start a game, and Escape leaves it. The headless run has no real time,
// so the demo sleeps in every frame (`config.sleep_ms`).
target: kit.Vec2

aimPlaySolo :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "menu", "Play solo") }
aimHost :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "menu", "Host a game") }
aimJoin :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "menu", "Join a game") }
aimPaste :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "join", "Paste") }
aimConnect :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "join", "Connect") }
aimBack :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "join", "Back") }
aimCopyInvite :: proc(ctx: ^kit.Context) -> bool { return aim(&target, CONNECTION_WINDOW, "Copy the invite code") }
aimName :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "menu", "Name") }
aimCopyReply :: proc(ctx: ^kit.Context) -> bool { return aim(&target, "connecting", "Copy the reply code") }
aimReplyPaste :: proc(ctx: ^kit.Context) -> bool { return aim(&target, CONNECTION_WINDOW, "Paste") }
aimReplyAccept :: proc(ctx: ^kit.Context) -> bool { return aim(&target, CONNECTION_WINDOW, "Accept the reply") }

// The right of the screen: the Players and the Connection windows (the field is on the left and changes all the time)
panel_frames: []kit.Rect = {{880, 40, 380, 660}}

menu_script: []kit.Step = {
    kit.Wait(4),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        config.loopback = true                                // the codes of this machine and the loopback are enough to connect
        state.name_length = copy(state.name[:], "player")
        return state.phase == .MENU && state.name_length > 0
    }, "the start screen is shown with a name"),
    // a held key repeats like in any editor: backspace erases a whole name while it is held
    kit.Check(proc(ctx: ^kit.Context) -> bool { state.name_length = 0; return aimName(ctx) }, "the name field is on the screen"),
    kit.ClickAt(&target),
    kit.Type("abcdefghijklmnop"),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.name[:state.name_length]) == "abcdefghijklmnop" }, "the name field takes typing"),
    kit.Hold(.BACKSPACE, 1100),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.name_length == 0 }, "holding backspace erased all 16 letters (a tap erases one)"),
    kit.Tap(.BACKSPACE),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { state.name_length = copy(state.name[:], "player"); return aimName(ctx) }, "the name for the pictures"),
    kit.ClickAt(&target),                          // a click past the end of the text puts the caret at the end
    kit.Wait(3),
    kit.Tap(.BACKSPACE),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.name_length == 5 }, "one tap erases one letter, not more"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { state.name_length = copy(state.name[:], "player"); return true }, "the name for the pictures again"),
    kit.Check(aimJoin, "the Join a game button is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .JOIN_FORM }, "Join a game opens the form"),
    // nothing is pasted yet: Connect does nothing
    kit.Check(proc(ctx: ^kit.Context) -> bool { return session_kind(state.code[:state.code_length]) == .EMPTY && aimConnect(ctx) }, "nothing is pasted and the Connect button is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .JOIN_FORM }, "Connect does nothing without a code"),
    // a text that is not a code: Paste takes it and the label says what it is
    kit.Check(proc(ctx: ^kit.Context) -> bool { kit.ClipboardSet(ctx, "not a code"); return aimPaste(ctx) }, "the clipboard takes text and the Paste button is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.code[:state.code_length]) == "not a code" && session_kind(state.code[:state.code_length]) == .NOT_A_CODE }, "Paste takes the text and it is told apart: not a code"),
    kit.Wait(15),
    kit.Capture("join_form"),
    kit.Wait(1),
    kit.Check(aimConnect, "the Connect button is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .JOIN_FORM }, "Connect does nothing for a text that is not a code"),
    // the reply of a friend is not what the host's code is: told apart
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        reply: p2p.Invite = {kind = .REPLY, session = 3, id = 5, derp_server = 4}
        p2p.InviteSetName(&reply, "Eve")
        out: [p2p.CODE_TEXT_MAX]u8
        text, _ := p2p.InviteEncode(reply, out[:])
        kit.ClipboardSet(ctx, text)
        return aimPaste(ctx)
    }, "the clipboard has a reply code"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return session_kind(state.code[:state.code_length]) == .REPLY && aimConnect(ctx) }, "a reply code is told apart from an invite code"),
    kit.ClickAt(&target),
    kit.Wait(5),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .JOIN_FORM }, "and Connect does nothing for it"),
    // Paste puts the clipboard into the field
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
    kit.WaitUntil(proc(ctx: ^kit.Context) -> bool { return state.phase == .PLAYING && state.game != nil && state.game.phase == .PLAYING && state.game.player_count == 1 && state.game.coin_count > 0 }, "Play solo starts the game", 60),
    kit.Tap(.ESCAPE),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .MENU && state.host == nil && state.game != nil }, "Escape stops the server and shows the start screen again"),
    // host: the invite code is shown, Copy puts it on the clipboard
    kit.Check(aimHost, "the Host a game button is on the screen"),
    kit.ClickAt(&target),
    kit.WaitUntil(proc(ctx: ^kit.Context) -> bool { return state.phase == .PLAYING && state.host != nil && state.host.stage == .READY && aimCopyInvite(ctx) }, "Host a game starts the game and the invite is ready", 60),
    kit.Wait(15),
    kit.CaptureIn("host_ready", panel_frames),
    kit.Wait(1),
    // the reply of a friend: nothing is pasted, a text that is not a reply is told apart and cannot be accepted
    kit.Check(proc(ctx: ^kit.Context) -> bool { return session_kind(state.reply[:state.reply_length]) == .EMPTY && aimReplyAccept(ctx) }, "no reply is pasted and Accept the reply is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.paste_length == 0 && state.waiting_length == 0 }, "Accept does nothing without a reply"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { kit.ClipboardSet(ctx, "this is not a reply code"); return aimReplyPaste(ctx) }, "the connection window has a Paste button for the reply"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.reply[:state.reply_length]) == "this is not a reply code" && session_kind(state.reply[:state.reply_length]) == .NOT_A_CODE }, "Paste takes the text and it is told apart: not a code"),
    kit.Check(aimReplyAccept, "Accept the reply is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.paste_length == 0 && state.waiting_length == 0 && state.host != nil && session.HostGuests(state.host) == 0 }, "and it cannot be accepted: nobody is connecting"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { kit.ClipboardSet(ctx, ""); return aimCopyInvite(ctx) }, "the clipboard is emptied"),
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
        return session.GuestJoin(test_guest, session.HostInvite(state.host), {loopback = true, name = "Friend"})
    }, "a friend joins the hosted game with the code and has a reply code"),
    // the reply: copied on the friend's computer (the clipboard), pasted here, told apart, accepted; the window says that the friend is connecting
    kit.Check(proc(ctx: ^kit.Context) -> bool { kit.ClipboardSet(ctx, session.GuestReply(test_guest)); return aimReplyPaste(ctx) }, "the reply of the friend is on the clipboard"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        kind, from, _ := session.CodeInspect(string(state.reply[:state.reply_length]))
        return kind == .REPLY && from == "Friend" && aimReplyAccept(ctx)
    }, "the pasted reply is a reply code of Friend and can be accepted"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.reply_good && strings.contains(string(state.paste_message[:state.paste_length]), "Friend") && (state.waiting_length > 0 || session.HostGuests(state.host) == 1) }, "the reply is accepted and the window says that Friend is connecting (or has connected already: on this computer it takes a few frames)"),
    kit.WaitUntil(proc(ctx: ^kit.Context) -> bool { return session.HostGuests(state.host) == 1 && session.GuestConnected(test_guest) && state.waiting_length == 0 }, "the friend is connected and nothing is waited for any more", 60),
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
        state.code_length = 0
        kit.ClipboardSet(ctx, session.HostInvite(test_host))
        return true
    }, "another host is running with an invite code on the clipboard"),
    kit.Check(aimJoin, "the Join a game button is on the screen"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(aimPaste, "the join form has Paste"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return session_kind(state.code[:state.code_length]) == .INVITE && aimConnect(ctx) }, "the pasted code is an invite code and Connect is on the screen"),
    kit.ClickAt(&target),
    kit.WaitUntil(proc(ctx: ^kit.Context) -> bool { return state.phase == .CONNECTING && state.guest != nil && state.guest.stage >= .READY }, "the guest shows the connection being made and has its reply code", 60),
    kit.Capture("connecting"),
    kit.Wait(1),
    kit.Check(proc(ctx: ^kit.Context) -> bool { kit.ClipboardSet(ctx, ""); return aimCopyReply(ctx) }, "the connecting screen has Copy the reply code"),
    kit.ClickAt(&target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        buffer: [1024]u8
        return state.guest != nil && kit.ClipboardGet(ctx, buffer[:]) == session.GuestReply(state.guest)
    }, "Copy the reply code puts the reply on the clipboard"),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return session.HostAcceptReply(test_host, session.GuestReply(state.guest)) }, "the host accepts the reply code"),
    kit.WaitUntil(proc(ctx: ^kit.Context) -> bool { return state.phase == .PLAYING && state.game.phase == .PLAYING && state.game.player_count == 1 }, "the guest plays on the database of the other host through the tunnel", 60),
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

// What a text is, for the checks of the script
session_kind :: proc(text: []u8) -> session.CodeKind {
    kind, _, _ := session.CodeInspect(string(text))
    return kind
}
