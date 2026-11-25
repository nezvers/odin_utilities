#+build !js
package ui_default

// Reading the font files of a skin (skin.odin): the bytes of every face that names a file, from `folder` (an absolute file name is taken as it is). A face with no file, or a file that cannot be read,
// has no bytes: the glue uses the built in font for it. The bytes are made with `allocator`; `SkinFontBytesFree` gives them back.

import "core:os"
import "core:fmt"

SkinFontsRead :: proc(fonts: ^SkinFonts, folder: string, bytes: ^SkinFontBytes, allocator := context.allocator) -> (read: int) {
    SkinFontBytesFree(bytes, allocator)
    for face in Face {
        file: string = SkinFontFile(fonts, face)
        if file == "" { continue }
        path: string = file
        if !isAbsolute(file) && folder != "" { path = fmt.tprintf("%s/%s", folder, file) }
        data, err := os.read_entire_file(path, allocator)
        if err != nil { continue }
        bytes[face] = data
        read += 1
    }
    return
}

SkinFontBytesFree :: proc(bytes: ^SkinFontBytes, allocator := context.allocator) {
    for face in Face {
        if bytes[face] != nil { delete(bytes[face], allocator) }
        bytes[face] = nil
    }
}

@(private)
isAbsolute :: proc(path: string) -> bool {
    return len(path) > 0 && (path[0] == '/' || path[0] == '\\' || (len(path) > 2 && path[1] == ':'))
}
