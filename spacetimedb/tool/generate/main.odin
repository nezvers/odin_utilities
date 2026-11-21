package main

// Writes an Odin file for a database from its schema: `odin run spacetimedb/tool/generate -- --schema fixtures/basic.schema.json --out game/data.odin [--package game] [--library ../spacetimedb]`
// or, from a running server, `-- --server 127.0.0.1:3000 --database chat --out ...`. The module can also be a .wasm built by this library: publish it, then read its schema from the server.

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import spacetimedb "../.."

main :: proc() {
    schema_path, server, database, out, package_name, library: string
    for i := 1; i < len(os.args); i += 1 {
        value: string = os.args[i + 1] if i + 1 < len(os.args) else ""
        switch os.args[i] {
        case "--schema": schema_path = value
        case "--server": server = value
        case "--database": database = value
        case "--out": out = value
        case "--package": package_name = value
        case "--library": library = value
        case:
            fmt.eprintln("unknown argument", os.args[i])
            os.exit(2)
        }
        i += 1
    }
    schema: string
    if schema_path != "" {
        bytes, error := os.read_entire_file(schema_path, context.allocator)
        if error != nil {
            fmt.eprintln("cannot read", schema_path)
            os.exit(1)
        }
        schema = string(bytes)
    } else if server != "" && database != "" {
        secure: bool = strings.has_prefix(server, "https://")
        server = strings.trim_prefix(strings.trim_prefix(server, "https://"), "http://")
        colon: int = strings.last_index_byte(server, ':')
        port: int = 443 if secure else 3000
        host: string = server
        if colon >= 0 {
            host = server[:colon]
            port = strconv.parse_int(server[colon + 1:]) or_else port
        }
        response := make([]u8, 1 << 20)
        result: spacetimedb.HttpResult = spacetimedb.DatabaseSchema({host = host, port = port, secure = secure}, database, "", response)
        if !result.ok || result.status != 200 {
            fmt.eprintln("could not read the schema of", database, "from", server)
            os.exit(1)
        }
        schema = string(result.body)
    } else {
        fmt.eprintln("usage: generate (--schema file.json | --server [https://]host[:port] --database name) [--out file.odin] [--package name] [--library import path]")
        os.exit(2)
    }
    source, ok := spacetimedb.GenerateSource(schema, {package_name = package_name, library = library}, context.allocator)
    if !ok {
        fmt.eprintln("the schema could not be read")
        os.exit(1)
    }
    if out == "" {
        fmt.print(source)
        return
    }
    if error := os.write_entire_file(out, source); error != nil {
        fmt.eprintln("cannot write", out)
        os.exit(1)
    }
    fmt.println("wrote", out)
}
