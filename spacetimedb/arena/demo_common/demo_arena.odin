#+build !js
package demo_common

// The arena: a small multiplayer game whose whole world lives in a SpacetimeDB database (arena/module), for people to try the library with. Move with WASD or the arrows and pick up the
// coins; everybody sees the same field. The start screen (no arguments) offers the three ways to play:
//
//   Play solo        this program starts a server and the game; nobody else can join
//   Host a game      the same, and a p2p invite code is drawn for friends (Copy code puts it on the clipboard). With the free relay a friend joins with this one code, even behind strict
//                    NATs; without it the friend sends a reply code back: paste it into the field "reply from a friend"
//   Join a game      paste the code of a host (Ctrl+V or the Paste button) and press Connect
//
// The same from the command line (the start screen is skipped): `arena host --derp`, `arena join <code> [name]`, `arena <name>` (the start screen with the name filled in). `--internet` adds
// the public address (STUN), `--port N` is the port of the server. A guest has no server: its game reaches the host's database through a tunnel over the p2p link (spacetimedb/tunnel).
// Escape leaves a game.

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import kit "../../../demo_kit"
import game_lib "../game"
import "../session"
import schema "../schema"

Mode :: enum u8 {
    SOLO,
    HOST,
    JOIN,
}

Config :: struct {
    parsed: bool,
    menu: bool,             // show the start screen (no mode was given)
    mode: Mode,
    invite: string,         // join: the code of the host
    name: string,
    internet: bool,
    derp: bool,
    root: string,           // the folder of the server of a host
    port: int,
    sleep_ms: int,          // a test sleeps in each frame: the network needs real time while a headless run has none
}

config: Config

Phase :: enum u8 {
    MENU,
    JOIN_FORM,
    STARTING,
    WAITING,                // a guest: the p2p connection to the host is not up yet
    PLAYING,
    FAILED,
}

State :: struct {
    phase: Phase,
    pending: Maybe(Mode),   // chosen on the start screen: done in the next update, so that "starting..." is drawn first (starting a server takes a moment)
    error: [256]u8,
    error_length: int,
    status: [160]u8,        // a message on the start screen
    status_length: int,
    host: ^session.Host,
    guest: ^session.Guest,
    game: ^game_lib.Game,
    invite_lines: [8][96]u8,
    invite_line_lengths: [8]int,
    invite_line_count: int,
    reply_line: [1024]u8,   // a line typed into the console of a host
    min_x, max_x: f32,      // where this player has been (the test of the demo reads it)
    started: time.Tick,
    paste_message: [96]u8,
    paste_length: int,
    // the start screen
    name: [24]u8,
    name_length: int,
    code: [1024]u8,
    code_length: int,
    reply: [1024]u8,
    reply_length: int,
    focus_name, focus_code, focus_reply: bool,
    relay, stun: bool,
    console: bool,          // the console of the process is read for reply codes (started from the command line)
    copy_rect: kit.Rect,    // where the Copy code button was drawn (the test clicks it)
}

state: State

fail :: proc(message: string) {
    if config.menu {
        backToMenu(message)
        return
    }
    state.phase = .FAILED
    state.error_length = copy(state.error[:], message)
    fmt.eprintln("arena:", message)
}

parseArguments :: proc() {
    config.parsed = true
    positional: [dynamic]string
    positional.allocator = context.temp_allocator
    for i := 1; i < len(os.args); i += 1 {
        switch os.args[i] {
        case "--derp": config.derp = true
        case "--internet": config.internet = true
        case "--port":
            i += 1
            if i < len(os.args) { config.port = parsePort(os.args[i]) }
        case: append(&positional, os.args[i])
        }
    }
    config.menu = true
    if len(positional) > 0 && positional[0] == "host" {
        config.mode, config.menu = .HOST, false
        if len(positional) > 1 { config.name = strings.clone(positional[1]) }
    } else if len(positional) > 0 && positional[0] == "join" {
        config.mode, config.menu = .JOIN, false
        if len(positional) > 1 { config.invite = strings.clone(positional[1]) }
        if len(positional) > 2 { config.name = strings.clone(positional[2]) }
    } else if len(positional) > 0 {
        config.name = strings.clone(positional[0])
    }
}

@(private = "file")
parsePort :: proc(text: string) -> (port: int) {
    for c in text {
        if c < '0' || c > '9' { return 0 }
        port = port * 10 + int(c - '0')
    }
    return
}

