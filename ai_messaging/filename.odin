#+build !js
// File names that arrive from another computer are untrusted: the sender chooses them. They are reduced to one safe file name
// inside the receive folder (never a path, never "..", nothing Windows refuses), and an existing file is never overwritten.
package ai_messaging

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

// Writes the safe name into `buffer` and returns it. Never empty.
FileNameSafe :: proc(buffer: []byte, wanted: string) -> string {
    start: int
    for i in 0 ..< len(wanted) {
        if wanted[i] == '/' || wanted[i] == '\\' {
            start = i + 1
        }
    }
    name: string = wanted[start:]
    length: int
    for i in 0 ..< len(name) {
        if length >= min(len(buffer), FILE_NAME_MAX) {
            break
        }
        c: u8 = name[i]
        bad: bool = c < 32 || c == 127 || c == '<' || c == '>' || c == ':' || c == '"' || c == '|' || c == '?' || c == '*'
        buffer[length] = '_' if bad else c
        length += 1
    }
    // Windows does not take trailing dots or spaces, and a leading dot hides the file or means "." / ".."
    for length > 0 && (buffer[length - 1] == '.' || buffer[length - 1] == ' ') {
        length -= 1
    }
    first: int
    for first < length && (buffer[first] == '.' || buffer[first] == ' ') {
        first += 1
    }
    if first > 0 {
        copy(buffer[:length - first], buffer[first:length])
        length -= first
    }
    if length == 0 {
        return "file"
    }
    stem_end: int = length
    for i in 0 ..< length {
        if buffer[i] == '.' {
            stem_end = i
            break
        }
    }
    stem: string = strings.to_upper(string(buffer[:stem_end]), context.temp_allocator)
    reserved: bool = stem == "CON" || stem == "PRN" || stem == "AUX" || stem == "NUL"
    if len(stem) == 4 && (strings.has_prefix(stem, "COM") || strings.has_prefix(stem, "LPT")) && stem[3] >= '1' && stem[3] <= '9' {
        reserved = true
    }
    if reserved && length < len(buffer) {
        copy(buffer[1:length + 1], buffer[:length])
        buffer[0] = '_'
        length += 1
    }
    return string(buffer[:length])
}

// folder/name, or folder/name (1).ext, (2)... the first that does not exist yet. Temp allocator.
FileUniquePath :: proc(folder: string, name: string, suffix: string = "") -> string {
    path: string = fmt.tprintf("%s/%s%s", folder, name, suffix)
    if !os.exists(path) {
        return path
    }
    dot: int = strings.last_index_byte(name, '.')
    stem: string = name if dot <= 0 else name[:dot]
    extension: string = "" if dot <= 0 else name[dot:]
    for number in 1 ..< 1000 {
        path = fmt.tprintf("%s/%s (%d)%s%s", folder, stem, number, extension, suffix)
        if !os.exists(path) {
            return path
        }
    }
    return path
}

@(test)
FileNameSafeTest :: proc(t: ^testing.T) {
    buffer: [FILE_NAME_MAX]byte
    testing.expect_value(t, FileNameSafe(buffer[:], "report.pdf"), "report.pdf")
    testing.expect_value(t, FileNameSafe(buffer[:], "../../etc/passwd"), "passwd")
    testing.expect_value(t, FileNameSafe(buffer[:], `C:\Windows\system32\cmd.exe`), "cmd.exe")
    testing.expect_value(t, FileNameSafe(buffer[:], ".."), "file")
    testing.expect_value(t, FileNameSafe(buffer[:], ""), "file")
    testing.expect_value(t, FileNameSafe(buffer[:], "a/"), "file")
    testing.expect_value(t, FileNameSafe(buffer[:], ".bashrc"), "bashrc")
    testing.expect_value(t, FileNameSafe(buffer[:], "what?*.txt"), "what__.txt")
    testing.expect_value(t, FileNameSafe(buffer[:], "name. . ."), "name")
    testing.expect_value(t, FileNameSafe(buffer[:], "con.txt"), "_con.txt")
    testing.expect_value(t, FileNameSafe(buffer[:], "LPT1"), "_LPT1")
    testing.expect_value(t, FileNameSafe(buffer[:], "com10.txt"), "com10.txt")
    long: string = strings.repeat("x", 500, context.temp_allocator)
    testing.expect_value(t, len(FileNameSafe(buffer[:], long)), FILE_NAME_MAX)
}
