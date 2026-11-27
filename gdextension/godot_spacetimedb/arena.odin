#+build !js
package godot_spacetimedb

// The arena game (odin_utilities/spacetimedb/arena) for Godot: the class `ArenaClient` (a RefCounted) does everything of the Odin demo that is not drawing: it starts the server of a host, makes the p2p
// invite, joins a host by a code or a room name, connects the game client (through the tunnel for a guest), keeps the rows of `player` and `coin` and smooths the players. A script (arena_project) only
// calls `update` once a frame, `set_input` with the held direction, and draws `snapshot`. No thread, no callback into Godot.
//
// The snapshot (a PackedByteArray, little endian: read it with a StreamPeerBuffer):
//     u32 game phase (see GamePhase), u32 players, u32 coins, u32 coins picked up since the start, u64 id of this player (0: not joined yet)
//     per player: u64 id, f32 x, f32 y (where to draw: smoothed), u32 score, u32 hue (0..255), u8 name length, the name
//     per coin: u64 id, f32 x, f32 y
// The field is 800 x 600 (arena_game FIELD_WIDTH, FIELD_HEIGHT).

import "core:encoding/endian"
import "core:fmt"
import "core:strings"
import "core:time"
import ge "../../gdextension"
import game_lib "../../spacetimedb/arena/game"
import "../../spacetimedb/arena/session"

// What `phase()` says: where the whole thing is
ArenaPhase :: enum u8 {
    IDLE,               // nothing started
    CONNECTING,         // a guest: the p2p connection to the host is being made (`stage()` and `notice()` tell the steps)
    PLAYING,            // the game client is open (`game_phase()` tells whether the first rows came)
    FAILED,             // `error()` says why; `leave()` goes back to IDLE
}

// The bits of the `flags` of `host` and `join`
FLAG_P2P :: 1           // host: make an invite for friends (without it the game is solo; the server is the same)
FLAG_RELAY :: 2         // host: also use a free DERP relay (a friend joins with the room name or the one code, even behind strict NATs)
FLAG_INTERNET :: 4      // host and join: find the public address with STUN (needs the internet)
FLAG_LOOPBACK :: 8      // host and join: also offer 127.0.0.1 (two programs on one computer: tests)

SNAPSHOT_MAX :: 8192

// The host of this process (the last one started): a guest in the SAME process (a test, two clients in one script) steps it while it waits in a blocking call. Nil when there is none.
@(private = "file")
active_host: ^session.Host

Arena :: struct {
    phase: ArenaPhase,
    game: ^game_lib.Game,
    host: ^session.Host,
    guest: ^session.Guest,
    name: string,                       // heap copies: the session keeps strings by reference
    root: string,
    module: string,
    error: [400]u8,
    error_length: int,
    code: [512]u8,                      // the text that `code_from` returns
    snapshot: [SNAPSHOT_MAX]u8,
    picked_up: int,
}

@(private = "file")
arenaOf :: proc(instance: rawptr) -> ^Arena {
    return cast(^Arena)instance
}

@(private = "file")
arenaFail :: proc(arena: ^Arena, message: string) {
    arena.error_length = copy(arena.error[:], message)
    arena.phase = .FAILED
}

// Goes back to IDLE: closes the game, the server, the link
@(private = "file")
arenaLeave :: proc(arena: ^Arena) {
    if arena.game != nil {
        game_lib.GameClose(arena.game)
        free(arena.game)
        arena.game = nil
        // the close of the websocket travels through the tunnel: step it a few times so that the host hears it now and not after the p2p timeout
        if arena.guest != nil && arena.guest.tunnel_started {
            for _ in 0 ..< 12 {
                session.GuestUpdate(arena.guest)
                if active_host != nil { session.HostUpdate(active_host) }
                time.sleep(5 * time.Millisecond)
            }
        }
    }
    session.ClearIdle()
    if arena.host != nil {
        if active_host == arena.host { active_host = nil }
        session.HostStop(arena.host)
        free(arena.host)
        arena.host = nil
    }
    if arena.guest != nil {
        session.GuestStop(arena.guest)
        free(arena.guest)
        arena.guest = nil
    }
    delete(arena.name)
    delete(arena.root)
    delete(arena.module)
    arena.name, arena.root, arena.module = "", "", ""
    arena.error_length = 0
    arena.picked_up = 0
    arena.phase = .IDLE
}

// Starts the server with the game (a second or two: the call blocks), makes the invite for friends when asked, and opens the game on the server. False with `error()` set.
@(private = "file")
arenaHost :: proc(arena: ^Arena, name: string, root: string, port: int, flags: int, module: string) -> bool {
    arenaLeave(arena)
    arena.name = strings.clone(name if name != "" else "player")
    arena.root = strings.clone(root if root != "" else "arena_server")
    arena.module = strings.clone(module)
    arena.host = new(session.Host)
    arena.game = new(game_lib.Game)
    options: session.HostOptions = {
        root = arena.root, port = port, module_path = arena.module, name = arena.name,
        internet = flags & FLAG_P2P != 0 && flags & FLAG_INTERNET != 0,
        derp = flags & FLAG_P2P != 0 && flags & FLAG_RELAY != 0,
        loopback = flags & FLAG_LOOPBACK != 0,
    }
    if !session.HostBegin(arena.host, options) {
        arenaFail(arena, arena.host.error)
        return false
    }
    if !game_lib.GameOpen(arena.game, arena.host.server.endpoint, arena.name) {
        arenaFail(arena, arena.game.error)
        return false
    }
    active_host = arena.host
    arena.phase = .PLAYING
    return true
}

