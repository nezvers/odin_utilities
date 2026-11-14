// Resources (textures, fonts, sounds, data) that load the same way on desktop and on the web.
// A browser build has no files to read, so the bytes have to be compiled into the program with #load. On desktop the same resource
// is read from a folder, which keeps iteration fast and the executable small.
//
// The program lists what it embeds once (see demo_karl2d/game/embedded.odin) and asks for resources by name.
// Where the folder is can be set when building: -define:RESOURCE_PATH=../assets
// This file also builds for js_wasm32 (the demo web build imports it), so it has no core:os and no core:testing:
// the disk part is in resource_file.odin and the tests of this file are in resource_test.odin.
package web_build

import "core:fmt"

// Folder of the resources, relative to the working directory of the executable. A web build ignores it.
RESOURCE_PATH :: #config(RESOURCE_PATH, "assets")

// Use only the embedded resources and never touch the disk. On by default for the web, where there is no disk.
// Turn it on for desktop (-define:RESOURCE_EMBED=true) to ship a single file.
RESOURCE_EMBED :: #config(RESOURCE_EMBED, ODIN_OS == .JS)

// A resource that is compiled into the program, `name` is its path relative to the resource folder: "textures/player.png"
Resource :: struct {
    name: string,
    data: []byte,
}

ResourceSet :: struct {
    directory: string,          // empty - RESOURCE_PATH
    embedded: []Resource,       // empty when the build doesn't embed, see `when RESOURCE_EMBED` in the demo
}

// Loaded bytes. `owned` bytes were read from disk and belong to the caller (ResourceFree), embedded bytes are static
ResourceData :: struct {
    data: []byte,
    owned: bool,
}

ResourceDirectory :: proc(set: ResourceSet) -> string {
    return set.directory if len(set.directory) > 0 else RESOURCE_PATH
}

// Path of a resource on disk, built in the user provided buffer
ResourcePath :: proc(buffer: []u8, set: ResourceSet, name: string) -> string {
    return fmt.bprintf(buffer, "%s/%s", ResourceDirectory(set), name)
}

@(private)
ResourceFindEmbedded :: proc(set: ResourceSet, name: string) -> (data: []byte, ok: bool) {
    for resource in set.embedded {
        if resource.name == name {
            return resource.data, true
        }
    }
    return
}

// Get a resource by name. Embedded builds use the embedded bytes. Other builds read the file from the resource folder and fall back
// to the embedded bytes when the file is missing. Reading allocates with `allocator`, give it back with ResourceFree.
ResourceLoad :: proc(set: ResourceSet, name: string, allocator := context.allocator) -> (result: ResourceData, ok: bool) {
    when RESOURCE_EMBED || ODIN_OS == .JS {
        result.data, ok = ResourceFindEmbedded(set, name)
        return
    } else {
        buffer: [512]u8
        data, file_ok := ResourceLoadFile(ResourcePath(buffer[:], set, name), allocator)
        if file_ok {
            return {data = data, owned = true}, true
        }
        result.data, ok = ResourceFindEmbedded(set, name)
        return
    }
}

ResourceFree :: proc(result: ResourceData, allocator := context.allocator) {
    if result.owned {
        delete(result.data, allocator)
    }
}
