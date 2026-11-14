#+build js
package web_build

// There are no files in a browser, resources are embedded
ResourceLoadFile :: proc(path: string, allocator := context.allocator) -> (data: []byte, ok: bool) {
    return
}
