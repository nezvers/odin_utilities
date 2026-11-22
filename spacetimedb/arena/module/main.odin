package main

// The module of the arena game, written in Odin: the whole game runs in the database. Players join with a name, tell the server which way they hold their stick (`set_input`), and a scheduled
// reducer (`tick`, every 50 ms) moves everybody, lets them pick up coins and puts new coins on the field. Clients only send their input and draw the rows they subscribe to (`player`, `coin`).
// Build: `odin run spacetimedb/tool/build_module -- spacetimedb/arena/module spacetimedb/bin/arena-odin.wasm`.

import "../../bsatn"
import sdb "../../module"

FIELD_WIDTH :: 800.0
FIELD_HEIGHT :: 600.0
SPEED :: 6.0                // units per tick: 120 per second
PICKUP :: 22.0              // distance at which a player takes a coin
COIN_TARGET :: 8
MAX_PLAYERS :: 16
MAX_COINS :: 32
TICK_MICROSECONDS :: 50_000

Player :: struct {
    id: u64,
    owner: bsatn.Identity,
    name: [32]u8,
    name_length: int,
    x, y: f32,
    dx, dy: i8,
    score: u32,
    hue: u8,
    connection: bsatn.ConnectionId, // the connection that owns the player now: the last one that joined. A person who comes back (the same identity) takes the player over, and the disconnect of
                                    // the OLD connection must not remove it (the identity of a signed in person is the same in every window)
}

Coin :: struct {
    id: u64,
    x, y: f32,
}

players, coins, world, ticks: sdb.Table

PLAYER_COLUMNS :: []sdb.Column{{"id", .U64, nil}, {"owner", .IDENTITY, nil}, {"name", .STRING, nil}, {"x", .F32, nil}, {"y", .F32, nil}, {"dx", .I8, nil}, {"dy", .I8, nil}, {"score", .U32, nil}, {"hue", .U8, nil}, {"connection", .CONNECTION_ID, nil}}
COIN_COLUMNS :: []sdb.Column{{"id", .U64, nil}, {"x", .F32, nil}, {"y", .F32, nil}}
WORLD_COLUMNS :: []sdb.Column{{"id", .U64, nil}, {"seed", .U64, nil}, {"ticks", .U64, nil}}
TICK_COLUMNS :: []sdb.Column{{"scheduled_id", .U64, nil}, {"scheduled_at", .SCHEDULE_AT, nil}}

@(export)
__preinit__10_define :: proc "c" () {
    sdb.Define(define)
}

define :: proc(m: ^sdb.Module) {
    players = sdb.TableAdd(m, "player", PLAYER_COLUMNS, public = true, primary_key = 0, options = {unique = {1}, auto_increment = 0, has_auto_increment = true})
    coins = sdb.TableAdd(m, "coin", COIN_COLUMNS, public = true, primary_key = 0, options = {auto_increment = 0, has_auto_increment = true})
    world = sdb.TableAdd(m, "world", WORLD_COLUMNS, primary_key = 0)
    ticks = sdb.TableAdd(m, "tick_schedule", TICK_COLUMNS, primary_key = 0, options = {auto_increment = 0, has_auto_increment = true, schedule_reducer = "tick", schedule_column = 1})
    sdb.ReducerAdd(m, "init", nil, initialise, .INIT)
    sdb.ReducerAdd(m, "identity_connected", nil, connected, .ON_CONNECT)
    sdb.ReducerAdd(m, "identity_disconnected", nil, disconnected, .ON_DISCONNECT)
    sdb.ReducerAdd(m, "join", {{"name", .STRING, nil}}, join)
    sdb.ReducerAdd(m, "set_input", {{"dx", .I8, nil}, {"dy", .I8, nil}}, set_input)
    sdb.ReducerAddScheduled(m, "tick", ticks, tick)
}

// ---- rows ---------------------------------------------------------------------------------------------------------------------------------------------------------

readPlayer :: proc(reader: ^bsatn.Reader) -> Player {
    player: Player
    player.id = bsatn.ReadU64(reader)
    player.owner = bsatn.ReadIdentity(reader)
    name: string = bsatn.ReadString(reader)
    player.name_length = copy(player.name[:], name)
    player.x, player.y = bsatn.ReadF32(reader), bsatn.ReadF32(reader)
    player.dx, player.dy = bsatn.ReadI8(reader), bsatn.ReadI8(reader)
    player.score = bsatn.ReadU32(reader)
    player.hue = bsatn.ReadU8(reader)
    player.connection = bsatn.ReadConnectionId(reader)
    return player
}