@(private = "file")
defaultName :: proc() -> string {
    if config.name != "" { return config.name }
    for variable in ([2]string{"USERNAME", "USER"}) {
        name: string = os.get_env(variable, context.temp_allocator)
        if name != "" { return name[:min(len(name), 20)] }
    }
    return "player"
}

@(private = "file")
playerName :: proc() -> string {
    return string(state.name[:state.name_length])
}

// The invite as lines that fit the side panel
@(private = "file")
splitInvite :: proc(code: string) {
    state.invite_line_count = 0
    rest: string = code
    for len(rest) > 0 && state.invite_line_count < len(state.invite_lines) {
        length: int = min(len(rest), 44)
        state.invite_line_lengths[state.invite_line_count] = copy(state.invite_lines[state.invite_line_count][:], rest[:length])
        state.invite_line_count += 1
        rest = rest[length:]
    }
}

@(private = "file")
setStatus :: proc(message: string) {
    state.status_length = copy(state.status[:], message)
}

init :: proc(ctx: ^kit.Context) {
    state = {}
    state.started = time.tick_now()
    ctx.background = {24, 28, 38, 255}
    if !config.parsed { parseArguments() }
    state.game = new(game_lib.Game)
    state.name_length = copy(state.name[:], defaultName())
    state.relay, state.stun = config.derp, config.internet
    if config.invite != "" { state.code_length = copy(state.code[:], config.invite) }
    if config.menu {
        state.phase = .MENU
    } else {
        state.pending = config.mode
        state.phase = .STARTING
    }
}

// Stops whatever is running and shows the start screen again (with a message, when there is one)
backToMenu :: proc(message: string = "") {
    teardown()
    state.game = new(game_lib.Game)
    state.phase = .MENU
    setStatus(message)
    if message != "" { fmt.eprintln("arena:", message) }
}

@(private = "file")
teardown :: proc() {
    session.ClearIdle()
    if state.game != nil {
        game_lib.GameClose(state.game)
        free(state.game)
        state.game = nil
    }
    if state.host != nil {
        session.HostStop(state.host)
        free(state.host)
        state.host = nil
    }
    if state.guest != nil {
        session.GuestStop(state.guest)
        free(state.guest)
        state.guest = nil
    }
    state.invite_line_count = 0
    state.paste_length = 0
}

finit :: proc(ctx: ^kit.Context) {
    teardown()
    state = {}
}

// Does what was chosen: starts the server and the game, or joins a host
@(private = "file")
launch :: proc(mode: Mode) {
    name: string = playerName()
    if name == "" { name = "player" }
    switch mode {
    case .SOLO, .HOST:
        state.host = new(session.Host)
        root: string = config.root if config.root != "" else "arena_server"
        if !session.HostStart(state.host, {root = root, port = config.port, name = name, internet = mode == .HOST && state.stun, derp = mode == .HOST && state.relay}) {
            fail(state.host.error)
            return
        }
        if mode == .HOST {
            code: string = session.HostInvite(state.host)
            splitInvite(code)
            fmt.println("Give this code to your friends (arena join <code>):")
            fmt.println(code)
            if !config.menu {
                fmt.println("If it does not use a relay (--derp), paste the reply code of each friend here and press Enter.")
                consoleStart()
                state.console = true
            }
        }
        if !game_lib.GameOpen(state.game, state.host.server.endpoint, name) {
            fail(state.game.error)
            return
        }
        state.phase = .PLAYING
    case .JOIN:
        state.guest = new(session.Guest)
        code: string = strings.trim_space(string(state.code[:state.code_length]))
        if code == "" {
            fail("paste the code of the host first")
            return
        }
        if !session.GuestJoin(state.guest, code, {internet = state.stun, name = name}) {
            fail(state.guest.error)
            return
        }
        fmt.println("Connecting to the host. If its code did not name a relay, send this reply code back to the host:")
        fmt.println(session.GuestReply(state.guest))
        splitInvite(session.GuestReply(state.guest))
        state.phase = .WAITING
    }
}

