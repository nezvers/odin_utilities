package main

// The module of fixtures/basic-rs written in Odin: a table `person` with a name, a reducer `add(name)` that inserts a row, `say_hello()` that writes the names to the log of the database, and the
// lifecycle reducers. Build it with `odin run spacetimedb/tool/build_module` (it makes bin/basic-odin.wasm); the session test publishes it and talks to it like to the Rust one.

import "../../../bsatn"
import module "../.."

people: module.Table

// The host runs the exports called `__preinit__...` before anything else: this is where the module says where its description is
@(export)
__preinit__10_define :: proc "c" () {
    module.Define(define)
}

define :: proc(m: ^module.Module) {
    people = module.TableAdd(m, "person", {{"name", .STRING}}, public = true)
    module.ReducerAdd(m, "init", nil, initialise, .INIT)
    module.ReducerAdd(m, "identity_connected", nil, connected, .ON_CONNECT)
    module.ReducerAdd(m, "identity_disconnected", nil, disconnected, .ON_DISCONNECT)
    module.ReducerAdd(m, "add", {{"name", .STRING}}, add)
    module.ReducerAdd(m, "say_hello", nil, say_hello)
}

initialise :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    module.Log(module.LOG_INFO, "the module is made")
    return ""
}

connected :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    return ""
}

disconnected :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    return ""
}

add :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    name: string = bsatn.ReadString(args)
    if bsatn.ReaderFailed(args) { return "the argument is not a name" }
    if len(name) == 0 { return "a person has a name" }
    row: [256]u8
    writer: bsatn.Writer = bsatn.WriterMake(row[:])
    bsatn.WriteString(&writer, name)
    if bsatn.WriterFailed(&writer) { return "the name is too long" }
    return module.TableInsert(people, bsatn.WriterBytes(&writer))
}

say_hello :: proc(ctx: ^module.ReducerContext, args: ^bsatn.Reader) -> string {
    module.TableScan(people, nil, proc(user: rawptr, row: ^bsatn.Reader) -> bool {
        name: string = bsatn.ReadString(row)
        module.Log(module.LOG_INFO, name)
        return true
    })
    module.Log(module.LOG_INFO, "Hello, World!")
    return ""
}
