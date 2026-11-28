#+build !js
package file_browser

import "base:runtime"
import "core:os"

// The disk through core:os. Reading a directory uses the temp allocator of the caller's context for the OS iterator (it is rewound before returning), nothing is kept.

IoOs :: proc() -> Io {
    return {
        list = osList,
        read = osRead,
        write = osWrite,
        stat = osStat,
        start = osStart,
    }
}

@(private)
osError :: proc(err: os.Error) -> Error {
    if err == nil { return .NONE }
    if err == os.General_Error.Not_Exist { return .NOT_FOUND }
    if err == os.General_Error.Exist { return .EXISTS }
    return .FAILED
}

@(private)
osList :: proc(user: rawptr, dir: string, out: ^Listing) -> Error {
    guard := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(guard)
    if exists, directory := osStat(nil, dir); !exists {
        return .NOT_FOUND
    } else if !directory {
        return .NOT_A_DIRECTORY
    }
    handle, open_err := os.open(dir)
    if open_err != nil { return osError(open_err) }
    defer os.close(handle)
    iterator: os.Read_Directory_Iterator = os.read_directory_iterator_create(handle)
    defer os.read_directory_iterator_destroy(&iterator)
    for info in os.read_directory_iterator(&iterator) {
        ListingAdd(out, info.name, info.type == .Directory, info.size if info.type != .Directory else 0)
    }
    if _, err := os.read_directory_iterator_error(&iterator); err != nil { return osError(err) }
    return .NONE
}

@(private)
osRead :: proc(user: rawptr, path: string, buffer: []u8) -> (count: int, err: Error) {
    handle, open_err := os.open(path)
    if open_err != nil { return 0, osError(open_err) }
    defer os.close(handle)
    size, size_err := os.file_size(handle)
    if size_err != nil { return 0, osError(size_err) }
    if size > i64(len(buffer)) { return 0, .TOO_BIG }
    if size == 0 { return 0, .NONE }
    read, read_err := os.read(handle, buffer[:size])
    if read_err != nil && read != int(size) { return read, osError(read_err) }
    return read, .NONE
}

@(private)
osWrite :: proc(user: rawptr, path: string, data: []u8) -> Error {
    return osError(os.write_entire_file(path, data))
}

@(private)
osStat :: proc(user: rawptr, path: string) -> (exists: bool, directory: bool) {
    guard := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(guard)
    info, err := os.stat(path, context.temp_allocator)
    if err != nil { return false, false }
    return true, info.type == .Directory
}

@(private)
osStart :: proc(user: rawptr, buffer: []u8) -> string {
    guard := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(guard)
    // the folder of the person first, the working directory when there is none
    home, home_err := os.user_home_dir(context.temp_allocator)
    if home_err == nil && len(home) <= len(buffer) && len(home) > 0 {
        copy(buffer, home)
        return string(buffer[:len(home)])
    }
    working, working_err := os.get_working_directory(context.temp_allocator)
    if working_err == nil && len(working) <= len(buffer) && len(working) > 0 {
        copy(buffer, working)
        return string(buffer[:len(working)])
    }
    return ""
}
