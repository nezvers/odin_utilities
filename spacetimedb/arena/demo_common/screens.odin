#+build !js
package demo_common

// The windows of the game, made with `odin_utilities/ui`: the start screen, the screen that takes a code, the screen that shows a connection being made, and the two windows that stay over the
// game (the players, and the connection with the invite code, the friends and how they are connected). It is the example of how a program shows and handles its connections with the ui library:
// a window per concern, widgets that return what was clicked, a style for everything, text fields that paste. The game itself (the field, the coins, the players) is drawn with the kit.
//
// Everything here runs in the `draw` of the demo: `uiFrame` opens the ui frame, calls the screen of the phase and renders it over what the kit drew.

import "core:fmt"
import "core:strings"
import ui "../../../ui"
import ui_default "../../../ui/default_style"
import ui_kit "../../../ui/kit"
import kit "../../../demo_kit"
import "../../../p2p"
import "../session"
import game_lib "../game"
import schema "../schema"

UiState :: struct {
    storage: ui.Storage(512, 1024, 128, 8192),
    ctx: ui.Context,
    painter: ui_default.Painter,
    style: ui.Style,
    ready: bool,
    players_position: ui.Vec2,
    connection_position: ui.Vec2,
}

ui_state: UiState

CONNECTION_WINDOW :: "Connection##connection"       // shown as Connection; the ids of its widgets are found by this name

// The kit context of the frame that is being drawn: the clipboard procs of the ui reach the clipboard of the kit through it
@(private = "file")
frame_context: ^kit.Context

uiInit :: proc() {
    ui_state = {}
    ui_kit.PainterInit(&ui_state.painter)
    ui_state.style = ui_default.StyleMake()
    ui.UiInit(&ui_state.ctx, &ui_state.storage, ui_default.Measure, &ui_state.painter)
    ui_state.ctx.clipboard.get = proc(c: ^ui.Context, buffer: []u8) -> int {
        return len(kit.ClipboardGet(frame_context, buffer))
    }
    ui_state.ctx.clipboard.set = proc(c: ^ui.Context, text: string) {
        kit.ClipboardSet(frame_context, text)
    }
    ui_state.ready = true
    ui_state.players_position = {900, 60}
    ui_state.connection_position = {900, 230}
}

// One ui frame over the frame of the kit
uiFrame :: proc(kit_ctx: ^kit.Context) {
    if !ui_state.ready { return }
    frame_context = kit_ctx
    ui_kit.Begin(&ui_state.ctx, &ui_state.painter, &ui_state.style, kit_ctx)
    c: ^ui.Context = &ui_state.ctx
    switch state.phase {
    case .MENU: menuScreen(c)
    case .JOIN_FORM: joinScreen(c)
    case .STARTING: startingScreen(c)
    case .CONNECTING: connectingScreen(c)
    case .PLAYING:
        waitingNotice(c, state.game)
        playersWindow(c)
        connectionWindow(c)
    case .FAILED: failedScreen(c)
    case .SIGN_IN: signInScreen(c)
    case .SIGNING_IN: signingInScreen(c)
    case .SIGN_IN_WAIT: signInWaitScreen(c)
    }
    ui.UiEnd(c)
    ui.UiRender(c)
}

// The keys of the game go to the game unless a text field has the keyboard
textFieldFocused :: proc() -> bool {
    focused: ui.Id = ui.UiFocused(&ui_state.ctx)
    if focused == 0 { return false }
    // a read only area (the invite) takes the focus too, to select and copy: the keys of the game are not for the player then
    return focused == ui.UiIdPath(CONNECTION_WINDOW, "Reply") || focused == ui.UiIdPath(CONNECTION_WINDOW, "Invite") || focused == ui.UiIdPath("menu", "Name") || focused == ui.UiIdPath("join", "Code")
}

@(private = "file")
WARNING :: ui.Color{255, 170, 60, 255}
@(private = "file")
GOOD :: ui.Color{110, 220, 130, 255}
@(private = "file")
DIM :: ui.Color{150, 156, 170, 255}

@(private = "file")
centered :: proc(c: ^ui.Context, width: f32, y: f32) -> ui.Vec2 {
    return {(c.screen.x - width) * 0.5, y}
}

@(private = "file")
column :: proc() -> ui.Layout {
    return {direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(18), gap = 10}
}

