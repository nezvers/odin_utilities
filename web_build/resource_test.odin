#+build !js
// Tests of resource.odin. They are not at the bottom of resource.odin because that file builds for js_wasm32, where core:testing doesn't compile.
package web_build

import "core:testing"

@(test)
test_resource_path_and_directory :: proc(t: ^testing.T) {
    buffer: [64]u8
    testing.expect_value(t, ResourceDirectory({}), RESOURCE_PATH)
    testing.expect_value(t, ResourceDirectory({directory = "../assets"}), "../assets")
    testing.expect_value(t, ResourcePath(buffer[:], {directory = "../assets"}, "textures/a.png"), "../assets/textures/a.png")
    testing.expect_value(t, ResourcePath(buffer[:], {}, "a.txt"), RESOURCE_PATH + "/a.txt")
}

@(test)
test_embedded_lookup :: proc(t: ^testing.T) {
    set: ResourceSet = {embedded = []Resource{{"a.txt", {1, 2, 3}}, {"dir/b.txt", {9}}}}
    data, ok := ResourceFindEmbedded(set, "dir/b.txt")
    testing.expect(t, ok)
    testing.expect_value(t, len(data), 1)
    _, missing := ResourceFindEmbedded(set, "b.txt")
    testing.expect(t, !missing, "names are whole paths")
    _, empty := ResourceFindEmbedded({}, "a.txt")
    testing.expect(t, !empty)
}
