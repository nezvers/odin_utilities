package file_browser

// Paths as strings, no allocations: the results are slices of the argument or are written into a caller buffer. Both '/' and '\' separate names (a path typed on Windows or copied from a web page
// can have either); the separator that is written is the one of the platform, unless the directory already uses the other one.

PATH_MAX :: 1024
NAME_MAX :: 256
PATH_SEPARATOR :: '\\' when ODIN_OS == .Windows else '/'

PathIsSeparator :: proc(c: u8) -> bool {
    return c == '/' || c == '\\'
}

// "/" , "C:\" or "C:": nothing above it
PathIsRoot :: proc(path: string) -> bool {
    if len(path) == 1 && PathIsSeparator(path[0]) { return true }
    if len(path) == 2 && path[1] == ':' { return true }
    if len(path) == 3 && path[1] == ':' && PathIsSeparator(path[2]) { return true }
    return false
}

// The directory that holds the last name of the path ("/a/b" -> "/a", "C:\a" -> "C:\"). A trailing separator is ignored. The path of a root and a bare name have no parent: `ok` is false and
// `parent` is the path itself.
PathParent :: proc(path: string) -> (parent: string, ok: bool) {
    trimmed: string = path
    for len(trimmed) > 1 && PathIsSeparator(trimmed[len(trimmed) - 1]) && !PathIsRoot(trimmed) {
        trimmed = trimmed[:len(trimmed) - 1]
    }
    if PathIsRoot(trimmed) { return path, false }
    cut: int = -1
    for i := len(trimmed) - 1; i >= 0; i -= 1 {
        if PathIsSeparator(trimmed[i]) {
            cut = i
            break
        }
    }
    if cut < 0 { return path, false }
    if cut == 0 { return trimmed[:1], true }
    if cut == 2 && trimmed[1] == ':' { return trimmed[:3], true }
    return trimmed[:cut], true
}

// The last name of a path: "/a/b.png" -> "b.png". "" for a path that ends with a separator.
PathFileName :: proc(path: string) -> string {
    for i := len(path) - 1; i >= 0; i -= 1 {
        if PathIsSeparator(path[i]) { return path[i + 1:] }
    }
    return path
}

// The directory of a file path: "/a/b.png" -> "/a", "b.png" -> "". The root keeps its separator ("/b.png" -> "/").
PathDirectory :: proc(path: string) -> string {
    for i := len(path) - 1; i >= 0; i -= 1 {
        if PathIsSeparator(path[i]) {
            if i == 0 { return path[:1] }
            if i == 2 && path[1] == ':' { return path[:3] }
            return path[:i]
        }
    }
    return ""
}

// The extension without the dot, "" for none: "a.PNG" -> "PNG", ".hidden" -> "", "a.tar.gz" -> "gz"
PathExtension :: proc(file_name: string) -> string {
    name: string = PathFileName(file_name)
    for i := len(name) - 1; i > 0; i -= 1 {
        if name[i] == '.' { return name[i + 1:] }
    }
    return ""
}

// dir + separator + name into `buffer`. False when it does not fit (the buffer is left alone). An empty directory gives the name, a directory that ends with a separator does not get a second one.
PathJoin :: proc(buffer: []u8, dir: string, name: string) -> (path: string, ok: bool) {
    if len(dir) == 0 {
        if len(name) > len(buffer) { return "", false }
        copy(buffer, name)
        return string(buffer[:len(name)]), true
    }
    separator: u8 = PATH_SEPARATOR
    for c in transmute([]u8)dir {
        if PathIsSeparator(c) {
            separator = c
            break
        }
    }
    needs: bool = !PathIsSeparator(dir[len(dir) - 1])
    total: int = len(dir) + (1 if needs else 0) + len(name)
    if total > len(buffer) { return "", false }
    copy(buffer, dir)
    used: int = len(dir)
    if needs {
        buffer[used] = separator
        used += 1
    }
    copy(buffer[used:], name)
    return string(buffer[:total]), true
}