// The first line of a text, without the spaces around it: what a code field takes from the clipboard
@(private = "file")
firstLine :: proc(text: string) -> string {
    end: int = strings.index_any(text, "\r\n")
    return strings.trim_space(text if end < 0 else text[:end])
}

// The code as shown: a picture of the screen (a golden) cannot hold a code that is new every time, so a run that takes pictures (`config.mask_codes`) shows a fixed text of `length` letters
@(private = "file")
shownCode :: proc(code: string, length: int) -> string {
    if !config.mask_codes { return code }
    // groups like the ones of a real code, so that the lines are about as wide as real ones
    pattern: string = strings.repeat("XXXXX-", length / 6 + 1, context.temp_allocator)
    return pattern[:length]
}

// A code with no spaces cannot wrap by itself: it is cut into lines of `width` characters (temp memory)
@(private = "file")
cutCode :: proc(code: string, width: int) -> string {
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    for i := 0; i < len(code); i += width {
        if i > 0 { strings.write_byte(&builder, '\n') }
        strings.write_string(&builder, code[i:min(i + width, len(code))])
    }
    return strings.to_string(builder)
}

// While the game has no rows yet the field is not empty-looking: it says what is awaited and for how long. (The first data of a guest comes through the host's window: a slow host window means a slow start.)
@(private = "file")
waitingNotice :: proc(c: ^ui.Context, game: ^game_lib.Game) {
    waiting: f32 = game_lib.GameWaitingMs(game)
    if waiting < 300 { return }                      // 0: the data is here; a fast start does not flash the notice
    if ui.UiWindow(c, "waiting", centered(c, 420, 250), {ui.Fixed(420), ui.Fit()}, column()) {
        ui.UiSeparatorText(c, "Joining the game")
        if game.greeted_ms == 0 {
            ui.UiLabel(c, "waiting for the server to answer...")
        } else {
            ui.UiLabel(c, "connected: waiting for the first data of the game...")
        }
        ui.UiProgress(c, "waiting", min(1, waiting / 5000), 0, 1, {ui.Grow(), {}}, "")
        if waiting > 3000 {
            ui.UiLabelColored(c, fmt.tprintf("%.0f seconds. The data comes through the host's window: if it is minimized or busy, it is slow.", waiting / 1000), WARNING, .WORDS)
        }
    }
}

// A code that people read, select and copy: a read only text area that wraps it (a code has no spaces: the area breaks it where it must) and scrolls when it is longer than the box. The area keeps its
// own copy of the text in `buffer` (the caret and the selection stay while the text is the same).
@(private = "file")
codeBox :: proc(c: ^ui.Context, name: string, text: string, buffer: []u8, length: ^int, height: f32) {
    if string(buffer[:length^]) != text { length^ = copy(buffer, text) }
    _ = ui.UiTextArea(c, name, buffer, length, {ui.Grow(), ui.Fixed(height)}, true, false, nil, nil, true)
}

@(private = "file")
statusLine :: proc(c: ^ui.Context) {
    if state.status_length > 0 { ui.UiLabelColored(c, string(state.status[:state.status_length]), WARNING, .WORDS) }
}

// ---- the start screen ---------------------------------------------------------------------------------------------------------------------------------------------

menuScreen :: proc(c: ^ui.Context) {
    if ui.UiWindow(c, "menu", centered(c, 480, 80), {ui.Fixed(480), ui.Fit()}, column()) {
        ui.UiSeparatorText(c, "ARENA")
        ui.UiLabelColored(c, "A game on a SpacetimeDB database. Friends join over p2p: no server of anybody's.", DIM, .WORDS)
        ui.UiLabel(c, "Your name")
        ui.UiTextField(c, "Name", state.name[:], &state.name_length, {ui.Grow(), {}})
        accountSection(c)
        ui.UiSeparatorText(c, "Play")
        if ui.UiButton(c, "Play solo", {ui.Grow(), ui.Fixed(40)}, state.name_length == 0) {
            state.pending, state.phase = .SOLO, .STARTING
            setStatus("")
        }
        ui.UiTooltip(c, "Starts a server and a game on this computer. Nobody else can join.")
        if ui.UiButton(c, "Host a game", {ui.Grow(), ui.Fixed(40)}, state.name_length == 0) {
            state.pending, state.phase = .HOST, .STARTING
            setStatus("")
        }
        ui.UiTooltip(c, "The same, and an invite code for friends.")
        if ui.UiButton(c, "Join a game", {ui.Grow(), ui.Fixed(40)}) {
            state.phase = .JOIN_FORM
            setStatus("")
        }
        ui.UiTooltip(c, "Paste the invite code of a friend who hosts.")
        ui.UiSeparatorText(c, "When hosting")
        ui.UiToggle(c, "Free relay: friends join with one code", &state.relay)
        ui.UiTooltip(c, "Uses a free DERP relay (Tailscale, no account). The invite names it, so a friend needs no reply code, even behind strict NATs.")
        ui.UiToggle(c, "Public address: friends on other networks", &state.stun)
        ui.UiTooltip(c, "Asks public STUN servers for the address the internet sees, and puts it in the invite.")
        statusLine(c)
        ui.UiLabelColored(c, "WASD or the arrows move, Escape leaves a game.", DIM)
    }
}