update :: proc(ctx: ^kit.Context) {
    if config.sleep_ms > 0 { time.sleep(time.Duration(config.sleep_ms) * time.Millisecond) }
    if mode, chosen := state.pending.?; chosen {
        state.pending = nil
        launch(mode)
        return
    }
    if state.phase == .MENU || state.phase == .JOIN_FORM || state.phase == .STARTING { return }
    if config.menu && kit.KeyPressed(&ctx.input, .ESCAPE) {
        backToMenu()
        return
    }
    if state.phase == .FAILED { return }
    if state.host != nil {
        session.HostUpdate(state.host)
        if state.console {
            line: string = consoleLine(state.reply_line[:])
            if line != "" { acceptReply(line) }
        }
    }
    if state.guest != nil {
        session.GuestUpdate(state.guest)
        if state.phase == .WAITING && session.GuestConnected(state.guest) && session.GuestStartTunnel(state.guest) {
            session.SetIdle(state.guest)
            if !game_lib.GameOpen(state.game, session.GuestEndpoint(state.guest), playerName()) {
                fail(state.game.error)
                return
            }
            state.phase = .PLAYING
        }
    }
    if state.phase != .PLAYING { return }
    game: ^game_lib.Game = state.game
    game_lib.GamePoll(game)
    // the keys go to the game unless a text field has the focus
    if !(state.focus_reply || state.focus_code || state.focus_name) {
        dx: i8 = i8(kit.AxisKeys(&ctx.input, .A, .D)) + i8(kit.AxisKeys(&ctx.input, .LEFT, .RIGHT))
        dy: i8 = i8(kit.AxisKeys(&ctx.input, .W, .S)) + i8(kit.AxisKeys(&ctx.input, .UP, .DOWN))
        game_lib.GameInput(game, clamp(dx, -1, 1), clamp(dy, -1, 1))
    } else {
        game_lib.GameInput(game, 0, 0)
    }
    game_lib.GameSmooth(game, ctx.delta_time)
    if me, found := game_lib.GameMe(game); found {
        if state.max_x == 0 { state.min_x, state.max_x = me.x, me.x }
        state.min_x, state.max_x = min(state.min_x, me.x), max(state.max_x, me.x)
    }
}

@(private = "file")
acceptReply :: proc(text: string) {
    if state.host != nil && session.HostAcceptReply(state.host, strings.trim_space(text)) {
        state.paste_length = copy(state.paste_message[:], "reply accepted: the friend is connecting")
    } else {
        state.paste_length = copy(state.paste_message[:], "that is not a reply code for this game")
    }
}

// A colour from a hue 0..255
@(private = "file")
hueColor :: proc(hue: u8) -> kit.Color {
    h: f32 = f32(hue) / 255 * 6
    x: f32 = 1 - abs(h - 2 * f32(int(h / 2)) - 1)
    r, g, b: f32
    switch int(h) {
    case 0: r, g, b = 1, x, 0
    case 1: r, g, b = x, 1, 0
    case 2: r, g, b = 0, 1, x
    case 3: r, g, b = 0, x, 1
    case 4: r, g, b = x, 0, 1
    case: r, g, b = 1, 0, x
    }
    return {u8(60 + r * 195), u8(60 + g * 195), u8(60 + b * 195), 255}
}

FIELD_X :: 40
FIELD_Y :: 60

// Where the start screen is drawn: the middle column of the 1280 x 720 window
MENU_X :: 440
MENU_WIDTH :: 400

draw :: proc(ctx: ^kit.Context) {
    switch state.phase {
    case .MENU: drawMenu(ctx)
    case .JOIN_FORM: drawJoinForm(ctx)
    case .STARTING:
        kit.DrawTextCentered(ctx, "starting...", {640, 340}, 32, kit.YELLOW)
    case .WAITING, .PLAYING, .FAILED: drawGame(ctx)
    }
}

@(private = "file")
drawStatus :: proc(ctx: ^kit.Context, y: f32) {
    if state.status_length > 0 { kit.DrawTextCentered(ctx, string(state.status[:state.status_length]), {640, y}, 18, kit.ORANGE) }
}

