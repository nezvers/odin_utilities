#+build !js
package arena_game

// The client of the arena game, without a window: it connects to the database, joins with a name, keeps the rows of `player` and `coin` in a cache, and sends the direction the player holds.
// A window (demo_common) only reads `players`, `coins` and `me` once a frame and draws them. The game itself runs in the database (arena/module); this is the part that every client has.
//
//     game: ^Game = new(Game)                                  // about 200 KB
//     GameOpen(game, {host = "127.0.0.1", port = 3000}, "Ada")
//     every frame: GamePoll(game); GameInput(game, dx, dy); GameSmooth(game, dt); draw game.players[:game.player_count]
//
// The rows come from the generated code of arena/schema (`odin run spacetimedb/arena/tool/schema` writes it from the module): `schema.Player`, `schema.CallJoin`, `schema.CallSetInput`.

import "base:runtime"
import "core:time"
import st "../.."
import schema "../schema"

PLAYERS_MAX :: 16
COINS_MAX :: 32
FIELD_WIDTH :: 800
FIELD_HEIGHT :: 600

Phase :: enum u8 {
    CLOSED,
    CONNECTING,         // the socket is open, the server has not greeted us yet
    JOINING,            // subscribed and joined, waiting for the first rows
    PLAYING,
    LOST,               // the connection is gone (it is reopened by itself)
}

// Where a player is drawn: it follows the position of the database with a delay, so the 20 steps per second of the server look smooth
Smooth :: struct {
    id: u64,
    x, y: f32,
}

Game :: struct {
    connection: st.Connection,
    receive: [1 << 16]u8,
    message: [1 << 16]u8,
    cache: st.Cache,
    slots: [128]st.CacheSlot,
    buckets: [128]i32,
    bytes: [1 << 14]u8,
    events: [64]st.CacheEvent,
    tables_storage: [4]st.CacheTable,
    tables: schema.Tables,
    phase: Phase,
    name: [32]u8,
    name_length: int,
    host: [64]u8,                       // the connection keeps its strings by reference
    host_length: int,
    players: [PLAYERS_MAX]schema.Player,
    player_count: int,
    coins: [COINS_MAX]schema.Coin,
    coin_count: int,
    smooth: [PLAYERS_MAX]Smooth,
    input_dx, input_dy: i8,
    sent_dx, sent_dy: i8,
    error: string,                      // the last refusal of the server (a reducer result) or of the connection
    picked_up: int,                     // coins that disappeared from the field since the start (for sounds and effects: read and reset)
    opened: time.Tick,                  // when `GameOpen` was called
    greeted_ms: f32,                    // how long after that the server greeted us (InitialConnection), 0: not yet
    synced_ms: f32,                     // and how long until the first rows of the database came (SubscribeApplied): the field is drawn from then on, 0: not yet
}

// How long the game has been waiting for the first rows of the database, in milliseconds (0 once they came): what a window shows instead of an empty field
GameWaitingMs :: proc(game: ^Game) -> f32 {
    if game.phase == .CLOSED || game.synced_ms > 0 { return 0 }
    return f32(time.duration_milliseconds(time.tick_since(game.opened)))
}

GameName :: proc(game: ^Game) -> string {
    return string(game.name[:game.name_length])
}

// Connects. The phases follow in GamePoll. False when the socket could not be opened.
// `token`: the ID token of a signed in player (oidc, see spacetimedb/auth.odin): the identity is then the one of the person, the same in every game. `refresh` (with `refresh_user`) renews it at a reconnect.
GameOpen :: proc(game: ^Game, endpoint: st.Endpoint, name: string, token: string = "", refresh: proc(user: rawptr) -> string = nil, refresh_user: rawptr = nil) -> bool {
    game^ = {}
    game.opened = time.tick_now()
    game.name_length = copy(game.name[:], name)
    game.host_length = copy(game.host[:], endpoint.host)
    st.CacheInit(&game.cache, {slots = game.slots[:], buckets = game.buckets[:], bytes = game.bytes[:], events = game.events[:], tables = game.tables_storage[:]})
    game.tables = schema.TablesAdd(&game.cache)
    config: st.ConnectionConfig = {endpoint = {host = string(game.host[:game.host_length]), port = endpoint.port, secure = endpoint.secure}, database = "arena", token = token, refresh = refresh, refresh_user = refresh_user}
    if !st.ConnectionOpen(&game.connection, config, game.receive[:], game.message[:]) {
        game.error = game.connection.error
        return false
    }
    game.phase = .CONNECTING
    return true
}