// ---- an account ---------------------------------------------------------------------------------------------------------------------------------------------------

// Signed in: who, and Sign out. Not signed in: Sign in. The identity of a signed in player is the one of the account in every game.
@(private = "file")
accountSection :: proc(c: ^ui.Context) {
    account: ^Account = signin.account
    if account != nil {
        ui.UiLabelColored(c, fmt.tprintf("Signed in with %s as %s", string(account.provider[:account.provider_length]), string(account.name[:account.name_length])), GOOD, .WORDS)
        if ui.UiButton(c, "Sign out", {ui.Grow(), ui.Fixed(32)}) { signinOut() }
        ui.UiTooltip(c, "Your next game has a new anonymous identity.")
        return
    }
    if ui.UiButton(c, "Sign in", {ui.Grow(), ui.Fixed(32)}) {
        signinLoad()
        signin.message_length = 0
        state.phase = .SIGN_IN
        setStatus("")
    }
    ui.UiTooltip(c, "Sign in with an account (Google, Discord ...): you are the same player in every game, with the name of your account.")
}

signInScreen :: proc(c: ^ui.Context) {
    if ui.UiWindow(c, "signin", centered(c, 520, 120), {ui.Fixed(520), ui.Fit()}, column()) {
        ui.UiSeparatorText(c, "Sign in")
        ui.UiLabelColored(c, "A page of the account opens in your browser. The game never sees a password: it gets a proof of who you are.", DIM, .WORDS)
        if signin.provider_count == 0 {
            ui.UiLabelColored(c, "No account is set up. Put a client id into oidc/providers/providers.local.txt (oidc/README.md, Getting a client id).", WARNING, .WORDS)
        }
        for i in 0 ..< signin.provider_count {
            if ui.UiButton(c, fmt.tprintf("Sign in with %s", signin.providers[i].label), {ui.Grow(), ui.Fixed(40)}) { signinChoose(i) }
        }
        if signin.message_length > 0 { ui.UiLabelColored(c, signinMessage(), WARNING, .WORDS) }
        if ui.UiButton(c, "Back", {ui.Grow(), ui.Fixed(34)}) {
            state.phase = .MENU
            setStatus("")
        }
    }
}

signingInScreen :: proc(c: ^ui.Context) {
    if ui.UiWindow(c, "signing", centered(c, 420, 260), {ui.Fixed(420), ui.Fit()}, column()) {
        ui.UiSeparatorText(c, "Signing in")
        ui.UiLabel(c, fmt.tprintf("Contacting %s...", signin.providers[signin.chosen].label))
        ui.UiProgress(c, "working", 0.5, 0, 1, {ui.Grow(), {}}, "")
    }
}

signInWaitScreen :: proc(c: ^ui.Context) {
    if ui.UiWindow(c, "signin_wait", centered(c, 660, 120), {ui.Fixed(660), ui.Fit()}, column()) {
        ui.UiSeparatorText(c, fmt.tprintf("Sign in with %s", signin.providers[signin.chosen].label))
        ui.UiLabelColored(c, "A page was opened in your browser: sign in there, then come back to this window. If no page appeared, copy this address into a browser.", DIM, .WORDS)
        ui.UiLabelColored(c, cutCode(shownCode(signinAddress(), 300), 70), RAY, .NEWLINES)
        if ui.UiRow(c, {size = {ui.Grow(), ui.Fit()}, gap = 10}) {
            if ui.UiButton(c, "Copy the address", {ui.Grow(), ui.Fixed(36)}) { kit.ClipboardSet(frame_context, signinAddress()) }
            if ui.UiButton(c, "Open the browser", {ui.Grow(), ui.Fixed(36)}) { signinOpenBrowser() }
            if ui.UiButton(c, "Cancel", {ui.Grow(), ui.Fixed(36)}) { signinCancel() }
        }
    }
}

