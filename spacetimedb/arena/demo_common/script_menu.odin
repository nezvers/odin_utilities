#+build !js
package demo_common

import "core:strings"
import kit "../../../demo_kit"
import "../session"

// The test of the start screen: the buttons are clicked at their places (the screen is 1280 x 720 on every display), a wrong code brings back the menu with a message, Paste and Copy
// use the clipboard, solo and host start a game, and Escape leaves it. The headless run has no real time, so the demo sleeps in every frame (`config.sleep_ms`).
copy_target: kit.Vec2

menu_script: []kit.Step = {
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .MENU && state.name_length > 0 }, "the start screen is shown with a name"),
    // join with nothing pasted: back to the menu with a message
    kit.Click({640, 420}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .JOIN_FORM }, "Join a game opens the form"),
    kit.Click({640, 342}),
    kit.Wait(8),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .MENU && strings.contains(string(state.status[:state.status_length]), "paste the code") }, "Connect without a code says so on the start screen"),
    // a typed text that is not a code
    kit.Click({640, 420}),
    kit.Wait(2),
    kit.Click({500, 256}),
    kit.Type("not a code"),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.code[:state.code_length]) == "not a code" }, "the code field takes typing"),
    kit.Click({640, 342}),
    kit.Wait(8),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .MENU && strings.contains(string(state.status[:state.status_length]), "not an invite code") }, "a text that is not a code is refused"),
    // Paste puts the clipboard into the field
    kit.Click({640, 420}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { kit.ClipboardSet(ctx, "pasted-code\nsecond line"); return true }, "the clipboard takes text"),
    kit.Click({1040, 256}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return string(state.code[:state.code_length]) == "pasted-code" }, "Paste puts the first line of the clipboard into the code field"),
    kit.Click({640, 392}),
    kit.Wait(2),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .MENU }, "Back returns to the start screen"),
    // solo: a server and a game start, Escape leaves
    kit.Click({640, 312}),
    kit.Wait(1400),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .PLAYING && state.game != nil && state.game.phase == .PLAYING && state.game.player_count == 1 && state.game.coin_count > 0 }, "Play solo starts the game"),
    kit.Tap(.ESCAPE),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .MENU && state.host == nil && state.game != nil }, "Escape stops the server and shows the start screen again"),
    // host: the invite code is shown, Copy code puts it on the clipboard
    kit.Click({640, 366}),
    kit.Wait(1400),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .PLAYING && state.invite_line_count > 0 && state.copy_rect[2] > 0 }, "Host a game starts the game and shows an invite code"),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        copy_target = {state.copy_rect[0] + 60, state.copy_rect[1] + 13}
        kit.ClipboardSet(ctx, "")
        return true
    }, "the Copy code button is found"),
    kit.ClickAt(&copy_target),
    kit.Wait(3),
    kit.Check(proc(ctx: ^kit.Context) -> bool {
        buffer: [1024]u8
        return state.host != nil && kit.ClipboardGet(ctx, buffer[:]) == session.HostInvite(state.host)
    }, "Copy code puts the invite on the clipboard"),
    kit.Tap(.ESCAPE),
    kit.Wait(10),
    kit.Check(proc(ctx: ^kit.Context) -> bool { return state.phase == .MENU }, "and Escape leaves the hosted game"),
}

demo_arena_menu: kit.Demo = {
    name = "arena start screen",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = menu_script,
}
