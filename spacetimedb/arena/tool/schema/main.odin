package main

// Writes arena/schema/schema.odin from the module: starts a server of its own, publishes bin/arena-odin.wasm, reads the schema and runs the generator on it.
// `odin run spacetimedb/arena/tool/schema` (after `odin run spacetimedb/tool/build_module -- spacetimedb/arena/module spacetimedb/bin/arena-odin.wasm`). Run it again when the module changes.

import "core:fmt"
import "core:os"
import spacetimedb "../../.."

OUT :: #directory + "../../schema/schema.odin"

main :: proc() {
    module_path: string = spacetimedb.FixturePath("arena-odin")
    if module_path == "" || !os.exists(spacetimedb.ServerCliPath()) {
        fmt.eprintln("build the module and run the setup first (see the comment of this file)")
        os.exit(1)
    }
    module, read_error := os.read_entire_file(module_path, context.allocator)
    if read_error != nil { os.exit(1) }
    root: string = "arena_schema_server"
    defer os.remove_all(root)
    server: spacetimedb.Server
    if !spacetimedb.ServerStart(&server, {root = root, port = 3142, in_memory = true}) {
        fmt.eprintln("the server does not start")
        os.exit(1)
    }
    defer spacetimedb.ServerStop(&server)
    response := make([]u8, 1 << 16)
    _, token_view, made := spacetimedb.IdentityCreate(server.endpoint, response)
    if !made { os.exit(1) }
    token: string = fmt.aprintf("%s", token_view)
    published: spacetimedb.HttpResult = spacetimedb.DatabasePublish(server.endpoint, "arena", module, token, response)
    if !published.ok || published.status != 200 {
        fmt.eprintln("publish failed:", string(published.body))
        os.exit(1)
    }
    schema: spacetimedb.HttpResult = spacetimedb.DatabaseSchema(server.endpoint, "arena", token, response)
    if !schema.ok || schema.status != 200 {
        fmt.eprintln("no schema")
        os.exit(1)
    }
    source, ok := spacetimedb.GenerateSource(string(schema.body), {package_name = "arena_schema", library = "../.."}, context.allocator)
    if !ok { os.exit(1) }
    if os.write_entire_file(OUT, source) != nil { os.exit(1) }
    fmt.println("wrote", OUT)
}
