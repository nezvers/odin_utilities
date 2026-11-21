#+build !js
package demo_common

// The arena: a small multiplayer game whose whole world lives in a SpacetimeDB database (arena/module), for people to try the library with. Move with WASD or the arrows and pick up the
// coins; everybody sees the same field. The windows (start screen, code, connection, players) are made with `odin_utilities/ui` (screens.odin); the field is drawn with the demo kit.
// The start screen (no arguments) offers the three ways to play:
//
//   Play solo        this program starts a server and the game; nobody else can join
//   Host a game      the same, and a p2p invite code for friends (Copy the invite code puts it on the clipboard). With the free relay a friend joins with this one code, even behind strict
//                    NATs; without it the friend sends a reply code back: paste it into the field "Reply" of the connection window
//   Join a game      paste the code of a host (Ctrl+V or the Paste button) and press Connect: the steps of the connection are shown
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
    loopback: bool,         // a test: also offer 127.0.0.1 in the p2p codes
    mask_codes: bool,       // pictures: the codes are shown as a fixed text (see screens.odin)
    idle_host: ^session.Host,   // a test that hosts in the same process: stepped while the guest waits in a blocking call
}

// A test that has something to do every frame (another host to step)
frame_hook: proc()

config: Config

Phase :: enum u8 {
    MENU,
    JOIN_FORM,
    STARTING,               // the server is being started (a moment): drawn first, done in the next update
    CONNECTING,             // a guest: the p2p connection to the host is being made (the steps are shown)
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
    hosting: bool,          // the host shows an invite (Host a game, not Play solo)
    guest_tunnel_open: bool,
    printed: bool,          // the invite or the reply code went to the console
    reply_line: [1024]u8,   // a line typed into the console of a host
    min_x, max_x: f32,      // where this player has been (the test of the demo reads it)
    started: time.Tick,
    paste_message: [96]u8,
    paste_length: int,
    name: [24]u8,
    name_length: int,
    code: [1024]u8,
    code_length: int,
    reply: [1024]u8,
    reply_length: int,
    relay, stun: bool,
    console: bool,          // the console of the process is read for reply codes (started from the command line)
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
    uiInit()
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
    state.hosting, state.guest_tunnel_open, state.printed = false, false, false
    state.paste_length = 0
}

finit :: proc(ctx: ^kit.Context) {
    teardown()
    state = {}
}

// Does what was chosen: starts the server and the game, or begins joining a host
@(private = "file")
launch :: proc(mode: Mode) {
    name: string = playerName()
    if name == "" { name = "player" }
    switch mode {
    case .SOLO, .HOST:
        state.host = new(session.Host)
        root: string = config.root if config.root != "" else "arena_server"
        if !session.HostBegin(state.host, {root = root, port = config.port, name = name, internet = mode == .HOST && state.stun, derp = mode == .HOST && state.relay}) {
            fail(state.host.error)
            return
        }
        state.hosting = mode == .HOST
        if state.hosting && !config.menu {
            consoleStart()
            state.console = true
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
        options: session.GuestOptions = {internet = state.stun, name = name, loopback = config.loopback}
        began: bool = session.GuestBeginRoom(state.guest, code, options) if looksLikeRoom(code) else session.GuestBegin(state.guest, code, options)
        if !began {
            fail(state.guest.error)
            return
        }
        state.phase = .CONNECTING
    }
}

// A room name is short (maple-otter-22); an invite code is a hundred letters in groups of five
looksLikeRoom :: proc(text: string) -> bool {
    if len(text) > 48 || strings.contains_rune(text, ' ') { return false }
    dash: int = strings.last_index_byte(text, '-')
    if dash <= 0 || dash + 1 >= len(text) { return false }
    for c in text[dash + 1:] { if c < '0' || c > '9' { return false } }
    return strings.count(text, "-") <= 3
}

update :: proc(ctx: ^kit.Context) {
    if config.sleep_ms > 0 { time.sleep(time.Duration(config.sleep_ms) * time.Millisecond) }
    if frame_hook != nil { frame_hook() }
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
        if state.hosting && state.host.stage == .READY && !state.printed {
            state.printed = true
            fmt.println("Give this code to your friends (arena join <code>):")
            fmt.println(session.HostInvite(state.host))
            if room := session.HostRoom(state.host); room != "" { fmt.printfln("Or the room name (arena join %s) when the relay is up.", room) }
            if state.console { fmt.println("If it does not use a relay (--derp), paste the reply code of each friend here and press Enter.") }
        }
        if state.console {
            line: string = consoleLine(state.reply_line[:])
            if line != "" { acceptReply(line) }
        }
    }
    if state.guest != nil {
        session.GuestUpdate(state.guest)
        if state.guest.stage == .FAILED {
            fail(state.guest.error)
            return
        }
        if state.guest.stage == .READY && !state.printed {
            state.printed = true
            fmt.println("Connecting to the host. If its code did not name a relay, send this reply code back to the host:")
            fmt.println(session.GuestReply(state.guest))
        }
        if state.phase == .CONNECTING && state.guest.stage == .CONNECTED && session.GuestStartTunnel(state.guest) {
            state.guest_tunnel_open = true
            session.SetIdle(state.guest, config.idle_host)
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
    // the keys go to the game unless a text field has the keyboard
    if !textFieldFocused() {
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

draw :: proc(ctx: ^kit.Context) {
    if state.phase == .PLAYING { drawField(ctx) }
    uiFrame(ctx)
}

// The field with the coins and the players: the kit draws it, the windows over it are the ui's
@(private = "file")
drawField :: proc(ctx: ^kit.Context) {
    kit.DrawRect(ctx, {FIELD_X, FIELD_Y, game_lib.FIELD_WIDTH, game_lib.FIELD_HEIGHT}, {38, 46, 62, 255})
    kit.DrawRectOutline(ctx, {FIELD_X, FIELD_Y, game_lib.FIELD_WIDTH, game_lib.FIELD_HEIGHT}, 2, {90, 110, 150, 255})
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
}

demo_arena: kit.Demo = {
    name = "arena",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = menu_script,       // the start screen, a solo game, a hosted game, a friend, a guest: with the pictures of each screen
}

// The solo game started from the command line (no start screen): the test of that way in
demo_arena_solo: kit.Demo = {
    name = "arena solo",
    init = init,
    finit = finit,
    update = update,
    draw = draw,
    script = script,
}
