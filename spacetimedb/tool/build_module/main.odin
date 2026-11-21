package main

// `odin run spacetimedb/tool/build_module [-- <package> [<out.wasm>]]`: builds a module written in Odin to WebAssembly (`-target:freestanding_wasm32 -no-entry-point`). Without arguments it builds
// the example (module/example/basic) into spacetimedb/bin/basic-odin.wasm. Publish the result with `DatabasePublish` or `spacetime publish --bin-path`.

import "core:fmt"
import "core:os"
import spacetimedb "../.."

main :: proc() {
    package_path: string = fmt.tprintf("%s/spacetimedb/module/example/basic", spacetimedb.SetupRoot())
    out: string = fmt.tprintf("%s/basic-odin.wasm", spacetimedb.ServerBinFolder())
    if len(os.args) > 1 { package_path = os.args[1] }
    if len(os.args) > 2 { out = os.args[2] }
    os.make_directory_all(spacetimedb.ServerBinFolder())
    if !spacetimedb.BuildModule(package_path, out) {
        fmt.eprintln("the build failed")
        os.exit(1)
    }
    fmt.println("built", out)
}
