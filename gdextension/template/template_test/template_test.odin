#+build !js
package template_test

// Builds the extension of the template and runs godot_project/test.gd in a headless Godot (4.4 or newer, `godot` in PATH). Skipped when there is no Godot.

import "core:fmt"
import "core:os"
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
    state, output, errors, run_error := os.process_exec({command = {"godot", "--headless", "--path", PROJECT, "--script", "test.gd"}}, context.temp_allocator)
    text: string = strings.concatenate({string(output), string(errors)}, context.temp_allocator)
    testing.expectf(t, run_error == nil && state.success && strings.contains(text, "PASS"), "test.gd passes:\n%s", text)

    // the scene that is the testing ground runs too (headless it quits by itself)
    scene, scene_output, scene_errors, scene_error := os.process_exec({command = {"godot", "--headless", "--path", PROJECT, "--quit-after", "60"}}, context.temp_allocator)
    scene_text: string = strings.concatenate({string(scene_output), string(scene_errors)}, context.temp_allocator)
    testing.expectf(t, scene_error == nil && scene.success && strings.contains(scene_text, "get -> 12"), "main.tscn runs:\n%s", scene_text)
}