writePlayer :: proc(writer: ^bsatn.Writer, player: ^Player) {
    bsatn.WriteU64(writer, player.id)
    bsatn.WriteIdentity(writer, player.owner)
    bsatn.WriteString(writer, string(player.name[:player.name_length]))
    bsatn.WriteF32(writer, player.x)
    bsatn.WriteF32(writer, player.y)
    bsatn.WriteI8(writer, player.dx)
    bsatn.WriteI8(writer, player.dy)
    bsatn.WriteU32(writer, player.score)
    bsatn.WriteU8(writer, player.hue)
    bsatn.WriteConnectionId(writer, player.connection)
}

// The player of an identity (the unique index on `owner`)
findPlayer :: proc(owner: bsatn.Identity) -> (player: Player, found: bool) {
    Found :: struct {
        player: Player,
        found: bool,
    }
    result: Found
    key: [32]u8
    writer: bsatn.Writer = bsatn.WriterMake(key[:])
    bsatn.WriteIdentity(&writer, owner)
    sdb.TableFind(players, {1}, bsatn.WriterBytes(&writer), &result, proc(user: rawptr, row: ^bsatn.Reader) -> bool {
        found: ^Found = cast(^Found)user
        found.player = readPlayer(row)
        found.found = true
        return false
    })
    return result.player, result.found
}

savePlayer :: proc(player: ^Player) -> string {
    row: [128]u8
    writer: bsatn.Writer = bsatn.WriterMake(row[:])
    writePlayer(&writer, player)
    return sdb.TableUpdate(players, {0}, bsatn.WriterBytes(&writer))
}

// ---- the random numbers: a xorshift generator whose state is a row of the private table `world` (so the game is the same for every replica of the database) -----

World :: struct {
    seed: u64,
    ticks: u64,
}

readWorld :: proc() -> World {
    state: World
    sdb.TableScan(world, &state, proc(user: rawptr, row: ^bsatn.Reader) -> bool {
        state: ^World = cast(^World)user
        _ = bsatn.ReadU64(row)
        state.seed, state.ticks = bsatn.ReadU64(row), bsatn.ReadU64(row)
        return false
    })
    return state
}

writeWorld :: proc(state: World) -> string {
    row: [24]u8
    writer: bsatn.Writer = bsatn.WriterMake(row[:])
    bsatn.WriteU64(&writer, 1)
    bsatn.WriteU64(&writer, state.seed)
    bsatn.WriteU64(&writer, state.ticks)
    return sdb.TableUpdate(world, {0}, bsatn.WriterBytes(&writer))
}

// 0 ..< 1
random :: proc(state: ^World) -> f32 {
    x: u64 = state.seed
    x ~= x << 13
    x ~= x >> 7
    x ~= x << 17
    state.seed = x
    return f32(x >> 40) / f32(1 << 24)
}

// ---- reducers ---------------------------------------------------------------------------------------------------------------------------------------------------

initialise :: proc(ctx: ^sdb.ReducerContext, args: ^bsatn.Reader) -> string {
    row: [24]u8
    writer: bsatn.Writer = bsatn.WriterMake(row[:])
    bsatn.WriteU64(&writer, 1)
    bsatn.WriteU64(&writer, 0x9E3779B97F4A7C15)
    bsatn.WriteU64(&writer, 0)
    if message := sdb.TableInsert(world, bsatn.WriterBytes(&writer)); message != "" { return message }
    schedule: [32]u8
    schedule_writer: bsatn.Writer = bsatn.WriterMake(schedule[:])
    bsatn.WriteU64(&schedule_writer, 0)
    sdb.WriteScheduleInterval(&schedule_writer, TICK_MICROSECONDS)
    return sdb.TableInsert(ticks, bsatn.WriterBytes(&schedule_writer))
}

connected :: proc(ctx: ^sdb.ReducerContext, args: ^bsatn.Reader) -> string {
    return ""
}

// A player who leaves (or loses the connection) leaves the field. Only the connection that owns the player removes it: when the same identity joined again from another window, the old connection
// that the server only now notices as gone is not the owner any more.
disconnected :: proc(ctx: ^sdb.ReducerContext, args: ^bsatn.Reader) -> string {
    player, exists := findPlayer(ctx.sender)
    if !exists || player.connection != ctx.connection { return "" }
    key: [32]u8
    writer: bsatn.Writer = bsatn.WriterMake(key[:])
    bsatn.WriteIdentity(&writer, ctx.sender)
    sdb.TableDeleteBy(players, {1}, bsatn.WriterBytes(&writer))
    return ""
}