@(private = "file")
drawMenu :: proc(ctx: ^kit.Context) {
    kit.DrawTextCentered(ctx, "ARENA", {640, 110}, 64, kit.RAY_WHITE)
    kit.DrawTextCentered(ctx, "a game on a SpacetimeDB database, played over p2p", {640, 160}, 18, kit.LIGHT_GRAY)
    kit.DrawText(ctx, "your name", {MENU_X, 208}, 16, kit.LIGHT_GRAY)
    kit.TextField(ctx, {MENU_X, 230, MENU_WIDTH, 32}, state.name[:], &state.name_length, &state.focus_name, "your name")
    if kit.Button(ctx, {MENU_X, 290, MENU_WIDTH, 44}, "Play solo") && state.name_length > 0 {
        state.pending, state.phase = .SOLO, .STARTING
        setStatus("")
    }
    if kit.Button(ctx, {MENU_X, 344, MENU_WIDTH, 44}, "Host a game") && state.name_length > 0 {
        state.pending, state.phase = .HOST, .STARTING
        setStatus("")
    }
    if kit.Button(ctx, {MENU_X, 398, MENU_WIDTH, 44}, "Join a game") {
        state.phase = .JOIN_FORM
        setStatus("")
    }
    kit.Toggle(ctx, {MENU_X, 466, MENU_WIDTH, 28}, "free relay: friends join with one code (host)", &state.relay)
    kit.Toggle(ctx, {MENU_X, 500, MENU_WIDTH, 28}, "public address: friends on other networks", &state.stun)
    if state.name_length == 0 { setStatus("type a name first") }
    drawStatus(ctx, 560)
    kit.DrawTextCentered(ctx, "WASD or the arrows move, Escape leaves a game", {640, 660}, 16, kit.GRAY)
}

@(private = "file")
drawJoinForm :: proc(ctx: ^kit.Context) {
    kit.DrawTextCentered(ctx, "Join a game", {640, 110}, 40, kit.RAY_WHITE)
    kit.DrawText(ctx, "paste the code of the host (Ctrl+V)", {160, 218}, 16, kit.LIGHT_GRAY)
    kit.TextField(ctx, {160, 240, 780, 32}, state.code[:], &state.code_length, &state.focus_code, "the code of the host")
    if kit.Button(ctx, {960, 240, 160, 32}, "Paste") {
        state.code_length = 0
        kit.TextFieldPaste(ctx, state.code[:], &state.code_length)
    }
    if kit.Button(ctx, {MENU_X, 320, MENU_WIDTH, 44}, "Connect") && state.name_length > 0 {
        state.pending, state.phase = .JOIN, .STARTING
        setStatus("")
    }
    if kit.Button(ctx, {MENU_X, 374, MENU_WIDTH, 36}, "Back") {
        state.phase = .MENU
        setStatus("")
    }
    drawStatus(ctx, 450)
}