// Begins joining a host by the code of its invite or by its room name; `update` goes on until the game is open. False with `error()` set.
@(private = "file")
arenaJoin :: proc(arena: ^Arena, code: string, name: string, flags: int) -> bool {
    arenaLeave(arena)
    arena.name = strings.clone(name if name != "" else "player")
    arena.guest = new(session.Guest)
    arena.game = new(game_lib.Game)
    trimmed: string = strings.trim_space(code)
    if trimmed == "" {
        arenaFail(arena, "paste the code of the host first")
        return false
    }
    options: session.GuestOptions = {internet = flags & FLAG_INTERNET != 0, name = arena.name, loopback = flags & FLAG_LOOPBACK != 0}
    began: bool = session.GuestBeginRoom(arena.guest, trimmed, options) if session.RoomLooksLike(trimmed) else session.GuestBegin(arena.guest, trimmed, options)
    if !began {
        arenaFail(arena, arena.guest.error)
        return false
    }
    arena.phase = .CONNECTING
    return true
}

// Once a frame: the p2p side, the tunnel, the game client and the smoothing of the players
@(private = "file")
arenaUpdate :: proc(arena: ^Arena, delta_ms: int) {
    if arena.phase == .IDLE || arena.phase == .FAILED { return }
    if arena.host != nil { session.HostUpdate(arena.host) }
    if arena.guest != nil {
        session.GuestUpdate(arena.guest)
        if arena.guest.stage == .FAILED {
            arenaFail(arena, arena.guest.error)
            return
        }
        if arena.phase == .CONNECTING && arena.guest.stage == .CONNECTED && session.GuestStartTunnel(arena.guest) {
            // the tunnel is the way to the server: the blocking calls of the client step it while they wait
            session.SetIdle(arena.guest, active_host)
            if !game_lib.GameOpen(arena.game, session.GuestEndpoint(arena.guest), arena.name) {
                arenaFail(arena, arena.game.error)
                return
            }
            arena.phase = .PLAYING
        }
    }
    if arena.phase == .PLAYING {
        game_lib.GamePoll(arena.game)
        game_lib.GameSmooth(arena.game, f32(delta_ms) / 1000)
        arena.picked_up += arena.game.picked_up
        arena.game.picked_up = 0
    }
}

@(private = "file")
arenaSnapshot :: proc(arena: ^Arena) -> []u8 {
    buffer: []u8 = arena.snapshot[:]
    at: int
    put32 :: proc(buffer: []u8, at: ^int, value: u32) {
        endian.put_u32(buffer[at^:], .Little, value)
        at^ += 4
    }
    putf :: proc(buffer: []u8, at: ^int, value: f32) {
        endian.put_f32(buffer[at^:], .Little, value)
        at^ += 4
    }
    put64 :: proc(buffer: []u8, at: ^int, value: u64) {
        endian.put_u64(buffer[at^:], .Little, value)
        at^ += 8
    }
    game: ^game_lib.Game = arena.game
    if game == nil || arena.phase != .PLAYING {
        put32(buffer, &at, u32(game_lib.Phase.CLOSED))
        put32(buffer, &at, 0)
        put32(buffer, &at, 0)
        put32(buffer, &at, 0)
        put64(buffer, &at, 0)
        return buffer[:at]
    }
    put32(buffer, &at, u32(game.phase))
    put32(buffer, &at, u32(game.player_count))
    put32(buffer, &at, u32(game.coin_count))
    put32(buffer, &at, u32(arena.picked_up))
    me_id: u64
    if me, found := game_lib.GameMe(game); found { me_id = me.id }
    put64(buffer, &at, me_id)
    for i in 0 ..< game.player_count {
        player := &game.players[i]
        x, y := game_lib.GamePosition(game, player)
        put64(buffer, &at, player.id)
        putf(buffer, &at, x)
        putf(buffer, &at, y)
        put32(buffer, &at, player.score)
        put32(buffer, &at, u32(player.hue))
        length: int = min(len(player.name), 255)
        buffer[at] = u8(length)
        at += 1
        copy(buffer[at:], player.name[:length])
        at += length
    }
    for i in 0 ..< game.coin_count {
        coin := &game.coins[i]
        put64(buffer, &at, coin.id)
        putf(buffer, &at, coin.x)
        putf(buffer, &at, coin.y)
    }
    return buffer[:at]
}

@(private = "file")
stageOf :: proc(arena: ^Arena) -> session.Stage {
    if arena.host != nil { return arena.host.stage }
    if arena.guest != nil { return arena.guest.stage }
    return .IDLE
}