join :: proc(ctx: ^sdb.ReducerContext, args: ^bsatn.Reader) -> string {
    name: string = bsatn.ReadString(args)
    if bsatn.ReaderFailed(args) || len(name) == 0 || len(name) > 24 { return "a player needs a name of 1 to 24 letters" }
    state: World = readWorld()
    player, exists := findPlayer(ctx.sender)
    if exists {
        player.name_length = copy(player.name[:], name)
        player.connection = ctx.connection          // the player is taken over by the connection that joins now
        return savePlayer(&player)
    }
    player = {owner = ctx.sender, connection = ctx.connection, x = random(&state) * FIELD_WIDTH, y = random(&state) * FIELD_HEIGHT, hue = u8(random(&state) * 255)}
    player.name_length = copy(player.name[:], name)
    row: [128]u8
    writer: bsatn.Writer = bsatn.WriterMake(row[:])
    writePlayer(&writer, &player)
    if message := sdb.TableInsert(players, bsatn.WriterBytes(&writer)); message != "" { return message }
    return writeWorld(state)
}

set_input :: proc(ctx: ^sdb.ReducerContext, args: ^bsatn.Reader) -> string {
    dx, dy: i8 = bsatn.ReadI8(args), bsatn.ReadI8(args)
    if bsatn.ReaderFailed(args) { return "the input is a direction" }
    player, exists := findPlayer(ctx.sender)
    if !exists { return "join first" }
    dx, dy = clamp(dx, -1, 1), clamp(dy, -1, 1)
    if player.dx == dx && player.dy == dy { return "" }
    player.dx, player.dy = dx, dy
    return savePlayer(&player)
}

// The scheduled step: everybody moves, takes the coins they touch, and the field gets new coins
@(private = "file")
field_players: [MAX_PLAYERS]Player
@(private = "file")
field_coins: [MAX_COINS]Coin

tick :: proc(ctx: ^sdb.ReducerContext, args: ^bsatn.Reader) -> string {
    state: World = readWorld()
    state.ticks += 1

    Counts :: struct {
        players, coins: int,
    }
    counts: Counts
    sdb.TableScan(players, &counts, proc(user: rawptr, row: ^bsatn.Reader) -> bool {
        counts: ^Counts = cast(^Counts)user
        if counts.players < MAX_PLAYERS {
            field_players[counts.players] = readPlayer(row)
            counts.players += 1
        } else {
            _ = readPlayer(row)
        }
        return true
    })
    sdb.TableScan(coins, &counts, proc(user: rawptr, row: ^bsatn.Reader) -> bool {
        counts: ^Counts = cast(^Counts)user
        coin: Coin = {id = bsatn.ReadU64(row), x = bsatn.ReadF32(row), y = bsatn.ReadF32(row)}
        if counts.coins < MAX_COINS {
            field_coins[counts.coins] = coin
            counts.coins += 1
        }
        return true
    })

    taken: [MAX_COINS]bool
    for i in 0 ..< counts.players {
        player: ^Player = &field_players[i]
        changed: bool
        if player.dx != 0 || player.dy != 0 {
            player.x = clamp(player.x + f32(player.dx) * SPEED, 0, FIELD_WIDTH)
            player.y = clamp(player.y + f32(player.dy) * SPEED, 0, FIELD_HEIGHT)
            changed = true
        }
        for j in 0 ..< counts.coins {
            if taken[j] { continue }
            ox, oy: f32 = field_coins[j].x - player.x, field_coins[j].y - player.y
            if ox * ox + oy * oy <= PICKUP * PICKUP {
                taken[j] = true
                player.score += 1
                changed = true
            }
        }
        if changed {
            if message := savePlayer(player); message != "" { return message }
        }
    }
    remaining: int = counts.coins
    for j in 0 ..< counts.coins {
        if !taken[j] { continue }
        key: [8]u8
        writer: bsatn.Writer = bsatn.WriterMake(key[:])
        bsatn.WriteU64(&writer, field_coins[j].id)
        sdb.TableDeleteBy(coins, {0}, bsatn.WriterBytes(&writer))
        remaining -= 1
    }
    for remaining < COIN_TARGET {
        row: [16]u8
        writer: bsatn.Writer = bsatn.WriterMake(row[:])
        bsatn.WriteU64(&writer, 0)
        bsatn.WriteF32(&writer, 20 + random(&state) * (FIELD_WIDTH - 40))
        bsatn.WriteF32(&writer, 20 + random(&state) * (FIELD_HEIGHT - 40))
        if message := sdb.TableInsert(coins, bsatn.WriterBytes(&writer)); message != "" { return message }
        remaining += 1
    }
    return writeWorld(state)
}