// ---- the code of a host -------------------------------------------------------------------------------------------------------------------------------------------

joinScreen :: proc(c: ^ui.Context) {
    if ui.UiWindow(c, "join", centered(c, 760, 120), {ui.Fixed(760), ui.Fit()}, column()) {
        ui.UiSeparatorText(c, "Join a game")
        ui.UiLabelColored(c, "Type the room name that the host gave you (like maple-otter-22), or paste an invite code (Ctrl+V in the field, or the button).", DIM, .WORDS)
        _ = ui.UiTextArea(c, "Code", state.code[:], &state.code_length, {ui.Grow(), ui.Fixed(86)})          // a code is long: a text area wraps it and shows all of it
        if ui.UiRow(c, {size = {ui.Grow(), ui.Fit()}, gap = 10}) {
            if ui.UiButton(c, "Paste", {ui.Grow(), ui.Fixed(38)}) {
                buffer: [1024]u8
                pasted: string = firstLine(kit.ClipboardGet(frame_context, buffer[:]))
                state.code_length = copy(state.code[:], pasted)
            }
            if ui.UiButton(c, "Connect", {ui.Grow(), ui.Fixed(38)}, state.code_length == 0) {
                state.pending, state.phase = .JOIN, .STARTING
                setStatus("")
            }
            if ui.UiButton(c, "Back", {ui.Grow(), ui.Fixed(38)}) {
                state.phase = .MENU
                setStatus("")
            }
        }
        statusLine(c)
    }
}

// ---- a connection being made --------------------------------------------------------------------------------------------------------------------------------------

startingScreen :: proc(c: ^ui.Context) {
    if ui.UiWindow(c, "starting", centered(c, 380, 260), {ui.Fixed(380), ui.Fit()}, column()) {
        ui.UiSeparatorText(c, "Starting")
        ui.UiLabel(c, "Starting the server and the game...")
        ui.UiProgress(c, "working", 0.5, 0, 1, {ui.Grow(), {}}, "")
    }
}

@(private = "file")
stageStep :: proc(c: ^ui.Context, done: bool, current: bool, text: string) {
    mark: string = "[x] " if done else "[>] " if current else "[ ] "
    ui.UiLabelColored(c, fmt.tprintf("%s%s", mark, text), GOOD if done else RAY if current else DIM)
}

@(private = "file")
RAY :: ui.Color{235, 238, 245, 255}

// A guest that has the code: the steps, the reply code when the host needs it, Cancel
connectingScreen :: proc(c: ^ui.Context) {
    guest: ^session.Guest = state.guest
    if guest == nil { return }
    if ui.UiWindow(c, "connecting", centered(c, 620, 140), {ui.Fixed(620), ui.Fit()}, column()) {
        ui.UiSeparatorText(c, "Connecting to the host")
        stage: session.Stage = guest.stage
        relay: bool = guest.invite.derp_server != 0 && !guest.options.no_derp
        stageStep(c, stage > .GATHERING, stage == .GATHERING, "finding the addresses of this computer")
        if guest.room_mode {
            stageStep(c, stage > .RELAY, stage == .RELAY, "reaching the free relay of the room")
            stageStep(c, stage > .FINDING, stage == .FINDING, "asking who hosts the room")
        } else if relay { stageStep(c, stage > .RELAY, stage == .RELAY, "reaching the free relay named by the code") }
        stageStep(c, stage >= .CONNECTED, stage == .READY, "the host answers")
        stageStep(c, state.guest_tunnel_open, stage == .CONNECTED, "opening the game's way to the host's database")
        steps := [session.Stage]f32{.IDLE = 0, .GATHERING = 0.15, .RELAY = 0.35, .FINDING = 0.55, .READY = 0.7, .CONNECTED = 0.9, .FAILED = 0}
        progress: f32 = steps[stage]
        ui.UiProgress(c, "connect", progress, 0, 1, {ui.Grow(), {}}, "")
        if stage == .READY && !relay {
            ui.UiLabelColored(c, "This code names no relay, so the host needs a reply code from you. Send it to the host:", WARNING, .WORDS)
            reply: string = session.GuestReply(guest)
            codeBox(c, "ReplyCode", shownCode(reply, 190), state.reply_view[:], &state.reply_view_length, 96)       // a real reply is about 190
            if ui.UiButton(c, "Copy the reply code", {ui.Grow(), ui.Fixed(34)}) { kit.ClipboardSet(frame_context, reply) }
        } else if stage == .READY {
            ui.UiLabelColored(c, "Waiting for the host. Nothing needs to be sent back: the relay carries the answer.", DIM, .WORDS)
        }
        if ui.UiButton(c, "Cancel", {ui.Grow(), ui.Fixed(34)}) { backToMenu() }
    }
}