@(private = "file")
drawGame :: proc(ctx: ^kit.Context) {
    kit.DrawText(ctx, "ARENA   WASD / arrows: move, pick up the coins   Escape: leave" if config.menu else "ARENA   WASD / arrows: move, pick up the coins", {FIELD_X, 20}, 22, kit.RAY_WHITE)
    kit.DrawRect(ctx, {FIELD_X, FIELD_Y, game_lib.FIELD_WIDTH, game_lib.FIELD_HEIGHT}, {38, 46, 62, 255})
    kit.DrawRectOutline(ctx, {FIELD_X, FIELD_Y, game_lib.FIELD_WIDTH, game_lib.FIELD_HEIGHT}, 2, {90, 110, 150, 255})
    panel_x: f32 = FIELD_X + game_lib.FIELD_WIDTH + 30
    if state.phase == .FAILED {
        kit.DrawText(ctx, string(state.error[:state.error_length]), {panel_x, FIELD_Y}, 20, kit.RED)
        return
    }
    if state.phase == .WAITING {
        kit.DrawText(ctx, "connecting to the host...", {FIELD_X + 20, FIELD_Y + 20}, 24, kit.YELLOW)
        kit.DrawText(ctx, "reply code (if the host needs it):", {panel_x, FIELD_Y}, 18, kit.LIGHT_GRAY)
        for i in 0 ..< state.invite_line_count {
            kit.DrawText(ctx, string(state.invite_lines[i][:state.invite_line_lengths[i]]), {panel_x, FIELD_Y + 26 + f32(i) * 18}, 14, kit.LIGHT_GRAY)
        }
        if state.guest != nil && kit.Button(ctx, {panel_x, FIELD_Y + 40 + f32(state.invite_line_count) * 18, 120, 26}, "Copy reply") {
            kit.ClipboardSet(ctx, session.GuestReply(state.guest))
        }
        return
    }
    game: ^game_lib.Game = state.game
    for i in 0 ..< game.coin_count {
        coin: schema.Coin = game.coins[i]
        kit.DrawCircle(ctx, {FIELD_X + coin.x, FIELD_Y + coin.y}, 8, kit.YELLOW)
    }
    me, has_me := game_lib.GameMe(game)
    for i in 0 ..< game.player_count {
        player: ^schema.Player = &game.players[i]
        x, y: f32 = game_lib.GamePosition(game, player)
        center: kit.Vec2 = {FIELD_X + x, FIELD_Y + y}
        kit.DrawCircle(ctx, center, 14, hueColor(player.hue))
        if has_me && player.id == me.id { kit.DrawCircleOutline(ctx, center, 17, 2, kit.WHITE) }
        kit.DrawTextCentered(ctx, player.name, {center.x, center.y - 26}, 16, kit.RAY_WHITE)
    }

    // the side panel: who is here, the connection, the invite
    kit.DrawText(ctx, "players", {panel_x, FIELD_Y}, 20, kit.RAY_WHITE)
    order: [game_lib.PLAYERS_MAX]int
    for i in 0 ..< game.player_count { order[i] = i }
    for i in 1 ..< game.player_count {
        for j := i; j > 0 && game.players[order[j]].score > game.players[order[j - 1]].score; j -= 1 { order[j], order[j - 1] = order[j - 1], order[j] }
    }
    for rank in 0 ..< game.player_count {
        player: ^schema.Player = &game.players[order[rank]]
        kit.DrawCircle(ctx, {panel_x + 8, FIELD_Y + 40 + f32(rank) * 24}, 7, hueColor(player.hue))
        kit.DrawText(ctx, fmt.tprintf("%s  %d", player.name, player.score), {panel_x + 24, FIELD_Y + 31 + f32(rank) * 24}, 18, kit.WHITE)
    }
    y: f32 = FIELD_Y + 40 + f32(game.player_count) * 24 + 30
    status: string = "connected" if game.phase == .PLAYING else fmt.tprintf("%v", game.phase)
    via: string = "your own server" if state.guest == nil else "the host through p2p"
    kit.DrawText(ctx, fmt.tprintf("%s (%s)", status, via), {panel_x, y}, 16, kit.LIGHT_GRAY)
    if state.host != nil && state.invite_line_count > 0 {
        y += 34
        kit.DrawText(ctx, fmt.tprintf("friends connected: %d", session.HostGuests(state.host)), {panel_x, y}, 16, kit.LIGHT_GRAY)
        y += 24
        kit.DrawText(ctx, "invite code:", {panel_x, y}, 14, kit.GRAY)
        for i in 0 ..< state.invite_line_count {
            kit.DrawText(ctx, string(state.invite_lines[i][:state.invite_line_lengths[i]]), {panel_x, y + 18 + f32(i) * 15}, 12, kit.LIGHT_GRAY)
        }
        y += 24 + f32(state.invite_line_count) * 15
        state.copy_rect = {panel_x, y, 120, 26}
        if kit.Button(ctx, {panel_x, y, 120, 26}, "Copy code") { kit.ClipboardSet(ctx, session.HostInvite(state.host)) }
        y += 36
        kit.DrawText(ctx, "reply from a friend (no relay):", {panel_x, y}, 14, kit.GRAY)
        submitted: bool = kit.TextField(ctx, {panel_x, y + 20, 150, 26}, state.reply[:], &state.reply_length, &state.focus_reply, "paste")
        if kit.Button(ctx, {panel_x + 156, y + 20, 70, 26}, "Paste") {
            state.reply_length = 0
            kit.TextFieldPaste(ctx, state.reply[:], &state.reply_length)
            submitted = true
        }
        if submitted && state.reply_length > 0 {
            acceptReply(string(state.reply[:state.reply_length]))
            state.reply_length = 0
        }
        if state.paste_length > 0 { kit.DrawText(ctx, string(state.paste_message[:state.paste_length]), {panel_x, y + 52}, 14, kit.ORANGE) }
    }
    if game.error != "" { kit.DrawText(ctx, game.error, {panel_x, FIELD_Y + game_lib.FIELD_HEIGHT - 20}, 14, kit.RED) }
}

demo_arena: kit.Demo = {
    name = "arena",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}
