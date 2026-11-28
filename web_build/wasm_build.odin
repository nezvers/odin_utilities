#+build !js
package web_build

// Builds Odin to WebAssembly that is not a browser program: a module for a host (a SpacetimeDB module, a plugin, a game mod). `WebBuild` makes the browser version (js_wasm32 with an entry, an
// index.html and the Odin JavaScript runtime); `WasmBuild` makes the other kind (freestanding_wasm32 by default: no entry point, no runtime, no JavaScript, the host calls the exports of the
// program and offers the imports it declares) and checks the result with `WasmInspect`. The two share the compiler call, the flags and the check of the output.
//
//     result: WasmBuildResult = WasmBuild({source_directory = "module", output = "bin/module.wasm", odin_arguments = {"-o:size"}, require_exports = {"__describe_module__"}, allowed_import_modules = {"spacetime_10.0"}})
//     if !result.ok { fmt.eprintln(result.message) }

import "core:fmt"
import "core:os"

WasmTarget :: enum u8 {
    FREESTANDING,       // -target:freestanding_wasm32 -no-entry-point: a module for a host that is not a browser
    JS,                 // -target:js_wasm32 -no-entry-point: a library for a page that brings its own JavaScript (for a program with an entry and a page: WebBuild)
}

WasmBuildConfig :: struct {
    source_directory: string,           // the package that is built
    output: string,                     // the .wasm that is written (its folder is made)
    target: WasmTarget,
    odin_arguments: []string,           // more flags of `odin build`: "-o:size", "-define:NAME=value", "-debug"
    strict: bool,                       // -strict-style -vet (the repository's own rule, on by default through `WasmBuildStrict`)
    require_exports: []string,          // function exports the result has to have: a missing one fails the build, not the first call of the host
    require_memory: bool,               // the result has to export "memory" (a host reads and writes the arguments through it)
    allowed_import_modules: []string,   // when not empty: the result may import only from these namespaces (the host offers nothing else, a module that asks for more does not load)
}

WasmBuildResult :: struct {
    ok: bool,
    message: string,                    // what went wrong: the output of the compiler, or the missing export or the import that the host does not offer (temp allocator)
    bytes: int,                         // the size of the .wasm
}

// The flags a build of this repository uses on every package
WasmBuildStrict :: [?]string{"-strict-style", "-vet"}

WasmBuild :: proc(config: WasmBuildConfig) -> WasmBuildResult {
    assert(len(config.source_directory) > 0 && len(config.output) > 0)
    folder_end: int = max(lastSlash(config.output), 0)
    if folder_end > 0 { os.make_directory_all(config.output[:folder_end]) }
    os.remove(config.output)
    command: [dynamic]string
    command.allocator = context.temp_allocator
    target: string = "-target:freestanding_wasm32" if config.target == .FREESTANDING else "-target:js_wasm32"
    append(&command, "odin", "build", config.source_directory, target, "-no-entry-point", fmt.tprintf("-out:%s", config.output))
    if config.strict {
        strict := WasmBuildStrict
        append(&command, ..strict[:])
    }
    append(&command, ..config.odin_arguments)
    state, _, errors, error := os.process_exec({command = command[:]}, context.temp_allocator)
    if error != nil || state.exit_code != 0 { return {message = string(errors) if error == nil else "odin could not be started"} }
    data, read_error := os.read_entire_file(config.output, context.temp_allocator)
    if read_error != nil { return {message = "the compiler wrote no output"} }
    info, inspected := WasmInspect(data, context.temp_allocator)
    if !inspected { return {message = "the output is not a WebAssembly binary", bytes = len(data)} }
    for name in config.require_exports {
        if !WasmHasExport(&info, name, .FUNCTION) { return {message = fmt.tprintf("the module does not export the function %s", name), bytes = len(data)} }
    }
    if config.require_memory && !WasmHasExport(&info, "memory", .MEMORY) { return {message = "the module does not export its memory", bytes = len(data)} }
    if len(config.allowed_import_modules) > 0 {
        unknown: []WasmImport = WasmUnknownImports(&info, config.allowed_import_modules, context.temp_allocator)
        if len(unknown) > 0 { return {message = fmt.tprintf("the module imports %s.%s, which the host does not offer", unknown[0].module, unknown[0].name), bytes = len(data)} }
    }
    return {ok = true, bytes = len(data)}
}

@(private)
lastSlash :: proc(path: string) -> int {
    for i := len(path) - 1; i >= 0; i -= 1 {
        if path[i] == '/' || path[i] == '\\' { return i }
    }
    return -1
}
