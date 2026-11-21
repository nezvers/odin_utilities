package main

// A module that uses what the library has besides primitive columns: an automatic increment primary key, a unique column, an index, identity, option, array and timestamp columns, an update
// and a delete by index, and a scheduled reducer. The session test publishes it (bin/rich-odin.wasm, `odin run spacetimedb/tool/build_module -- spacetimedb/module/example/rich spacetimedb/bin/rich-odin.wasm`).

import "../../../bsatn"
import module "../.."

players, board, ticks, tick_log: module.Table

PLAYER_COLUMNS :: []module.Column{{"id", .U64, nil}, {"name", .STRING, nil}, {"level", .U32, nil}, {"owner", .IDENTITY, nil}, {"score", .OPTION, .U32}, {"tags", .ARRAY, .STRING}, {"joined", .TIMESTAMP, nil}}
BOARD_COLUMNS :: []module.Column{{"id", .U64, nil}, {"name", .STRING, nil}, {"points", .U32, nil}}
TICK_COLUMNS :: []module.Column{{"scheduled_id", .U64, nil}, {"scheduled_at", .SCHEDULE_AT, nil}}

@(export)
__preinit__10_define :: proc "c" () {
    module.Define(define)
}

define :: proc(m: ^module.Module) {
    // the name is unique (and so has an index of its own), the level has an index to look players up by
    players = module.TableAdd(m, "player", PLAYER_COLUMNS, public = true, primary_key = 0, options = {unique = {1}, auto_increment = 0, has_auto_increment = true, indexes = {{columns = {2}}}})
    board = module.TableAdd(m, "board", BOARD_COLUMNS, public = true, primary_key = 0)
    ticks = module.TableAdd(m, "tick_schedule", TICK_COLUMNS, primary_key = 0, options = {auto_increment = 0, has_auto_increment = true, schedule_reducer = "on_tick", schedule_column = 1})
    tick_log = module.TableAdd(m, "tick_log", {{"id", .U64, nil}}, public = true, primary_key = 0, options = {auto_increment = 0, has_auto_increment = true})
    module.ReducerAdd(m, "create_player", {{"name", .STRING, nil}, {"level", .U32, nil}, {"tags", .ARRAY, .STRING}}, create_player)
    module.ReducerAdd(m, "remove_player", {{"name", .STRING, nil}}, remove_player)
    module.ReducerAdd(m, "set_points", {{"id", .U64, nil}, {"name", .STRING, nil}, {"points", .U32, nil}}, set_points)
    module.ReducerAdd(m, "start_ticks", {{"milliseconds", .U64, nil}}, start_ticks)
    module.ReducerAdd(m, "stop_ticks", nil, stop_ticks)
    module.ReducerAddScheduled(m, "on_tick", ticks, on_tick)
}

create_player :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    name: string = bsatn.ReadString(args)
    level: u32 = bsatn.ReadU32(args)
    tag_count: int = bsatn.ReadLength(args, 4)
    if bsatn.ReaderFailed(args) { return "the arguments are wrong" }
    row: [512]u8
    writer: bsatn.Writer = bsatn.WriterMake(row[:])
    bsatn.WriteU64(&writer, 0)                      // the database numbers it
    bsatn.WriteString(&writer, name)
    bsatn.WriteU32(&writer, level)
    bsatn.WriteIdentity(&writer, ctx.sender)
    bsatn.WriteTag(&writer, 1)                      // score: none
    bsatn.WriteLength(&writer, tag_count)
    for _ in 0 ..< tag_count { bsatn.WriteString(&writer, bsatn.ReadString(args)) }
    bsatn.WriteI64(&writer, i64(ctx.timestamp))
    if bsatn.WriterFailed(&writer) || bsatn.ReaderFailed(args) { return "the player does not fit" }
    stored, message := module.TableInsertRow(players, bsatn.WriterBytes(&writer))
    if message != "" { return message }
    reader: bsatn.Reader = bsatn.ReaderMake(stored)
    module.Log(module.LOG_INFO, "player made")
    _ = bsatn.ReadU64(&reader)
    return ""
}

remove_player :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    name: string = bsatn.ReadString(args)
    key: [128]u8
    writer: bsatn.Writer = bsatn.WriterMake(key[:])
    bsatn.WriteString(&writer, name)
    deleted, ok := module.TableDeleteBy(players, {1}, bsatn.WriterBytes(&writer))
    if !ok { return "the delete failed" }
    if deleted == 0 { return "no such player" }
    return ""
}

set_points :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    id: u64 = bsatn.ReadU64(args)
    name: string = bsatn.ReadString(args)
    points: u32 = bsatn.ReadU32(args)
    row: [128]u8
    writer: bsatn.Writer = bsatn.WriterMake(row[:])
    bsatn.WriteU64(&writer, id)
    bsatn.WriteString(&writer, name)
    bsatn.WriteU32(&writer, points)
    if message := module.TableUpdate(board, {0}, bsatn.WriterBytes(&writer)); message != "" {
        if message != "no row with that key" { return message }
        return module.TableInsert(board, bsatn.WriterBytes(&writer))
    }
    return ""
}

start_ticks :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    milliseconds: u64 = bsatn.ReadU64(args)
    row: [32]u8
    writer: bsatn.Writer = bsatn.WriterMake(row[:])
    bsatn.WriteU64(&writer, 0)
    module.WriteScheduleInterval(&writer, i64(milliseconds) * 1000)
    return module.TableInsert(ticks, bsatn.WriterBytes(&writer))
}

stop_ticks :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    module.TableClear(ticks)
    return ""
}

on_tick :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    row: [8]u8
    writer: bsatn.Writer = bsatn.WriterMake(row[:])
    bsatn.WriteU64(&writer, 0)
    return module.TableInsert(tick_log, bsatn.WriterBytes(&writer))
}
