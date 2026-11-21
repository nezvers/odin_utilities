package main

// `odin run spacetimedb/tool/setup [-- --update] [--no-server] [--no-references] [--no-fixtures]`: clones the references (untracked, in odin_utilities/references), downloads the server of the release
// into spacetimedb/bin and builds the test module. Safe to run again. A library that builds on spacetimedb calls `spacetimedb.SetupRun` from its own setup.

import "core:fmt"
import "core:os"
import spacetimedb "../.."

main :: proc() {
    options: spacetimedb.SetupOptions
    for argument in os.args[1:] {
        switch argument {
        case "--update": options.update = true
        case "--no-server": options.skip_server = true
        case "--no-references": options.skip_references = true
        case "--no-fixtures": options.skip_fixtures = true
        case:
            fmt.eprintln("unknown option", argument)
            os.exit(2)
        }
    }
    result: spacetimedb.SetupResult = spacetimedb.SetupRun(options)
    fmt.printfln("references: %d cloned, %d there, %d failed; server: %v; modules built: %d", result.cloned, result.present, result.failed, result.server, result.fixtures)
    if result.failed > 0 { os.exit(1) }
}
