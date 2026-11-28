package file_browser

// A file system in memory, for tests and scripted demos (same files on every machine, nothing touches a disk) and for a program in a web page that wants a place to browse. Fixed capacity in the
// caller's memory: `files` (how many files and directories) and `storage` (the bytes of all file contents together). A write that replaces a file takes new room in `storage` (the old room is not reused,
// the storage is a bump allocator): fail with FAILED when it is full, never grow. Paths use '/' and start with it ("/pictures/cat.png"); directories are the prefixes of the files and the ones made
// with `MemoryFsDirectory`.

MEMORY_PATH_MAX :: 256

MemoryFile :: struct {
    path: [MEMORY_PATH_MAX]u8,
    path_length: int,
    offset: int,                // where the bytes are in `storage`
    size: int,
    directory: bool,
}

MemoryFs :: struct {
    files: []MemoryFile,
    count: int,
    storage: []u8,
    used: int,
}

MemoryFsInit :: proc(fs: ^MemoryFs, files: []MemoryFile, storage: []u8) {
    fs^ = {files = files, storage = storage}
}

// Create or replace a file
MemoryFsAdd :: proc(fs: ^MemoryFs, path: string, data: []u8) -> Error {
    if len(path) == 0 || len(path) > MEMORY_PATH_MAX { return .NAME_INVALID }
    if fs.used + len(data) > len(fs.storage) { return .FAILED }
    index: int = memoryFind(fs, path)
    if index < 0 {
        // a name that is the prefix of other files is a directory already
        if _, directory := memoryStat(fs, path); directory { return .IS_A_DIRECTORY }
        if fs.count >= len(fs.files) { return .FAILED }
        index = fs.count
        fs.count += 1
        fs.files[index] = {}
        fs.files[index].path_length = copy(fs.files[index].path[:], path)
    } else if fs.files[index].directory {
        return .IS_A_DIRECTORY
    }
    copy(fs.storage[fs.used:], data)
    fs.files[index].offset, fs.files[index].size = fs.used, len(data)
    fs.used += len(data)
    return .NONE
}

// An empty directory (one that has files is there without this)
MemoryFsDirectory :: proc(fs: ^MemoryFs, path: string) -> Error {
    if len(path) == 0 || len(path) > MEMORY_PATH_MAX { return .NAME_INVALID }
    if memoryFind(fs, path) >= 0 { return .NONE }
    if fs.count >= len(fs.files) { return .FAILED }
    fs.files[fs.count] = {directory = true}
    fs.files[fs.count].path_length = copy(fs.files[fs.count].path[:], path)
    fs.count += 1
    return .NONE
}

// The bytes of a file (a view into the storage, valid until the file is replaced)
MemoryFsGet :: proc(fs: ^MemoryFs, path: string) -> (data: []u8, found: bool) {
    index: int = memoryFind(fs, path)
    if index < 0 || fs.files[index].directory { return nil, false }
    return fs.storage[fs.files[index].offset:][:fs.files[index].size], true
}

IoMemory :: proc(fs: ^MemoryFs) -> Io {
    return {
        user = fs,
        list = memoryList,
        read = memoryRead,
        write = memoryWrite,
        stat = memoryStat,
        start = memoryStart,
    }
}

@(private)
memoryPath :: proc(file: ^MemoryFile) -> string {
    return string(file.path[:file.path_length])
}

@(private)
memoryFind :: proc(fs: ^MemoryFs, path: string) -> int {
    for i in 0 ..< fs.count {
        if memoryPath(&fs.files[i]) == path { return i }
    }
    return -1
}

// "/a/b" is under "/a" and under "/": the part of the path after the directory, without its first separator
@(private)
memoryBelow :: proc(path: string, directory: string) -> (rest: string, ok: bool) {
    prefix: string = directory
    if len(prefix) > 0 && prefix[len(prefix) - 1] == '/' { prefix = prefix[:len(prefix) - 1] }
    if len(path) <= len(prefix) + 1 || path[:len(prefix)] != prefix || path[len(prefix)] != '/' { return "", false }
    return path[len(prefix) + 1:], true
}

@(private)
memoryList :: proc(user: rawptr, dir: string, out: ^Listing) -> Error {
    fs: ^MemoryFs = cast(^MemoryFs)user
    if exists, directory := memoryStat(user, dir); !exists {
        return .NOT_FOUND
    } else if !directory {
        return .NOT_A_DIRECTORY
    }
    for i in 0 ..< fs.count {
        file: ^MemoryFile = &fs.files[i]
        rest, below := memoryBelow(memoryPath(file), dir)
        if !below { continue }
        // the first name of what is left is the entry: more names after it make it a directory
        slash: int = -1
        for c, j in transmute([]u8)rest {
            if c == '/' {
                slash = j
                break
            }
        }
        if slash >= 0 {
            if ListingFind(out, rest[:slash]) < 0 { ListingAdd(out, rest[:slash], true) }
        } else if file.directory {
            if ListingFind(out, rest) < 0 { ListingAdd(out, rest, true) }
        } else {
            ListingAdd(out, rest, false, i64(file.size))
        }
    }
    return .NONE
}

@(private)
memoryRead :: proc(user: rawptr, path: string, buffer: []u8) -> (count: int, err: Error) {
    fs: ^MemoryFs = cast(^MemoryFs)user
    index: int = memoryFind(fs, path)
    if index < 0 { return 0, .NOT_FOUND }
    if fs.files[index].directory { return 0, .IS_A_DIRECTORY }
    if fs.files[index].size > len(buffer) { return 0, .TOO_BIG }
    return copy(buffer, fs.storage[fs.files[index].offset:][:fs.files[index].size]), .NONE
}

@(private)
memoryWrite :: proc(user: rawptr, path: string, data: []u8) -> Error {
    return MemoryFsAdd(cast(^MemoryFs)user, path, data)
}

@(private)
memoryStat :: proc(user: rawptr, path: string) -> (exists: bool, directory: bool) {
    fs: ^MemoryFs = cast(^MemoryFs)user
    if path == "/" { return true, true }
    if index := memoryFind(fs, path); index >= 0 { return true, fs.files[index].directory }
    for i in 0 ..< fs.count {
        if _, below := memoryBelow(memoryPath(&fs.files[i]), path); below { return true, true }
    }
    return false, false
}

@(private)
memoryStart :: proc(user: rawptr, buffer: []u8) -> string {
    if len(buffer) < 1 { return "" }
    buffer[0] = '/'
    return string(buffer[:1])
}
