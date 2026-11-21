#+build !js
package web_build

import "core:fmt"
import "core:os"
import "core:testing"

@(test)
test_a_wasm_binary_is_read_for_its_imports_and_exports :: proc(t: ^testing.T) {
    // the smallest module with an import (env.f), a memory and two exports (memory, run)
    bytes: []u8 = {
        0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
        0x01, 0x04, 0x01, 0x60, 0x00, 0x00,                                             // type: () -> ()
        0x02, 0x09, 0x01, 0x03, 'e', 'n', 'v', 0x01, 'f', 0x00, 0x00,                   // import env.f, a function of type 0
        0x03, 0x02, 0x01, 0x00,                                                         // one function
        0x05, 0x03, 0x01, 0x00, 0x01,                                                   // a memory of one page
        0x07, 0x10, 0x02, 0x06, 'm', 'e', 'm', 'o', 'r', 'y', 0x02, 0x00, 0x03, 'r', 'u', 'n', 0x00, 0x01,   // exports
        0x0a, 0x04, 0x01, 0x02, 0x00, 0x0b,                                             // the body of the function
    }
    info, ok := WasmInspect(bytes, context.temp_allocator)
    testing.expect(t, ok)
    testing.expect_value(t, len(info.imports), 1)
    testing.expect(t, info.imports[0].module == "env" && info.imports[0].name == "f" && info.imports[0].kind == .FUNCTION)
    testing.expect_value(t, len(info.exports), 2)
    testing.expect(t, WasmHasExport(&info, "memory", .MEMORY) && WasmHasExport(&info, "run", .FUNCTION))
    testing.expect(t, !WasmHasExport(&info, "run", .MEMORY) && !WasmHasExport(&info, "nothing", .FUNCTION), "name and kind")
    unknown: []WasmImport = WasmUnknownImports(&info, {"other"}, context.temp_allocator)
    testing.expect_value(t, len(unknown), 1)
    testing.expect_value(t, len(WasmUnknownImports(&info, {"env", "other"}, context.temp_allocator)), 0)
    // not a module, and a module that is cut short
    _, not_wasm := WasmInspect({1, 2, 3, 4, 5, 6, 7, 8, 9}, context.temp_allocator)
    testing.expect(t, !not_wasm)
    _, cut := WasmInspect(bytes[:20], context.temp_allocator)
    testing.expect(t, !cut)
}

@(test)
test_a_freestanding_module_is_built_and_checked :: proc(t: ^testing.T) {
    temp, temp_error := os.temp_directory(context.temp_allocator)
    if temp_error != nil { testing.fail_now(t, "no temp directory") }
    directory: string = fmt.tprintf("%s/odin_utilities_wasm_build_test", temp)
    os.remove_all(directory)
    os.make_directory_all(directory)
    defer os.remove_all(directory)
    source :: `package module

foreign import host "host_functions"

@(default_calling_convention = "c")
foreign host {
	host_log :: proc(value: u32) ---
}

@(export)
run :: proc "c" (value: u32) {
	host_log(value)
}
`
    testing.expect_value(t, os.write_entire_file(fmt.tprintf("%s/module.odin", directory), source), nil)
    output: string = fmt.tprintf("%s/out/module.wasm", directory)
    result: WasmBuildResult = WasmBuild({source_directory = directory, output = output, require_exports = {"run"}, allowed_import_modules = {"host_functions"}})
    testing.expectf(t, result.ok, "the module builds: %s", result.message)
    testing.expect(t, result.bytes > 8 && os.exists(output), "a wasm binary was written")
    missing: WasmBuildResult = WasmBuild({source_directory = directory, output = output, require_exports = {"__describe_module__"}})
    testing.expect(t, !missing.ok && missing.message == "the module does not export the function __describe_module__")
    refused: WasmBuildResult = WasmBuild({source_directory = directory, output = output, allowed_import_modules = {"spacetime_10.0"}})
    testing.expect(t, !refused.ok && refused.message == "the module imports host_functions.host_log, which the host does not offer")
    broken_directory: string = fmt.tprintf("%s/broken", directory)
    os.make_directory_all(broken_directory)
    broken_write := os.write_entire_file(fmt.tprintf("%s/broken.odin", broken_directory), "package broken\nthis is not odin\n")
    testing.expect_value(t, broken_write, nil)
    broken: WasmBuildResult = WasmBuild({source_directory = broken_directory, output = output})
    testing.expect(t, !broken.ok && len(broken.message) > 0, "the message of the compiler comes back")
}