arena_class: ge.Class = {
    name = "ArenaClient",
    parent = "RefCounted",
    create = proc() -> rawptr { return new(Arena) },
    destroy = proc(instance: rawptr) {
        arenaLeave(arenaOf(instance))
        free(instance)
    },
    methods = {
        // host(name, root, port, flags, module): `root` is the folder of the server (OS.get_user_data_dir() + "/arena_server"), `port` 0 is 3000, `module` "" is the built module of the library
        {"host", {.STRING, .STRING, .INT, .INT, .STRING}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return boolOf(arenaHost(arenaOf(instance), string(a[0].text), string(a[1].text), int(a[2].number), int(a[3].number), string(a[4].text)))
        }},
        // join(code, name, flags): `code` is an invite code or a room name
        {"join", {.STRING, .STRING, .INT}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return boolOf(arenaJoin(arenaOf(instance), string(a[0].text), string(a[1].text), int(a[2].number)))
        }},
        {"update", {.INT}, .NONE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arenaUpdate(arenaOf(instance), int(a[0].number))
            return {}
        }},
        // set_input(dx, dy): the direction that is held, each -1, 0 or 1
        {"set_input", {.INT, .INT}, .NONE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arena: ^Arena = arenaOf(instance)
            if arena.game != nil { game_lib.GameInput(arena.game, i8(clamp(a[0].number, -1, 1)), i8(clamp(a[1].number, -1, 1))) }
            return {}
        }},
        {"leave", {}, .NONE, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arenaLeave(arenaOf(instance))
            return {}
        }},
        {"phase", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return intOf(i64(arenaOf(instance).phase)) }},
        // the step of the p2p connection: 0 idle, 1 gathering addresses, 2 waiting for the relay, 3 finding a room, 4 ready (a host: the invite is made; a guest: the reply is made), 5 connected, 6 failed
        {"stage", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value { return intOf(i64(stageOf(arenaOf(instance)))) }},
        // the phase of the game client: 0 closed, 1 connecting, 2 joining (waiting for the first rows), 3 playing, 4 connection lost
        {"game_phase", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arena: ^Arena = arenaOf(instance)
            return intOf(i64(arena.game.phase) if arena.game != nil else 0)
        }},
        {"waiting_ms", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arena: ^Arena = arenaOf(instance)
            return intOf(i64(game_lib.GameWaitingMs(arena.game)) if arena.game != nil else 0)
        }},
        {"invite", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arena: ^Arena = arenaOf(instance)
            return textOf(session.HostInvite(arena.host) if arena.host != nil else "")
        }},
        {"room", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arena: ^Arena = arenaOf(instance)
            return textOf(session.HostRoom(arena.host) if arena.host != nil else "")
        }},
        {"reply", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arena: ^Arena = arenaOf(instance)
            return textOf(session.GuestReply(arena.guest) if arena.guest != nil else "")
        }},
        {"notice", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arena: ^Arena = arenaOf(instance)
            if arena.host != nil { return textOf(session.HostNotice(arena.host)) }
            if arena.guest != nil { return textOf(session.GuestNotice(arena.guest)) }
            return textOf("")
        }},
        {"error", {}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arena: ^Arena = arenaOf(instance)
            return textOf(string(arena.error[:arena.error_length]))
        }},
        // accept_reply(text): a host pastes the reply code of a friend (needed when the invite names no relay)
        {"accept_reply", {.STRING}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arena: ^Arena = arenaOf(instance)
            return boolOf(arena.host != nil && session.HostAcceptReply(arena.host, strings.trim_space(string(a[0].text))))
        }},
        // a guest whose invite names no relay has to send its `reply()` back to the host
        {"needs_reply", {}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arena: ^Arena = arenaOf(instance)
            return boolOf(arena.guest != nil && !arena.guest.room_mode && (arena.guest.invite.derp_server == 0 || arena.guest.options.no_derp))
        }},
        // a host whose relay is up: a friend needs only the invite (or the room name), no reply
        {"relay_ready", {}, .BOOL, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arena: ^Arena = arenaOf(instance)
            return boolOf(arena.host != nil && arena.host.relay_used && arena.host.link.derp.state == .READY)
        }},
        // friends whose connection is made
        {"guests", {}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arena: ^Arena = arenaOf(instance)
            return intOf(i64(session.HostConnectedGuests(arena.host)) if arena.host != nil else 0)
        }},
        // what a pasted text is: 0 empty, 1 not a code, 2 an invite, 3 a reply, 4 a room name
        {"code_kind", {.STRING}, .INT, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            kind, _, _ := session.CodeInspect(string(a[0].text))
            return intOf(i64(kind))
        }},
        // who made the code (the name in it, or the room name)
        {"code_from", {.STRING}, .STRING, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            arena: ^Arena = arenaOf(instance)
            _, from, _ := session.CodeInspect(string(a[0].text))
            return textOf(string(arena.code[:copy(arena.code[:], from)]))
        }},
        {"snapshot", {}, .BYTES, proc(instance: rawptr, a: []ge.Value) -> ge.Value {
            return {kind = .BYTES, text = arenaSnapshot(arenaOf(instance))}
        }},
    },
}

_ :: fmt