failedScreen :: proc(c: ^ui.Context) {
    if ui.UiWindow(c, "failed", centered(c, 520, 200), {ui.Fixed(520), ui.Fit()}, column()) {
        ui.UiSeparatorText(c, "Could not start")
        ui.UiLabelColored(c, string(state.error[:state.error_length]), WARNING, .WORDS)
    }
}

// ---- over the game ------------------------------------------------------------------------------------------------------------------------------------------------

playersWindow :: proc(c: ^ui.Context) {
    game := state.game
    if ui.UiWindowTitled(c, "Players", &ui_state.players_position, {ui.Fixed(260), ui.Fit()}, {direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 4}) {
        order: [16]int
        for i in 0 ..< game.player_count { order[i] = i }
        for i in 1 ..< game.player_count {
            for j := i; j > 0 && game.players[order[j]].score > game.players[order[j - 1]].score; j -= 1 { order[j], order[j - 1] = order[j - 1], order[j] }
        }
        for rank in 0 ..< game.player_count {
            player: ^schema.Player = &game.players[order[rank]]
            ui.UiLabel(c, fmt.tprintf("%s   %d", player.name, player.score))
        }
        if game.player_count == 0 { ui.UiLabelColored(c, "nobody yet", DIM) }
    }
}

@(private = "file")
pathText :: proc(path: p2p.PeerPath) -> string {
    switch path {
    case .NONE: return "not connected"
    case .LAN: return "direct, same network"
    case .DIRECT: return "direct over the internet"
    case .RELAY: return "through the relay"
    }
    return ""
}

// The connection: for a host the invite and the friends, for everybody how the game is connected
connectionWindow :: proc(c: ^ui.Context) {
    host: ^session.Host = state.host
    guest: ^session.Guest = state.guest
    if ui.UiWindowTitled(c, CONNECTION_WINDOW, &ui_state.connection_position, {ui.Fixed(340), ui.Fit()}, {direction = .TOP_TO_BOTTOM, padding = ui.PaddingAll(10), gap = 6}) {
        ui.UiLabel(c, fmt.tprintf("game: %s", "connected" if state.game.phase == .PLAYING else fmt.tprintf("%v", state.game.phase)))
        if guest != nil {
            ui.UiLabel(c, "connected to: the host through p2p")
            if p2p.LinkPeerCount(guest.link) > 0 { ui.UiLabel(c, fmt.tprintf("path: %s", pathText(p2p.LinkPeerPath(guest.link, 0)))) }
        } else {
            ui.UiLabel(c, "server: this computer")
        }
        // a window that runs slowly serves the guests slowly (the host answers the p2p link once per frame): said when it is the case
        if host != nil && state.frame_ms > 60 { ui.UiLabelColored(c, fmt.tprintf("this window runs at %.0f frames a second: friends connect slowly", 1000 / state.frame_ms), WARNING, .WORDS) }
        if state.game.synced_ms > 2500 { ui.UiLabelColored(c, fmt.tprintf("the first data took %.1f seconds", state.game.synced_ms / 1000), WARNING, .WORDS) }
        if host != nil && state.hosting { hostPanel(c, host) }
        if state.game.error != "" { ui.UiLabelColored(c, state.game.error, WARNING, .WORDS) }
        if host != nil && session.HostNotice(host) != "" { ui.UiLabelColored(c, session.HostNotice(host), WARNING, .WORDS) }
        if guest != nil && session.GuestNotice(guest) != "" { ui.UiLabelColored(c, session.GuestNotice(guest), WARNING, .WORDS) }
        ui.UiLabelColored(c, "Escape leaves", DIM)
    }
}