GameClose :: proc(game: ^Game) {
    if game.phase != .CLOSED { st.ConnectionClose(&game.connection) }
    game.phase = .CLOSED
}

// The identity of this client and its row, when it has joined
GameMe :: proc(game: ^Game) -> (player: ^schema.Player, found: bool) {
    for i in 0 ..< game.player_count {
        if game.players[i].owner == game.connection.identity { return &game.players[i], true }
    }
    return nil, false
}

// The token to keep: with it the next start is the same player (the same identity owns the same row)
GameToken :: proc(game: ^Game) -> string {
    return st.ConnectionToken(&game.connection)
}

// Reads what the network has, keeps the cache and the lists for drawing up to date, reconnects when the connection was lost. Once a frame.
GamePoll :: proc(game: ^Game) {
    if game.phase == .CLOSED { return }
    arena: runtime.Arena
    allocator: runtime.Allocator = runtime.arena_allocator(&arena)
    defer runtime.arena_destroy(&arena)
    coins_before: int = game.coin_count
    for {
        message, got := st.ConnectionPoll(&game.connection, allocator)
        if !got { break }
        st.CacheApply(&game.cache, message)
        #partial switch value in message {
        case st.InitialConnection:
            game.greeted_ms = max(f32(time.duration_milliseconds(time.tick_since(game.opened))), 1)
            schema.SubscribeAll(&game.connection, 1)
            schema.CallJoin(&game.connection, GameName(game))
            game.phase = .JOINING
        case st.SubscribeApplied:
            game.phase = .PLAYING
            if game.synced_ms == 0 { game.synced_ms = max(f32(time.duration_milliseconds(time.tick_since(game.opened))), 1) }
        case st.ReducerResult:
            if value.outcome == .ERROR {
                reader: st.Reader = st.ReaderMake(value.value)
                game.error = st.ReadString(&reader)
            }
        }
    }
    if game.connection.dropped {
        game.phase = .LOST
        if st.ConnectionMaintain(&game.connection) {
            st.CacheClear(&game.cache)
            game.tables = schema.TablesAdd(&game.cache)
            game.phase = .CONNECTING
            game.sent_dx, game.sent_dy = 0, 0
        }
    }
    game.player_count = len(st.CacheCollect(&game.cache, game.tables.player, schema.PlayerRead, game.players[:]))
    game.coin_count = len(st.CacheCollect(&game.cache, game.tables.coin, schema.CoinRead, game.coins[:]))
    for event in st.CacheEvents(&game.cache) {
        if event.table == game.tables.coin && event.kind == .DELETE { game.picked_up += 1 }
    }
    st.CacheClearEvents(&game.cache)
    _ = coins_before
}

// The direction that is held (each -1, 0 or 1): sent to the database when it changed
GameInput :: proc(game: ^Game, dx: i8, dy: i8) {
    game.input_dx, game.input_dy = dx, dy
    if game.phase != .PLAYING || (dx == game.sent_dx && dy == game.sent_dy) { return }
    if schema.CallSetInput(&game.connection, dx, dy) != 0 { game.sent_dx, game.sent_dy = dx, dy }
}

// Moves what is drawn towards where the database has the players (`dt` in seconds)
GameSmooth :: proc(game: ^Game, dt: f32) {
    follow: f32 = min(1, dt * 14)
    for i in 0 ..< game.player_count {
        player: ^schema.Player = &game.players[i]
        slot: ^Smooth
        for &entry in game.smooth {
            if entry.id == player.id { slot = &entry }
        }
        if slot == nil {
            for &entry in game.smooth {
                if entry.id == 0 {
                    slot = &entry
                    slot^ = {id = player.id, x = player.x, y = player.y}
                    break
                }
            }
        }
        if slot == nil { continue }
        slot.x += (player.x - slot.x) * follow
        slot.y += (player.y - slot.y) * follow
    }
    // forget the players that left
    for &entry in game.smooth {
        if entry.id == 0 { continue }
        present: bool
        for i in 0 ..< game.player_count { if game.players[i].id == entry.id { present = true } }
        if !present { entry = {} }
    }
}

// Where to draw a player
GamePosition :: proc(game: ^Game, player: ^schema.Player) -> (x: f32, y: f32) {
    for entry in game.smooth {
        if entry.id == player.id && entry.id != 0 { return entry.x, entry.y }
    }
    return player.x, player.y
}
