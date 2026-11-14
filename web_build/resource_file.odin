#+build !js
package web_build

import "core:fmt"
import "core:os"
import "core:testing"

// Read a whole file. The bytes are allocated with `allocator`
ResourceLoadFile :: proc(path: string, allocator := context.allocator) -> (data: []byte, ok: bool) {
    file_data, error := os.read_entire_file(path, allocator)
    return file_data, error == nil
}

// --- Tests ---

@(test)
test_load_from_disk_then_embedded_then_nothing :: proc(t: ^testing.T) {
    temp, temp_error := os.temp_directory(context.temp_allocator)
    if temp_error != nil {
        testing.fail_now(t, "no temp directory")
    }
    directory: string = fmt.tprintf("%s/odin_utilities_resource_test", temp)
    os.make_directory_all(fmt.tprintf("%s/sub", directory))
    defer os.remove_all(directory)
    testing.expect_value(t, os.write_entire_file(fmt.tprintf("%s/sub/disk.txt", directory), "from disk"), nil)

    set: ResourceSet = {directory = directory, embedded = []Resource{{"embedded.txt", {'e', 'm'}}, {"sub/disk.txt", {'o', 'l', 'd'}}}}

    when !RESOURCE_EMBED {
        disk, disk_ok := ResourceLoad(set, "sub/disk.txt")
        testing.expect(t, disk_ok)
        testing.expect(t, disk.owned)
        testing.expect_value(t, string(disk.data), "from disk")                          // the file wins over the embedded copy
        ResourceFree(disk)
    }

    fallback, fallback_ok := ResourceLoad(set, "embedded.txt")
    testing.expect(t, fallback_ok, "no such file, the embedded bytes are used")
    testing.expect(t, !fallback.owned)
    testing.expect_value(t, string(fallback.data), "em")
    ResourceFree(fallback)                                                                // nothing to free, must be safe

    _, missing := ResourceLoad(set, "nowhere.txt")
    testing.expect(t, !missing)
}