@(private = "file")
hostPanel :: proc(c: ^ui.Context, host: ^session.Host) {
    ui.UiSeparatorText(c, "Invite friends")
    switch host.stage {
    case .GATHERING:
        ui.UiLabel(c, "finding the addresses of this computer...")
        ui.UiProgress(c, "gather", min(1, f32(session.HostElapsedMs(host)) / 5000), 0, 1, {ui.Grow(), {}}, "")
    case .FINDING:
        ui.UiLabel(c, "preparing the room...")
    case .RELAY:
        ui.UiLabel(c, "reaching the free relay...")
        ui.UiProgress(c, "relay", min(1, f32(session.HostElapsedMs(host)) / 8000), 0, 1, {ui.Grow(), {}}, "")
    case .READY, .CONNECTED:
        code: string = session.HostInvite(host)
        if room := session.HostRoom(host); room != "" && host.link.derp.state == .READY {
            ui.UiLabelColored(c, "Room: friends type this name:", GOOD)
            ui.UiLabelColored(c, room, RAY)
            if ui.UiButton(c, "Copy the room name", {ui.Grow(), ui.Fixed(32)}) { kit.ClipboardSet(frame_context, room) }
            ui.UiLabelColored(c, "or give them the invite code:", DIM)
        }
        codeBox(c, "Invite", shownCode(code, 330), state.invite_view[:], &state.invite_view_length, 120)     // a real invite is about 330 characters
        if ui.UiButton(c, "Copy the invite code", {ui.Grow(), ui.Fixed(32)}) { kit.ClipboardSet(frame_context, code) }
        if host.relay_used && host.link.derp.state == .READY {
            ui.UiLabelColored(c, "A friend needs only this code: the relay carries the answer.", GOOD, .WORDS)
        } else {
            ui.UiLabelColored(c, "No relay: a friend sends a reply code back. Paste it here:", WARNING, .WORDS)
            _ = ui.UiTextArea(c, "Reply", state.reply[:], &state.reply_length, {ui.Grow(), ui.Fixed(92)})          // a reply code is as long as an invite: a text area, not a line
            if ui.UiRow(c, {size = {ui.Grow(), ui.Fit()}, gap = 8}) {
                if ui.UiButton(c, "Paste", {ui.Grow(), ui.Fixed(32)}) {
                    buffer: [1024]u8
                    pasted: string = firstLine(kit.ClipboardGet(frame_context, buffer[:]))
                    state.reply_length = copy(state.reply[:], pasted)
                }
                if ui.UiButton(c, "Accept the reply", {ui.Grow(), ui.Fixed(32)}, strings.trim_space(string(state.reply[:state.reply_length])) == "") {
                    acceptReply(string(state.reply[:state.reply_length]))
                    state.reply_length = 0
                }
            }
            if state.paste_length > 0 { ui.UiLabelColored(c, string(state.paste_message[:state.paste_length]), WARNING, .WORDS) }
        }
    case .IDLE, .FAILED:
    }
    ui.UiSeparatorText(c, "Friends")
    friends: int
    for i in 0 ..< p2p.MAX_PEERS {
        path: p2p.PeerPath = p2p.LinkPeerPath(host.link, i)
        if path == .NONE { continue }
        ui.UiBullet(c, fmt.tprintf("%s: %s", p2p.LinkPeerName(host.link, i), pathText(path)))
        friends += 1
    }
    if friends == 0 { ui.UiLabelColored(c, "nobody has joined yet", DIM) }
}

// ---- finding a widget, for the script that plays the screens ------------------------------------------------------------------------------------------------------

// The middle of a widget (its path of names: window, widget), in the pixels of the screen; false when it is not on this screen
aim :: proc(target: ^kit.Vec2, window: string, widget: string) -> bool {
    rect, found := ui.UiElementRect(&ui_state.ctx, ui.UiIdPath(window, widget))
    if !found { return false }
    target^ = {rect.x + rect.z * 0.5, rect.y + rect.w * 0.5}
    return true
}
