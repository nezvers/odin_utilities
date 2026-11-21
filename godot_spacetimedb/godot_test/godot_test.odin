#+build !js
package godot_test

// Loads the built library in a real Godot (headless) and talks to a real SpacetimeDB server through it: the extension is built, a server of its own is started with the module `basic`
// (written in Odin), and a GDScript (test_project/test.gd) opens a SpacetimeDBClient, subscribes, calls a reducer and reads the events. Skipped without `godot` in PATH or without the server
// (`odin run spacetimedb/tool/setup`).

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import spacetimedb "../../spacetimedb"

PROJECT :: #directory + "../test_project"

@(test)
test_godot_script_uses_the_extension_against_a_server :: proc(t: ^testing.T) {
    godot_check, _, _, godot_error := os.process_exec({command = {"godot", "--version"}}, context.temp_allocator)
    module_path: string = spacetimedb.FixturePath("basic-odin")
    if godot_error != nil || !godot_check.success || module_path == "" || !os.exists(spacetimedb.ServerCliPath()) {
        fmt.println("[godot_spacetimedb] no godot or no server: the Godot test is skipped")
        return
    }

    os.make_directory_all(PROJECT + "/bin")
    dll: string = PROJECT + "/bin/godot_spacetimedb.dll" when ODIN_OS == .Windows else PROJECT + "/bin/libgodot_spacetimedb.so"
    build, _, build_errors, build_error := os.process_exec({command = {"odin", "build", #directory + "..", "-build-mode:dll", "-strict-style", "-vet", fmt.tprintf("-out:%s", dll)}}, context.temp_allocator)
    testing.expectf(t, build_error == nil && build.success, "the extension builds: %s", string(build_errors))

    root: string = "godot_test_server"
    defer os.remove_all(root)
    server: spacetimedb.Server
    testing.expect(t, spacetimedb.ServerStart(&server, {root = root, port = 3194, in_memory = true}), "the server starts")
    defer spacetimedb.ServerStop(&server)
    response: [8192]u8
    _, token_view, made := spacetimedb.IdentityCreate(server.endpoint, response[:])
    testing.expect(t, made)
    token: string = fmt.tprintf("%s", token_view)
    module, read_error := os.read_entire_file(module_path, context.temp_allocator)
    testing.expect(t, read_error == nil)
    published: spacetimedb.HttpResult = spacetimedb.DatabasePublish(server.endpoint, "odin-session", module, token, response[:])
    testing.expectf(t, published.ok && published.status == 200, "the module is published: %d", published.status)

    // the first run of a project imports it (it writes the list of extensions Godot loads)
    _, _, _, _ = os.process_exec({command = {"godot", "--headless", "--path", PROJECT, "--import"}}, context.temp_allocator)
    state, output, errors, run_error := os.process_exec({command = {"godot", "--headless", "--path", PROJECT, "--script", "test.gd", "--", "3194"}}, context.temp_allocator)
    text: string = strings.concatenate({string(output), string(errors)}, context.temp_allocator)
    testing.expectf(t, run_error == nil && state.success && strings.contains(text, "PASS"), "the script passes:\n%s", text)
}
