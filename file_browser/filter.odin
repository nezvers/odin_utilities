package file_browser

// File extension filters. A filter is a name for the dropdown ("Images") and the extensions it lets through. The strings are the caller's and have to live as long as the filter is used.

Filter :: struct {
    name: string,                   // shown in the dropdown
    extensions: []string,           // "png" or ".png" (the dot is optional, case does not matter), "tar.gz" is fine too. Empty, or "*": every file
}

// Does the file name pass the filter? A directory is never asked (the browser lists every directory). A name that is only an extension (".png", a hidden file) has no extension.
FilterMatches :: proc(filter: Filter, file_name: string) -> bool {
    if len(filter.extensions) == 0 { return true }
    for extension in filter.extensions {
        suffix: string = extension[1:] if len(extension) > 0 && extension[0] == '.' else extension
        if suffix == "*" { return true }
        if len(suffix) == 0 { continue }
        // the name ends with "." + suffix and something comes before the dot
        if len(file_name) < len(suffix) + 2 { continue }
        start: int = len(file_name) - len(suffix)
        if file_name[start - 1] != '.' { continue }
        if equalFold(file_name[start:], suffix) { return true }
    }
    return false
}

// "png,jpg": the extensions of a filter the way the `accept` attribute of a browser file chooser wants them (".png,.jpg"). Written into `buffer`; what does not fit is left out.
// A filter that lets everything through gives "".
FilterAccept :: proc(filter: Filter, buffer: []u8) -> string {
    used: int
    for extension in filter.extensions {
        suffix: string = extension[1:] if len(extension) > 0 && extension[0] == '.' else extension
        if suffix == "*" || len(suffix) == 0 { return "" }
        // a dot, the extension and a comma
        if used + len(suffix) + 2 > len(buffer) { break }
        if used > 0 {
            buffer[used] = ','
            used += 1
        }
        buffer[used] = '.'
        used += 1
        copy(buffer[used:], suffix)
        used += len(suffix)
    }
    return string(buffer[:used])
}

// The accept text of all the filters together (the web chooser has no dropdown of ours)
FiltersAccept :: proc(filters: []Filter, buffer: []u8) -> string {
    used: int
    for filter in filters {
        text: string = FilterAccept(filter, buffer[used:])
        if len(text) == 0 { return "" }
        used += len(text)
        if used < len(buffer) {
            buffer[used] = ','
            used += 1
        }
    }
    return string(buffer[:max(used - 1, 0)])
}

@(private)
equalFold :: proc(a: string, b: string) -> bool {
    if len(a) != len(b) { return false }
    for i in 0 ..< len(a) {
        if lower(a[i]) != lower(b[i]) { return false }
    }
    return true
}

@(private)
lower :: proc(c: u8) -> u8 {
    return c + ('a' - 'A') if c >= 'A' && c <= 'Z' else c
}

@(private)
compareFold :: proc(a: string, b: string) -> int {
    count: int = min(len(a), len(b))
    for i in 0 ..< count {
        x, y: u8 = lower(a[i]), lower(b[i])
        if x != y { return -1 if x < y else 1 }
    }
    if len(a) == len(b) { return 0 }
    return -1 if len(a) < len(b) else 1
}
