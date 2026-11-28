#+build !js
package template_test

// Builds the extension of the template and runs godot_project/test.gd in a headless Godot (4.4 or newer, `godot` in PATH). Skipped when there is no Godot.

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

PROJECT :: #directory + "../godot_project"

@(test)
test_the_template_extension_works_in_godot :: proc(t: ^testing.T) {
    version, _, _, version_error := os.process_exec({command = {"godot", "--version"}}, context.temp_allocator)
    if version_error != nil || !version.success {
        fmt.println("[gdextension template] no godot in PATH: skipped")
        return
    }
    os.make_directory_all(PROJECT + "/bin")
    when ODIN_OS == .Windows {
        library: string = PROJECT + "/bin/gdextension_template.dll"
    } else when ODIN_OS == .Darwin {
        library: string = PROJECT + "/bin/libgdextension_template.dylib"
    } else {
        library: string = PROJECT + "/bin/libgdextension_template.so"
    }
    build, _, build_errors, build_error := os.process_exec({command = {"odin", "build", #directory + "..", "-build-mode:dll", "-strict-style", "-vet", fmt.tprintf("-out:%s", library)}}, context.temp_allocator)
    testing.expectf(t, build_error == nil && build.success, "the extension builds: %s", string(build_errors))

    // the first run of a project imports it: that writes the list of extensions that Godot loads
    _, _, _, _ = os.process_exec({command = {"godot", "--headless", "--path", PROJECT, "--import"}}, context.temp_allocator)
    state, output, errors, run_error := os.process_exec({command = {"godot", "--headless", "--quit-after", "600", "--path", PROJECT, "--script", "test.gd"}}, context.temp_allocator)
    text: string = strings.concatenate({string(output), string(errors)}, context.temp_allocator)
    testing.expectf(t, run_error == nil && state.success && strings.contains(text, "PASS"), "test.gd passes:\n%s", text)

    // the scene that is the testing ground runs too (headless it quits by itself)
    scene, scene_output, scene_errors, scene_error := os.process_exec({command = {"godot", "--headless", "--path", PROJECT, "--quit-after", "60"}}, context.temp_allocator)
    scene_text: string = strings.concatenate({string(scene_output), string(scene_errors)}, context.temp_allocator)
    testing.expectf(t, scene_error == nil && scene.success && strings.contains(scene_text, "get -> 12"), "main.tscn runs:\n%s", scene_text)

    // Hot reload: Godot reloads an extension only inside the editor. A second build (TEMPLATE_VERSION=2) is made next to the project, the editor plugin of the project (addons/reload_test) makes
    // an object, copies the second build over the loaded library, reloads the extension and checks that the object answers with the new build and has its property back. This replaces the
    // library in bin/ with the second build: the next run of this test builds the first one again.
    next_library, _ := strings.replace(library, "/bin/", "/bin_next/", 1, context.temp_allocator)
    os.make_directory_all(PROJECT + "/bin_next")
    next_build, _, next_errors, next_error := os.process_exec({command = {"odin", "build", #directory + "..", "-build-mode:dll", "-strict-style", "-vet", "-define:TEMPLATE_VERSION=2", fmt.tprintf("-out:%s", next_library)}}, context.temp_allocator)
    testing.expectf(t, next_error == nil && next_build.success, "the second build compiles: %s", string(next_errors))
    loaded_path, loaded_error := filepath.abs(library, context.temp_allocator)
    next_path, next_path_error := filepath.abs(next_library, context.temp_allocator)
    testing.expect(t, loaded_error == nil && next_path_error == nil)
    reload, reload_output, reload_errors, reload_error := os.process_exec({command = {"godot", "--headless", "--editor", "--quit-after", "1200", "--path", PROJECT, "--", next_path, loaded_path}}, context.temp_allocator)
    reload_text: string = strings.concatenate({string(reload_output), string(reload_errors)}, context.temp_allocator)
    testing.expectf(t, reload_error == nil && reload.success && strings.contains(reload_text, "PASS"), "the hot reload test passes:\n%s", reload_text)
}
