#+build !js
package godot_test

// Loads the built library in a real Godot (headless) and talks to a real SpacetimeDB server through it: the extension is built, a server of its own is started with the module `basic`
// (written in Odin), and a GDScript (test_project/test.gd) opens a SpacetimeDBClient, subscribes, calls a reducer and reads the events. Skipped without `godot` in PATH or without the server
// (`odin run spacetimedb/tool/setup`).

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import spacetimedb "../../../spacetimedb"

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

    // the Node flavour polls itself and tells the script with signals
    node_state, node_output, node_errors, node_error := os.process_exec({command = {"godot", "--headless", "--path", PROJECT, "--script", "test_node.gd", "--", "3194"}}, context.temp_allocator)
    node_text: string = strings.concatenate({string(node_output), string(node_errors)}, context.temp_allocator)
    testing.expectf(t, node_error == nil && node_state.success && strings.contains(node_text, "PASS"), "the client node script passes:\n%s", node_text)
}

ARENA_PROJECT :: #directory + "../arena_project"

// Both tests of the project build and load the same library: one at a time
@(private = "file")
arena_project_lock: sync.Mutex

// The arena in Godot: `ArenaClient` hosts (a server with the arena module and a p2p invite over loopback), a second `ArenaClient` joins with the invite code and the reply, both play on the host's
// database (the guest through the tunnel), the guest walks and the host sees it, the guest leaves. test_arena.gd does it in headless Godot, one process playing both sides.
@(test)
test_godot_arena_host_and_join :: proc(t: ^testing.T) {
    sync.mutex_lock(&arena_project_lock)
    defer sync.mutex_unlock(&arena_project_lock)
    godot_check, _, _, godot_error := os.process_exec({command = {"godot", "--version"}}, context.temp_allocator)
    if godot_error != nil || !godot_check.success || spacetimedb.FixturePath("arena-odin") == "" || !os.exists(spacetimedb.ServerCliPath()) {
        fmt.println("[godot_spacetimedb] no godot or no arena module: the arena test is skipped")
        return
    }

    os.make_directory_all(ARENA_PROJECT + "/bin")
    dll: string = ARENA_PROJECT + "/bin/godot_spacetimedb.dll" when ODIN_OS == .Windows else ARENA_PROJECT + "/bin/libgodot_spacetimedb.so"
    build, _, build_errors, build_error := os.process_exec({command = {"odin", "build", #directory + "..", "-build-mode:dll", "-strict-style", "-vet", fmt.tprintf("-out:%s", dll)}}, context.temp_allocator)
    testing.expectf(t, build_error == nil && build.success, "the extension builds: %s", string(build_errors))

    // absolute: the Godot process runs in the folder of its project
    cwd, _ := os.get_working_directory(context.temp_allocator)
    root: string = fmt.tprintf("%s/godot_arena_test_server", cwd)
    spacetimedb.ServerRemove(root)
    defer spacetimedb.ServerRemove(root)
    _, _, _, _ = os.process_exec({command = {"godot", "--headless", "--path", ARENA_PROJECT, "--import"}}, context.temp_allocator)
    state, output, errors, run_error := os.process_exec({command = {"godot", "--headless", "--path", ARENA_PROJECT, "--script", "test_arena.gd", "--", "3198", root}}, context.temp_allocator)
    text: string = strings.concatenate({string(output), string(errors)}, context.temp_allocator)
    testing.expectf(t, run_error == nil && state.success && strings.contains(text, "PASS"), "the arena script passes:\n%s", text)
}

// Host and join for any game: the generic classes `SpacetimeDBLobby` and `SpacetimeDBClient` with the `basic` module (nothing of the arena), host and guest in one headless process;
// the guest adds a row through the tunnel and the host sees it. test_lobby.gd.
@(test)
test_godot_lobby_hosts_and_joins_a_module_that_is_not_the_arena :: proc(t: ^testing.T) {
    sync.mutex_lock(&arena_project_lock)
    defer sync.mutex_unlock(&arena_project_lock)
    godot_check, _, _, godot_error := os.process_exec({command = {"godot", "--version"}}, context.temp_allocator)
    module: string = spacetimedb.FixturePath("basic-odin")
    if godot_error != nil || !godot_check.success || module == "" || !os.exists(spacetimedb.ServerCliPath()) {
        fmt.println("[godot_spacetimedb] no godot or no basic module: the lobby test is skipped")
        return
    }
    dll: string = ARENA_PROJECT + "/bin/godot_spacetimedb.dll" when ODIN_OS == .Windows else ARENA_PROJECT + "/bin/libgodot_spacetimedb.so"
    os.make_directory_all(ARENA_PROJECT + "/bin")
    build, _, build_errors, build_error := os.process_exec({command = {"odin", "build", #directory + "..", "-build-mode:dll", "-strict-style", "-vet", fmt.tprintf("-out:%s", dll)}}, context.temp_allocator)
    testing.expectf(t, build_error == nil && build.success, "the extension builds: %s", string(build_errors))

    cwd, _ := os.get_working_directory(context.temp_allocator)
    root: string = fmt.tprintf("%s/godot_lobby_test_server", cwd)
    spacetimedb.ServerRemove(root)
    defer spacetimedb.ServerRemove(root)
    _, _, _, _ = os.process_exec({command = {"godot", "--headless", "--path", ARENA_PROJECT, "--import"}}, context.temp_allocator)
    state, output, errors, run_error := os.process_exec({command = {"godot", "--headless", "--path", ARENA_PROJECT, "--script", "test_lobby.gd", "--", "3199", root, module}}, context.temp_allocator)
    text: string = strings.concatenate({string(output), string(errors)}, context.temp_allocator)
    testing.expectf(t, run_error == nil && state.success && strings.contains(text, "PASS"), "the lobby script passes:\n%s", text)

    // the Node flavour updates itself from the engine's _process: the script only reacts to signals
    node_root: string = fmt.tprintf("%s/godot_lobby_node_server", cwd)
    spacetimedb.ServerRemove(node_root)
    defer spacetimedb.ServerRemove(node_root)
    node_state, node_output, node_errors, node_error := os.process_exec({command = {"godot", "--headless", "--path", ARENA_PROJECT, "--script", "test_lobby_node.gd", "--", "3197", node_root, module}}, context.temp_allocator)
    node_text: string = strings.concatenate({string(node_output), string(node_errors)}, context.temp_allocator)
    testing.expectf(t, node_error == nil && node_state.success && strings.contains(node_text, "PASS"), "the lobby node script passes:\n%s", node_text)
}
